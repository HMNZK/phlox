import Foundation

/// commit / push / PR 作成の失敗理由（task-4 契約）。
///
/// **git の失敗出力を握りつぶさない**ことが契約の核心。`commandFailed` は実行した引数と
/// 出力（stdout+stderr）をそのまま保持し、UI がユーザーへ提示できるようにする。
public enum GitWorkflowError: Error, Equatable {
    case notARepository
    case noStagedChanges
    case noPathsSelected
    case emptyCommitMessage
    case unmergedChanges
    case noRemoteConfigured
    case gitHubCLIUnavailable
    case commandFailed(arguments: [String], output: String)
}

/// ワーキングツリーの変更を commit / push し、PR を作る（task-4 契約）。
///
/// 受け入れテスト `GitWorkflowTests` が凍結する。
/// 読み取り専用の `WorkingTreeService` と対になる書き込み側（ADR 0204）。
public actor GitWorkflowService {
    private let repositoryRoot: URL
    private let gitHubCLIPath: String?
    /// `rev-parse --show-toplevel` で解決した作業ツリー根。pathspec はここ相対。
    private var workingTreeRoot: URL?
    /// `remoteNames()` が空を返したとき、それが「リモート未設定」なのか
    /// `git remote` 自体の失敗なのかを UI が区別するための最終失敗理由。
    /// 成功して空（リモート無し）のときは `nil`。
    private var lastRemoteLookupFailure: String?

    /// - Parameters:
    ///   - repositoryRoot: 対象リポジトリのルート。
    ///   - gitHubCLIPath: `gh` の絶対パス。`nil` なら PATH から探索する。
    ///     テストで不在時の挙動を決定的に再現するために注入可能にしてある。
    public init(repositoryRoot: URL, gitHubCLIPath: String? = nil) {
        self.repositoryRoot = repositoryRoot
        self.gitHubCLIPath = gitHubCLIPath
    }

    func perform(_ action: GitRepositoryAction) throws {
        try requireRepository()
        switch action {
        case .switchBranch(let name):
            try validateBranchName(name)
            try runGitAllowingFailure(arguments: ["switch", "--", name])
        case .createBranch(let name, let start, let switchTo):
            try validateBranchName(name)
            if start == "HEAD", switchTo {
                try runGitAllowingFailure(arguments: ["switch", "-c", name])
                return
            }
            let resolved = try runGitAllowingFailure(arguments: ["rev-parse", "--verify", "--end-of-options", start + "^{commit}"])
            let id = String(decoding: resolved.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            try runGitAllowingFailure(arguments: switchTo ? ["switch", "-c", name, id] : ["branch", "--", name, id])
        case .renameBranch(let old, let new):
            try validateBranchName(old)
            try validateBranchName(new)
            try runGitAllowingFailure(arguments: ["branch", "-m", "--", old, new])
        case .deleteBranch(let name, let force):
            try validateBranchName(name)
            try runGitAllowingFailure(arguments: ["branch", force ? "-D" : "-d", "--", name])
        case .checkoutRemote(let name):
            let parts = name.split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else { throw GitWorkflowError.commandFailed(arguments: ["switch"], output: "Invalid remote branch: " + name) }
            let local = String(parts[1])
            try validateBranchName(local)
            let exists = try runGitRaw(arguments: ["show-ref", "--verify", "--quiet", "refs/heads/" + local])
            if exists.terminationStatus == 0 { try runGitAllowingFailure(arguments: ["switch", "--", local]) }
            else { try runGitAllowingFailure(arguments: ["switch", "--track", "-c", local, "refs/remotes/" + name]) }
        case .fetch:
            try runGitAllowingFailure(arguments: ["fetch", "--all"])
        case .stash(let message):
            try runGitAllowingFailure(arguments: ["stash", "push", "--include-untracked"] + (message.isEmpty ? [] : ["-m", message]))
        case .applyStash(let id):
            try runGitAllowingFailure(arguments: ["stash", "apply", try stashName(for: id)])
        case .popStash(let id):
            try runGitAllowingFailure(arguments: ["stash", "pop", try stashName(for: id)])
        case .dropStash(let id):
            try runGitAllowingFailure(arguments: ["stash", "drop", try stashName(for: id)])
        }
    }

    private func validateBranchName(_ name: String) throws {
        guard !name.hasPrefix("-"), !name.contains("\0"), !name.hasPrefix("@{-") else {
            throw GitWorkflowError.commandFailed(arguments: ["check-ref-format", "--branch", name], output: "Invalid branch name: " + name)
        }
        try runGitAllowingFailure(arguments: ["check-ref-format", "--branch", name])
    }

    /// 番号は外部の操作で移動するため、一覧のIDを現在の reflog に解決し直す。
    private func stashName(for id: String) throws -> String {
        let result = try runGitAllowingFailure(arguments: ["stash", "list", "--format=%H%x09%gd"])
        for line in String(decoding: result.output, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: "\t")
            if fields.count == 2, fields[0] == id { return String(fields[1]) }
        }
        throw GitWorkflowError.commandFailed(arguments: ["stash", "list"], output: "Stash no longer exists: " + id)
    }

    /// index にある内容だけをコミットする。作業ツリーの内容やステージ状態を変更しない。
    public func commit(message: String) async throws -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else { throw GitWorkflowError.emptyCommitMessage }
        try requireRepository()
        let unmerged = try runGitAllowingFailure(arguments: ["ls-files", "--unmerged", "-z"])
        guard unmerged.output.isEmpty else { throw GitWorkflowError.unmergedChanges }
        let staged = try runGitAllowingFailure(arguments: ["diff", "--cached", "--name-only", "-z"])
        guard !staged.output.isEmpty else { throw GitWorkflowError.noStagedChanges }
        try runGitAllowingFailure(arguments: ["commit", "-m", trimmedMessage])
        let result = try runGitAllowingFailure(arguments: ["rev-parse", "HEAD"])
        return String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func stage(paths: [String]) async throws {
        try requireRepository()
        try validatePaths(paths)
        let snapshot = try await WorkingTreeService(repositoryRoot: workingTreeRoot ?? repositoryRoot).snapshot()
        guard Set(paths).isDisjoint(with: snapshot.conflictedPaths) else { throw GitWorkflowError.unmergedChanges }
        let renameSources = try renameSourcesByDestination(source: .worktree)
        let deleted = Set(snapshot.unstagedChanges.filter { $0.kind == .deleted }.map(\.path))
        let removals = Set(paths.filter { deleted.contains($0) } + paths.compactMap { renameSources[$0] })
        let additions = paths.filter { !deleted.contains($0) }
        for path in removals.sorted() {
            try runGitAllowingFailure(arguments: ["rm", "--cached", "--quiet", "--"] + Self.literalPathspecs([path]))
        }
        if !additions.isEmpty {
            try runGitAllowingFailure(arguments: ["add", "-A", "--"] + Self.literalPathspecs(additions))
        }
    }

    public func unstage(paths: [String]) async throws {
        try requireRepository()
        try validatePaths(paths)
        let expanded = try expandPathsWithRenameSources(paths, source: .staged)
        let snapshot = try await WorkingTreeService(repositoryRoot: workingTreeRoot ?? repositoryRoot).snapshot()
        guard Set(expanded).isDisjoint(with: snapshot.conflictedPaths) else { throw GitWorkflowError.unmergedChanges }
        let head = try runGitRaw(arguments: ["rev-parse", "--verify", "HEAD"])
        var removals: [String] = []
        var restorations: [(path: String, mode: String, id: String)] = []
        var seen: Set<String> = []
        for path in expanded where seen.insert(path).inserted {
            if head.terminationStatus == 0 {
                let tree = try runGitAllowingFailure(arguments: ["ls-tree", "-z", "HEAD", "--"] + Self.literalPathspecs([path]))
                let entry = tree.output.split(separator: 0).first { record in
                    record.split(separator: 9, maxSplits: 1).last.map { String(decoding: $0, as: UTF8.self) == path } == true
                }
                if let entry {
                    let metadata = entry.split(separator: 9, maxSplits: 1)[0].split(separator: 32)
                    // cacheinfo は pathspec ではなく完全一致のindex項目を受け取る。
                    if metadata.count == 3, metadata[1] != Data("tree".utf8)[...] {
                        restorations.append((path, String(decoding: metadata[0], as: UTF8.self), String(decoding: metadata[2], as: UTF8.self)))
                        continue
                    }
                }
            }
            removals.append(path)
        }
        for path in removals {
            try runGitAllowingFailure(arguments: ["rm", "--cached", "--quiet", "--"] + Self.literalPathspecs([path]))
        }
        // 同名の子の追加を先に外し、選択外の子と衝突する復元は Git に拒否させる。
        for entry in restorations.sorted(by: { $0.path.split(separator: "/").count > $1.path.split(separator: "/").count }) {
            try runGitAllowingFailure(arguments: ["update-index", "--add", "--cacheinfo", entry.mode, entry.id, entry.path])
        }
    }

    private func validatePaths(_ paths: [String]) throws {
        guard !paths.isEmpty else { throw GitWorkflowError.noPathsSelected }
        for path in paths {
            _ = try WorkingTreeService.relativeURL(for: path, relativeTo: workingTreeRoot ?? repositoryRoot)
        }
    }

    /// upstream がないブランチでは既定のリモートブランチとの差を使う。
    public func aheadCount() async throws -> Int {
        try requireRepository()
        guard try runGitRaw(arguments: ["rev-parse", "--verify", "HEAD"]).terminationStatus == 0 else { return 0 }
        let upstream = try runGitRaw(arguments: ["rev-parse", "--verify", "@{upstream}"])
        var base: String?
        if upstream.terminationStatus == 0 { base = "@{upstream}" }
        else if let remote = preferredRemote(in: await remoteNames()) {
            let branch = try runGitRaw(arguments: ["symbolic-ref", "--quiet", "refs/remotes/" + remote + "/HEAD"])
            if branch.terminationStatus == 0 {
                base = String(decoding: branch.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        let arguments = ["rev-list", "--count", base.map { $0 + "..HEAD" } ?? "HEAD"]
        let count = try runGitAllowingFailure(arguments: arguments)
        return Int(String(decoding: count.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    func pushState() throws -> (hasCommit: Bool, hasBranch: Bool, hasUpstream: Bool) {
        try requireRepository()
        return (
            try runGitRaw(arguments: ["rev-parse", "--verify", "HEAD"]).terminationStatus == 0,
            try runGitRaw(arguments: ["symbolic-ref", "--quiet", "HEAD"]).terminationStatus == 0,
            try runGitRaw(arguments: ["rev-parse", "--verify", "@{upstream}"]).terminationStatus == 0
        )
    }

    public func hasPushedBranch() async throws -> Bool {
        try requireRepository()
        let result = try runGitRaw(arguments: ["rev-parse", "--verify", "@{upstream}"])
        guard result.terminationStatus == 0 else { return false }
        return try await aheadCount() == 0
    }

    /// 設定済みリモート名の一覧。
    ///
    /// 非リポジトリや `git remote` 失敗時は空配列を返す（凍結受け入れが非 throwing を固定）。
    /// 失敗と「リモート未設定」の区別は `remoteLookupFailureReason` を見る。
    public func remoteNames() async -> [String] {
        lastRemoteLookupFailure = nil
        do {
            try requireRepository()
        } catch {
            lastRemoteLookupFailure = "Git リポジトリではありません。"
            return []
        }

        let result: CommandResult
        do {
            result = try runGitRaw(arguments: ["remote"])
        } catch {
            lastRemoteLookupFailure = "git remote の実行に失敗しました。"
            return []
        }
        guard result.terminationStatus == 0 else {
            let detail = combinedOutput(result).trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                lastRemoteLookupFailure = "git remote の実行に失敗しました。"
            } else {
                lastRemoteLookupFailure = "git remote の実行に失敗しました: \(detail)"
            }
            return []
        }
        return String(decoding: result.output, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// `remoteNames()` が空を返した直後の失敗理由。リモート未設定なら `nil`。
    public func remoteLookupFailureReason() -> String? {
        lastRemoteLookupFailure
    }

    /// 直近コミットの subject（`git log -1 --format=%s`）。HEAD が無ければ throw。
    public func latestCommitSubject() async throws -> String {
        try requireRepository()
        let result = try runGitAllowingFailure(arguments: ["log", "-1", "--format=%s"])
        return String(decoding: result.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 現在のブランチを push する。リモート未設定なら `.noRemoteConfigured`。
    public func push() async throws {
        try requireRepository()
        let remotes = await remoteNames()
        guard let remote = preferredRemote(in: remotes) else {
            throw GitWorkflowError.noRemoteConfigured
        }
        // upstream 未設定の初回でも通るよう remote + HEAD を明示する。
        try runGitAllowingFailure(arguments: ["push", "-u", remote, "HEAD"])
    }

    /// `gh` が利用可能か。
    public func isGitHubCLIAvailable() async -> Bool {
        resolvedGitHubCLIPath() != nil
    }

    /// PR を作成し、その URL を返す。`gh` が無ければ `.gitHubCLIUnavailable`。
    public func createPullRequest(title: String, body: String) async throws -> String {
        guard let gh = resolvedGitHubCLIPath() else {
            throw GitWorkflowError.gitHubCLIUnavailable
        }
        try requireRepository()
        let result = try runProcess(
            executable: gh,
            arguments: ["pr", "create", "--title", title, "--body", body]
        )
        guard result.terminationStatus == 0 else {
            throw GitWorkflowError.commandFailed(
                arguments: ["pr", "create", "--title", title, "--body", body],
                output: combinedOutput(result)
            )
        }
        let url = String(decoding: result.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            throw GitWorkflowError.commandFailed(
                arguments: ["pr", "create", "--title", title, "--body", body],
                output: combinedOutput(result)
            )
        }
        return url
    }

    // MARK: - pathspec / renamed paths

    /// pathspec の glob / magic 解釈を止め、ファイル名を文字どおり扱う。
    nonisolated static func literalPathspecs(_ paths: [String]) -> [String] {
        paths.map { ":(literal)" + $0 }
    }

    /// 改名の行には新パスしか表示しないため、旧パスの削除も操作に含める。
    private func expandPathsWithRenameSources(_ paths: [String], source: WorkingTreeSource) throws -> [String] {
        let renameSources = try renameSourcesByDestination(source: source)
        guard !renameSources.isEmpty else { return paths }
        var expanded = paths
        for path in paths {
            if let oldPath = renameSources[path] {
                expanded.append(oldPath)
            }
        }
        return expanded
    }

    /// ステージ済みリネームの新パス → 旧パス。`git status --porcelain=v1 -z` から読む。
    ///
    /// `-z` が要る理由: 既定の出力はパスに空白・非 ASCII が含まれると引用と C エスケープが掛かり
    /// （`R  "sp ace.txt" -> "sp ace2.txt"`）、生パスを返す変更一覧側（`WorkingTreeService`）の
    /// キーと一致しなくなる。読み方はその `statusEntries` と同じ流儀に揃える
    /// （`\0` 区切り・状態 2 文字＋空白＋パス・R/C は次レコードが旧パス）。
    private func renameSourcesByDestination(source: WorkingTreeSource) throws -> [String: String] {
        let result = try runGitAllowingFailure(arguments: ["status", "--porcelain=v1", "-z"])
        let records = result.output.split(separator: 0, omittingEmptySubsequences: false)
        var map: [String: String] = [:]
        var index = 0
        while index < records.count {
            let record = records[index]
            guard record.count >= 3, let indexStatus = record.first else {
                index += 1
                continue
            }
            let worktreeStatus = record[record.index(after: record.startIndex)]
            let isRenameOrCopy = [indexStatus, worktreeStatus].contains(82) || [indexStatus, worktreeStatus].contains(67) // R / C
            guard isRenameOrCopy else {
                index += 1
                continue
            }
            // コピー（C）は旧パスがツリーに残るので補わない。削除を伴うリネーム（R）だけを対象にする。
            if (source == .staged ? indexStatus : worktreeStatus) == 82, index + 1 < records.count {
                let newPath = String(decoding: record.dropFirst(3), as: UTF8.self)
                let oldPath = String(decoding: records[index + 1], as: UTF8.self)
                if !newPath.isEmpty, !oldPath.isEmpty {
                    map[newPath] = oldPath
                }
            }
            index += 2
        }
        return map
    }

    // MARK: - repository / remotes

    private func requireRepository() throws {
        if workingTreeRoot != nil { return }
        let result = try runProcess(
            executable: "/usr/bin/git",
            arguments: ["rev-parse", "--show-toplevel"],
            directory: repositoryRoot
        )
        let path = String(decoding: result.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.terminationStatus == 0, !path.isEmpty else {
            throw GitWorkflowError.notARepository
        }
        workingTreeRoot = URL(fileURLWithPath: path, isDirectory: true)
    }

    private func preferredRemote(in remotes: [String]) -> String? {
        if remotes.contains("origin") { return "origin" }
        return remotes.first
    }

    private func resolvedGitHubCLIPath() -> String? {
        if let gitHubCLIPath {
            return FileManager.default.isExecutableFile(atPath: gitHubCLIPath)
                ? gitHubCLIPath
                : nil
        }
        return findExecutable(named: "gh")
    }

    private func findExecutable(named name: String) -> String? {
        let pathEnv = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/usr/bin:/bin"
        for directory in pathEnv.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(name)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - process execution（WorkingTreeService.runGit と同型）

    private struct CommandResult {
        let terminationStatus: Int32
        let output: Data
        let errorOutput: Data
    }

    private final class DataCapture: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func store(_ data: Data) {
            lock.lock()
            defer { lock.unlock() }
            self.data = data
        }

        func value() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    @discardableResult
    private func runGitAllowingFailure(arguments: [String]) throws -> CommandResult {
        let result = try runGitRaw(arguments: arguments)
        guard result.terminationStatus == 0 else {
            throw GitWorkflowError.commandFailed(
                arguments: arguments,
                output: combinedOutput(result)
            )
        }
        return result
    }

    private func runGitRaw(arguments: [String]) throws -> CommandResult {
        // 書き込み操作には --no-optional-locks を付けない（index 更新が本体のため）。
        let directory = workingTreeRoot ?? repositoryRoot
        return try runProcess(
            executable: "/usr/bin/git",
            arguments: arguments,
            directory: directory
        )
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        directory: URL? = nil
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory ?? workingTreeRoot ?? repositoryRoot

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
        } catch {
            throw GitWorkflowError.commandFailed(
                arguments: arguments,
                output: error.localizedDescription
            )
        }

        try output.fileHandleForWriting.close()
        try errorOutput.fileHandleForWriting.close()

        let outputCapture = DataCapture()
        let errorCapture = DataCapture()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputCapture.store(output.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errorCapture.store(errorOutput.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        process.waitUntilExit()
        readers.wait()
        return CommandResult(
            terminationStatus: process.terminationStatus,
            output: outputCapture.value(),
            errorOutput: errorCapture.value()
        )
    }

    private func combinedOutput(_ result: CommandResult) -> String {
        let stdout = String(decoding: result.output, as: UTF8.self)
        let stderr = String(decoding: result.errorOutput, as: UTF8.self)
        switch (stdout.isEmpty, stderr.isEmpty) {
        case (false, false):
            return stdout + stderr
        case (false, true):
            return stdout
        case (true, false):
            return stderr
        case (true, true):
            return ""
        }
    }
}
