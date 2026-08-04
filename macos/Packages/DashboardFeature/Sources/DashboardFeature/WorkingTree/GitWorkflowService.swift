import Foundation

/// commit / push / PR 作成の失敗理由（task-4 契約）。
///
/// **git の失敗出力を握りつぶさない**ことが契約の核心。`commandFailed` は実行した引数と
/// 出力（stdout+stderr）をそのまま保持し、UI がユーザーへ提示できるようにする。
public enum GitWorkflowError: Error, Equatable {
    case notARepository
    case noPathsSelected
    case emptyCommitMessage
    case noRemoteConfigured
    case gitHubCLIUnavailable
    case commandFailed(arguments: [String], output: String)
}

/// ワーキングツリーの変更を commit / push し、PR を作る（task-4 契約）。
///
/// 受け入れテスト `AcceptanceGitWorkflowTests` が凍結する。
/// 読み取り専用の `WorkingTreeService` と対になる書き込み側（ADR 0169）。
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

    /// 指定したパスだけをステージしてコミットする。
    ///
    /// - Returns: 作成されたコミットの SHA。
    /// - Throws: `.noPathsSelected`（paths が空／空文字のみ）/ `.emptyCommitMessage`（空白のみを含む）/
    ///   `.notARepository` / `.commandFailed`。
    /// - Note: **選択していないパスの変更はワーキングツリーに残る**（全ステージしない）。
    ///   他パスの既存ステージ済みエントリもコミットに巻き込まない（`git commit -- <paths>`＝`--only`）。
    ///   pathspec は `:(literal)` でワイルドカード／magic 解釈を止める。
    ///   `add` は index に無い（未追跡）パスだけに限定し、commit 失敗時は
    ///   `git rm --cached` でその分だけ戻す（`.git/index` を直接差し替えない）。
    public func commit(paths: [String], message: String) async throws -> String {
        guard !paths.isEmpty else {
            throw GitWorkflowError.noPathsSelected
        }
        // `:(literal)` + 空文字は git が「全ファイル」と解釈するため、ここで拒否する。
        guard !paths.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) else {
            throw GitWorkflowError.noPathsSelected
        }
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            throw GitWorkflowError.emptyCommitMessage
        }
        try requireRepository()

        let commitPaths = try expandPathsWithStagedRenameSources(paths)
        let literalPaths = Self.literalPathspecs(commitPaths)
        // `commit -- <paths>` は既に `--only` 意味論なので、追跡済みパスは add 不要。
        // ワークツリーに実在するが index に無いパスだけ add し、失敗時は `rm --cached` で戻す
        // （ステージ済み削除は index にもワークツリーにも無いため add 不要）。
        let untrackedPaths = try pathsNeedingAddBeforeCommit(paths)
        let literalUntracked = Self.literalPathspecs(untrackedPaths)
        if !literalUntracked.isEmpty {
            try runGitAllowingFailure(arguments: ["add", "--"] + literalUntracked)
        }
        do {
            try runGitAllowingFailure(arguments: ["commit", "-m", trimmedMessage, "--"] + literalPaths)
        } catch let commitError {
            if !literalUntracked.isEmpty {
                do {
                    try runGitAllowingFailure(
                        arguments: ["rm", "--cached", "-f", "--"] + literalUntracked
                    )
                } catch let restoreFailure {
                    // 復元失敗を握りつぶさない。主因は commit 失敗なのでそこに追記する。
                    if case let .commandFailed(arguments, output) = commitError as? GitWorkflowError {
                        throw GitWorkflowError.commandFailed(
                            arguments: arguments,
                            output: output
                                + "\nunstage after failed commit also failed: \(restoreFailure)"
                        )
                    }
                    throw commitError
                }
            }
            throw commitError
        }

        let shaResult = try runGitAllowingFailure(arguments: ["rev-parse", "HEAD"])
        return String(decoding: shaResult.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    // MARK: - pathspec / untracked staging

    /// pathspec の glob / magic 解釈を止め、ファイル名を文字どおり扱う。
    static func literalPathspecs(_ paths: [String]) -> [String] {
        paths.map { ":(literal)" + $0 }
    }

    /// index に無いがワークツリーに実在するパス。これらだけ `git add` が必要。
    private func pathsNeedingAddBeforeCommit(_ paths: [String]) throws -> [String] {
        let absentFromIndex = try pathsAbsentFromIndex(paths)
        guard let workingTreeRoot else {
            return absentFromIndex
        }
        return try absentFromIndex.filter { path in
            let fullPath = workingTreeRoot.appendingPathComponent(path).path
            do {
                // `fileExists` ではなく属性取得を使うのは、壊れた symlink（リンク先が無い）も
                // 「実在する」と数えるため（`attributesOfItem` は lstat 相当）。
                _ = try FileManager.default.attributesOfItem(atPath: fullPath)
                return true
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                // 実在しない＝`git add` の対象外。これは失敗ではなく判定結果なので握りつぶしではない。
                return false
            }
            // 権限不足・親が非ディレクトリ等で「実在するか」を判定できない場合は、
            // 契約の不変条件どおり理由を握りつぶさずそのまま投げる。
        }
    }

    /// ステージ済みリネームの新パスが選ばれたとき、旧パスを pathspec に補う。
    /// 変更一覧は新パス 1 件しか返さないが、`git commit -- <new>` だけでは
    /// 旧パスの削除が取り残され HEAD に二重に残る。
    private func expandPathsWithStagedRenameSources(_ paths: [String]) throws -> [String] {
        let renameSources = try stagedRenameSourcesByDestination()
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
    private func stagedRenameSourcesByDestination() throws -> [String: String] {
        let result = try runGitRaw(arguments: ["status", "--porcelain=v1", "-z"])
        let records = result.output.split(separator: 0, omittingEmptySubsequences: false)
        var map: [String: String] = [:]
        var index = 0
        while index < records.count {
            let record = records[index]
            guard record.count >= 3, let indexStatus = record.first else {
                index += 1
                continue
            }
            let isRenameOrCopy = indexStatus == 82 || indexStatus == 67 // R / C
            guard isRenameOrCopy else {
                index += 1
                continue
            }
            // コピー（C）は旧パスがツリーに残るので補わない。削除を伴うリネーム（R）だけを対象にする。
            if indexStatus == 82, index + 1 < records.count {
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

    /// index にまだ載っていないパス。
    private func pathsAbsentFromIndex(_ paths: [String]) throws -> [String] {
        let literal = Self.literalPathspecs(paths)
        let result = try runGitRaw(arguments: ["ls-files", "--full-name", "-z", "--"] + literal)
        let tracked = Set(
            String(decoding: result.output, as: UTF8.self)
                .split(separator: "\0", omittingEmptySubsequences: true)
                .map(String.init)
        )
        return paths.filter { !tracked.contains($0) }
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
