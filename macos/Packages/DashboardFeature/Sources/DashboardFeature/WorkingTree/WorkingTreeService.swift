import Foundation

public enum WorkingTreeServiceError: Error, Sendable {
    case notRepository
    case invalidRelativePath(String)
    case gitCommandFailed(arguments: [String], output: String)
    case outsideRoot(String)
    case notRegularFile(String)
    case missingRoot(String)
}

public enum WorkingTreeTextError: Error, Sendable {
    case tooLarge
    case binary
    case invalidUTF8
}

public enum WorkingTreeText {
    public static let maximumHighlightedFileSize = 1_000_000
    public static let maximumEditableFileSize = 5_000_000
    public static let maximumReadableFileSize = 20_000_000

    public static func shouldHighlight(_ text: String, bomByteCount: Int = 0) -> Bool {
        let limit = maximumHighlightedFileSize - bomByteCount
        let length = (text as NSString).length
        if length > limit { return false }
        if length <= limit / 3 { return true }
        return text.utf8.count <= limit
    }

    public static func decode(_ data: Data) throws -> (text: String, bom: Data) {
        guard data.count <= maximumReadableFileSize else { throw WorkingTreeTextError.tooLarge }
        guard !data.prefix(8_192).contains(0) else { throw WorkingTreeTextError.binary }
        let bom = data.starts(with: [0xEF, 0xBB, 0xBF]) ? Data([0xEF, 0xBB, 0xBF]) : Data()
        return (try decodeUTF8(Data(data.dropFirst(bom.count))), bom)
    }

    static func decodeUTF8(_ data: Data) throws -> String {
        let text = String(decoding: data, as: UTF8.self)
        guard text.utf8.elementsEqual(data) else { throw WorkingTreeTextError.invalidUTF8 }
        return text
    }
}

private struct GitCommandResult {
    let terminationStatus: Int32
    let output: Data
    let errorOutput: Data
}

private struct StatusEntry {
    let path: String
    let kind: WorkingTreeChange.Kind
    var originalPath: String? = nil
    var indexStatus: UInt8 = 32
    var worktreeStatus: UInt8 = 32
}

private final class GitDataCapture: @unchecked Sendable {
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

/// リポジトリのワーキングツリーを読み書きする、git CLI の薄いラッパー。
public actor WorkingTreeService {
    static let maximumHTMLResourceSize = 32 * 1024 * 1024

    private let repositoryRoot: URL
    private let fixedRoot: Bool

    public init(repositoryRoot: URL, fixedRoot: Bool = false) {
        self.repositoryRoot = fixedRoot ? repositoryRoot.standardizedFileURL.resolvingSymlinksInPath() : repositoryRoot
        self.fixedRoot = fixedRoot
    }

    public func isGitRepository() -> Bool {
        let result = try? runGit(["rev-parse", "--is-inside-work-tree"])
        return result?.terminationStatus == 0
            && String(decoding: result?.output ?? Data(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    /// 取得に失敗した一覧は混在させず、既定の HEAD だけに戻す（WS-2）。
    func referenceNames(prefix: String) throws -> [String] {
        let arguments = ["for-each-ref", "--sort=-committerdate", "--format=%(refname)%09%(symref)", prefix]
        let result = try runGit(arguments)
        try requireSuccessful(result, arguments: arguments)
        return String(decoding: result.output, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 2, fields[1].isEmpty, fields[0].hasPrefix(prefix) else { return nil }
            return String(fields[0].dropFirst(prefix.count))
        }
    }

    func worktreeStartPoints() -> [WorktreeStartPointItem] {
        do {
            var items = [WorktreeStartPointItem(point: .head)]
            for (prefix, makePoint) in [
                ("refs/heads/", WorktreeStartPoint.localBranch),
                ("refs/remotes/", WorktreeStartPoint.remoteBranch),
                ("refs/tags/", WorktreeStartPoint.tag),
            ] {
                items += try referenceNames(prefix: prefix).map { .init(point: makePoint($0)) }
            }
            let arguments = ["log", "-30", "--format=%H%x09%s", "HEAD", "--"]
            let result = try runGit(arguments)
            try requireSuccessful(result, arguments: arguments)
            items += String(decoding: result.output, as: UTF8.self).split(whereSeparator: \.isNewline).compactMap { line in
                let fields = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
                guard fields.count == 2 else { return nil }
                return .init(point: .commit(String(fields[0])), summary: String(fields[1]))
            }
            return items
        } catch {
            return [.init(point: .head)]
        }
    }

    func worktreeCommit(matching query: String) throws -> WorktreeStartPoint? {
        guard WorktreeStartPoint.isCommitID(query) else { return nil }
        let arguments = ["rev-parse", "--verify", "--quiet", query + "^{commit}"]
        let result = try runGit(arguments)
        guard result.terminationStatus == 0 else { return nil }
        return .commit(String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func resolveWorktreeStartPoint(_ point: WorktreeStartPoint) throws -> String {
        let arguments = ["rev-parse", "--verify", "--quiet", "--end-of-options", point.revision + "^{commit}"]
        let result = try runGit(arguments)
        guard result.terminationStatus == 0 else { throw WorktreeStartPointError(point: point) }
        return String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// このサービスの作業ディレクトリから解決した Git リポジトリのルート。
    /// `requireRepository()` を通すことで、他の Git 読み取りと同じ実行規則を使う。
    public func resolvedRepositoryRootPath() -> String? {
        guard let repositoryURL = try? requireRepository() else { return nil }
        return repositoryURL.path
    }

    /// Git 管理外と取得失敗を分け、detached HEAD は短縮名を表示する。
    func branchLabel() -> String {
        guard FileManager.default.fileExists(atPath: repositoryRoot.path) else { return "" }
        guard let probe = try? runGit(["rev-parse", "--is-inside-work-tree"]) else { return "" }
        guard probe.terminationStatus == 0 else {
            let reason = String(decoding: probe.errorOutput, as: UTF8.self)
            return reason.contains("not a git repository") ? "Git 管理外" : ""
        }
        if let branch = try? runGit(["symbolic-ref", "--short", "HEAD"]), branch.terminationStatus == 0 {
            return String(decoding: branch.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let head = try? runGit(["rev-parse", "--short", "HEAD"]), head.terminationStatus == 0 else { return "" }
        return String(decoding: head.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) + " detached HEAD"
    }

    public func changes() throws -> [WorkingTreeChange] {
        try snapshot().changes
    }

    /// 両方の変更一覧が一度の取得結果を参照する。本文は未追跡の行数と選択差分だけ読む。
    func snapshot() throws -> WorkingTreeSnapshot {
        let root = try requireRepository().resolvingSymlinksInPath().standardizedFileURL
        let entries = try statusEntries(in: root)
        let args = hasHEAD(in: root)
            ? ["diff", "--no-ext-diff", "--numstat", "-z", "HEAD"]
            : ["diff", "--no-ext-diff", "--numstat", "-z", "--cached"]
        let result = try runGit(args, in: root)
        try requireSuccessful(result, arguments: args)
        let binaryPaths = Self.parseBinaryPaths(result.output)
        // 旧一覧だけはパス単位。出どころ別一覧には集約前の XY レコードを使う。
        let legacyEntries = Dictionary(grouping: entries, by: \.path).values.compactMap { records in
            records.first { $0.kind == .untracked } ?? records.first
        }
        let changes = legacyEntries.map { entry in
            let url = try? Self.containedURL(Self.relativeURL(for: entry.path, relativeTo: root), under: root)
            let binary = binaryPaths.contains(entry.path) || (url.map { isBinaryFile(at: $0) } ?? false)
            return WorkingTreeChange(path: entry.path, kind: entry.kind, isBinary: binary)
        }.sorted { $0.path < $1.path }
        var counts = Self.parseLineCounts(result.output)
        for change in changes where change.kind == .untracked && !change.isBinary {
            if let count = try? untrackedLineCount(change.path, root: root) {
                counts[change.path] = .init(added: count, deleted: 0)
            }
        }
        func group(_ source: WorkingTreeSource, binaryPaths: Set<String>) -> [WorkingTreeChange] {
            entries.compactMap { entry in
                guard !GitTabPolicy.isUnmerged(index: entry.indexStatus, worktree: entry.worktreeStatus) else { return nil }
                let status = source == .staged ? entry.indexStatus : entry.worktreeStatus
                guard status != 32, status != 63 || source == .worktree else { return nil }
                let kind = status == 63 ? WorkingTreeChange.Kind.untracked : changeKind(for: Data([status])[...])
                let binary = binaryPaths.contains(entry.path) || (kind == .untracked && (changes.first { $0.path == entry.path }?.isBinary ?? false))
                return .init(path: entry.path, kind: kind, isBinary: binary)
            }.sorted { $0.path < $1.path }
        }
        func sourceStats(_ source: WorkingTreeSource) throws -> (counts: [String: WorkingTreeLineCount], binaryPaths: Set<String>) {
            var arguments = ["diff", "--no-ext-diff", "--numstat", "-z"]
            if source == .staged { arguments.append("--cached") }
            let result = try runGit(arguments, in: root)
            try requireSuccessful(result, arguments: arguments)
            var counts = Self.parseLineCounts(result.output)
            if source == .worktree {
                for change in changes where change.kind == .untracked && !change.isBinary {
                    // 行数は補助情報。読めないリンクや大容量でも変更一覧自体は残す。
                    if let count = try? untrackedLineCount(change.path, root: root) {
                        counts[change.path] = .init(added: count, deleted: 0)
                    }
                }
            }
            return (counts, Self.parseBinaryPaths(result.output))
        }
        let stagedStats = try sourceStats(.staged)
        let unstagedStats = try sourceStats(.worktree)
        return .init(branch: branchLabel(), changes: changes, lineCounts: counts,
                     stagedChanges: group(.staged, binaryPaths: stagedStats.binaryPaths),
                     unstagedChanges: group(.worktree, binaryPaths: unstagedStats.binaryPaths),
                     conflictedPaths: entries.filter { GitTabPolicy.isUnmerged(index: $0.indexStatus, worktree: $0.worktreeStatus) }.map(\.path).sorted(),
                     stagedLineCounts: stagedStats.counts, unstagedLineCounts: unstagedStats.counts)
    }

    private func untrackedLineCount(_ path: String, root: URL) throws -> Int? {
        let url = try Self.containedURL(Self.relativeURL(for: path, relativeTo: root), under: root)
        guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return nil }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        // ponytail: 行数は1MBまで。超過時は省略し、大容量の行数が必要になったら遅延取得する。
        let limit = 1024 * 1024
        let bytes = try file.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit else { return nil }
        return bytes.reduce(0) { $0 + ($1 == 10 ? 1 : 0) } + (bytes.last.map { $0 == 10 ? 0 : 1 } ?? 0)
    }

    static func parseLineCounts(_ data: Data) -> [String: WorkingTreeLineCount] {
        let records = data.split(separator: 0, omittingEmptySubsequences: false)
        var counts: [String: WorkingTreeLineCount] = [:]
        var index = 0
        while index < records.count {
            let fields = records[index].split(separator: 9, maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3 else { index += 1; continue }
            let added = Int(String(decoding: fields[0], as: UTF8.self))
            let deleted = Int(String(decoding: fields[1], as: UTF8.self))
            var path = String(decoding: fields[2], as: UTF8.self)
            if path.isEmpty {
                guard index + 2 < records.count else { break }
                path = String(decoding: records[index + 2], as: UTF8.self)
                index += 2
            }
            if let added, let deleted { counts[path] = .init(added: added, deleted: deleted) }
            index += 1
        }
        return counts
    }

    public func detail(for path: String) throws -> WorkingTreeDetail {
        let repositoryURL = try requireRepository()
        let fileURL = try Self.relativeURL(for: path, relativeTo: repositoryURL)

        if try isTracked(path, workingTreeFileURL: fileURL, in: repositoryURL) {
            let repositoryHasHEAD = hasHEAD(in: repositoryURL)
            if repositoryHasHEAD {
                if isBinaryFile(at: fileURL) {
                    return .binary
                }
                if try binaryPathsChangedFromHEAD(
                   in: repositoryURL,
                   repositoryHasHEAD: repositoryHasHEAD,
                   limitedTo: path
                ).contains(path) {
                    return .binary
                }
            } else if isBinaryFile(at: fileURL) {
                return .binary
            }

            var arguments: [String]
            if repositoryHasHEAD {
                arguments = ["diff", "--no-ext-diff", "HEAD", "--", path]
            } else {
                arguments = ["diff", "--no-ext-diff", "--cached", "--", path]
            }
            if let original = try statusEntries(in: repositoryURL).first(where: { $0.path == path })?.originalPath {
                arguments.append(original)
            }
            let diff = try runGit(arguments, in: repositoryURL)
            try requireSuccessful(diff, arguments: arguments)
            return .diff(String(decoding: diff.output, as: UTF8.self))
        }

        let readableFileURL = try accessibleFileURL(for: path)
        if isBinaryFile(at: readableFileURL) {
            return .binary
        }
        return .untrackedContent(try fileContents(path))
    }

    public func detail(for path: String, source: WorkingTreeSource) throws -> WorkingTreeDetail {
        if source.isHistory { return try historyDetail(path: path, source: source) }
        let root = try requireRepository()
        _ = try Self.relativeURL(for: path, relativeTo: root)
        let entry = try statusEntries(in: root).first {
            $0.path == path && (source == .staged ? $0.indexStatus != 32 && $0.indexStatus != 63 : $0.worktreeStatus != 32)
        }
        if source == .worktree, entry?.worktreeStatus == 63 {
            let url = try accessibleFileURL(for: path)
            return isBinaryFile(at: url) ? .binary : .untrackedContent(try fileContents(path))
        }
        var arguments = ["diff", "--no-ext-diff"]
        if source == .staged { arguments.append("--cached") }
        var paths = [path]
        if let entry, (source == .staged ? entry.indexStatus : entry.worktreeStatus) == 82,
           let original = entry.originalPath { paths.append(original) }
        let literalPaths = GitWorkflowService.literalPathspecs(paths)
        let statsArguments = arguments + ["--numstat", "-z", "--"] + literalPaths
        let stats = try runGit(statsArguments, in: root)
        try requireSuccessful(stats, arguments: statsArguments)
        if Self.parseBinaryPaths(stats.output).contains(path) { return .binary }
        arguments += ["--"] + literalPaths
        let result = try runGit(arguments, in: root)
        try requireSuccessful(result, arguments: arguments)
        return .diff(String(decoding: result.output, as: UTF8.self))
    }

    /// 保存・読み込みと同じ基準（Git のルート）で解決した絶対パス。
    public func absolutePath(_ path: String) -> String? {
        try? accessibleFileURL(for: path).path
    }

    public func fileContents(_ path: String) throws -> String {
        let data = try Data(contentsOf: accessibleFileURL(for: path))
        return try WorkingTreeText.decodeUTF8(data)
    }

    public func fileContents(_ path: String, source: WorkingTreeSource) throws -> String {
        if source == .worktree { return try fileContents(path) }
        let root = try requireRepository()
        _ = try Self.relativeURL(for: path, relativeTo: root)
        let revision = try source.revision.map { try verifiedHistoryRevision($0) } ?? ""
        let tree = try historyTree(path: path, source: source, revision: revision)
        let arguments = ["show", tree + ":" + path]
        let result = try runGit(arguments, in: root)
        try requireSuccessful(result, arguments: arguments)
        return try WorkingTreeText.decode(result.output).text
    }

    func history(skip: Int = 0, limit: Int = 50, all: Bool = false) throws -> [GitHistoryCommit] {
        let root = try requireRepository()
        if !all && !hasHEAD(in: root) { return [] }
        let arguments = ["log", "--topo-order", "--decorate=full", "-z", "--format=%H%x00%P%x00%s%x00%an%x00%ct%x00%D",
                         "--max-count=\(limit)", "--skip=\(skip)"] + (all ? ["--exclude=refs/stash", "--all"] : ["HEAD"]) + ["--"]
        let result = try runGit(arguments)
        try requireSuccessful(result, arguments: arguments)
        let fields = String(decoding: result.output, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false)
        var commits: [GitHistoryCommit] = []
        for i in stride(from: 0, to: max(0, fields.count - 5), by: 6) {
            let parents = fields[i+1].split(separator: " ").map(String.init)
            let date = Date(timeIntervalSince1970: Double(fields[i+4]) ?? 0)
            let refs = fields[i+5].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            commits.append(GitHistoryCommit(id: String(fields[i]), parents: parents, summary: String(fields[i+2]),
                                            author: String(fields[i+3]), date: date, refs: refs))
        }
        return commits
    }

    func branches(remote: Bool = false) throws -> [GitBranch] {
        _ = try requireRepository()
        let current = branchLabel()
        var names = try referenceNames(prefix: remote ? "refs/remotes/" : "refs/heads/")
        if !remote, !names.isEmpty {
            let renameArguments = ["reflog", "show", "--all", "--format=%gD%x09%gs", "--"]
            let renames = try runGit(renameArguments)
            try requireSuccessful(renames, arguments: renameArguments)
            var renamedBranches: [String: String] = [:]
            for line in String(decoding: renames.output, as: UTF8.self).split(whereSeparator: \.isNewline) {
                let fields = line.split(separator: "\t", maxSplits: 1)
                guard fields.count == 2, fields[0].hasPrefix("refs/heads/"),
                      let selector = fields[0].range(of: "@{", options: .backwards),
                      fields[1].hasPrefix("Branch: renamed refs/heads/"),
                      let separator = fields[1].range(of: " to refs/heads/") else { continue }
                let name = String(fields[0][..<selector.lowerBound].dropFirst("refs/heads/".count))
                let old = String(fields[1][..<separator.lowerBound].dropFirst("Branch: renamed refs/heads/".count))
                if names.contains(name), renamedBranches[old] == nil { renamedBranches[old] = name }
            }
            let arguments = ["reflog", "show", "--format=%gs", "HEAD", "--"]
            let result = try runGit(arguments)
            try requireSuccessful(result, arguments: arguments)
            var recent: [String] = names.contains(current) ? [current] : []
            for line in String(decoding: result.output, as: UTF8.self).split(whereSeparator: \.isNewline)
                where line.hasPrefix("checkout: moving from ") {
                guard let range = line.range(of: " to ", options: .backwards) else { continue }
                let previousName = String(line[range.upperBound...])
                let name = names.contains(previousName) ? previousName : renamedBranches[previousName] ?? previousName
                if names.contains(name), !recent.contains(name) { recent.append(name) }
            }
            names = recent + names.filter { !recent.contains($0) }
        }
        if !remote, names.isEmpty, !current.isEmpty, !current.contains("detached HEAD") { names = [current] }
        var upstreams: Set<String> = []
        if remote {
            let arguments = ["for-each-ref", "--format=%(upstream:short)", "refs/heads/"]
            let result = try runGit(arguments)
            try requireSuccessful(result, arguments: arguments)
            upstreams = Set(String(decoding: result.output, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init))
        }
        return names.map { .init(name: $0, current: !remote && $0 == current, tracked: upstreams.contains($0)) }
    }

    func lastFetchDate() throws -> Date? {
        let root = try requireRepository()
        let arguments = ["rev-parse", "--git-path", "FETCH_HEAD"]
        let result = try runGit(arguments)
        try requireSuccessful(result, arguments: arguments)
        let path = String(decoding: result.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: path, relativeTo: root)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func isBranchMerged(_ name: String) throws -> Bool {
        let arguments = ["for-each-ref", "--merged=HEAD", "--format=%(refname)", "refs/heads/"]
        let result = try runGit(arguments)
        try requireSuccessful(result, arguments: arguments)
        return String(decoding: result.output, as: UTF8.self).split(whereSeparator: \.isNewline).contains(Substring("refs/heads/" + name))
    }

    func stashes() throws -> [GitStash] {
        _ = try requireRepository()
        let arguments = ["stash", "list", "-z", "--format=%H%x00%gd%x00%gs%x00%ct"]
        let result = try runGit(arguments)
        try requireSuccessful(result, arguments: arguments)
        let fields = String(decoding: result.output, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false)
        return stride(from: 0, to: max(0, fields.count - 3), by: 4).map { i in
            .init(id: String(fields[i]), name: String(fields[i+1]), message: String(fields[i+2]),
                  date: Date(timeIntervalSince1970: Double(fields[i+3]) ?? 0))
        }
    }

    private func verifiedHistoryRevision(_ revision: String) throws -> String {
        guard WorktreeStartPoint.isCommitID(revision) else { throw WorkingTreeServiceError.invalidRelativePath(revision) }
        return try resolveWorktreeStartPoint(.commit(revision))
    }

    func historyFiles(source: WorkingTreeSource) throws -> [WorkingTreeChange] {
        guard let revision = source.revision else { return [] }
        let id = try verifiedHistoryRevision(revision)
        var arguments = ["diff-tree", "--root", "--no-commit-id", "-r", "-M", "--name-status", "-z"]
        let parent = try runGit(["rev-parse", "--verify", id + "^1"])
        if parent.terminationStatus == 0 { arguments.append(id + "^1") }
        arguments += [id, "--"]
        var changes = try historyFileRecords(arguments)
        if case .stash = source {
            let untracked = try runGit(["rev-parse", "--verify", id + "^3"])
            if untracked.terminationStatus == 0 {
                changes += try historyFileRecords(["diff-tree", "--root", "--no-commit-id", "-r", "--name-status", "-z", id + "^3", "--"])
            }
        }
        return changes.sorted { $0.path < $1.path }
    }

    private func historyFileRecords(_ arguments: [String]) throws -> [WorkingTreeChange] {
        let result = try runGit(arguments)
        try requireSuccessful(result, arguments: arguments)
        let fields = String(decoding: result.output, as: UTF8.self).split(separator: "\0", omittingEmptySubsequences: false)
        var rows: [WorkingTreeChange] = []
        var i = 0
        while i + 1 < fields.count {
            let status = fields[i].first
            let renamed = status == "R" || status == "C"
            let pathIndex = i + (renamed ? 2 : 1)
            guard pathIndex < fields.count, !fields[pathIndex].isEmpty else { break }
            let kind: WorkingTreeChange.Kind = switch status {
            case "A": .added
            case "D": .deleted
            case "R": .renamed
            default: .modified
            }
            rows.append(.init(path: String(fields[pathIndex]), kind: kind, isBinary: false,
                              originalPath: renamed ? String(fields[i+1]) : nil))
            i = pathIndex + 1
        }
        return rows
    }

    private func historyTree(path: String, source: WorkingTreeSource, revision: String) throws -> String {
        guard case .stash = source else { return revision }
        let untracked = try runGit(["cat-file", "-e", revision + "^3:" + path])
        return untracked.terminationStatus == 0 ? revision + "^3" : revision
    }

    private func historyDetail(path: String, source: WorkingTreeSource) throws -> WorkingTreeDetail {
        let root = try requireRepository()
        _ = try Self.relativeURL(for: path, relativeTo: root)
        guard let revision = source.revision else { return .diff("") }
        let id = try verifiedHistoryRevision(revision)
        let tree = try historyTree(path: path, source: source, revision: id)
        let original = try historyFiles(source: source).first { $0.path == path }?.originalPath
        let literal = GitWorkflowService.literalPathspecs([path] + (original.map { [$0] } ?? []))
        let arguments: [String]
        if tree != id {
            arguments = ["show", "--format=", "--no-ext-diff", "--no-textconv", tree, "--"] + literal
        } else {
            let parent = try runGit(["rev-parse", "--verify", id + "^1"])
            arguments = parent.terminationStatus == 0
                ? ["diff", "--no-ext-diff", "--no-textconv", id + "^1", id, "--"] + literal
                : ["show", "--format=", "--no-ext-diff", "--no-textconv", id, "--"] + literal
        }
        let statArguments = [arguments[0], "--numstat"] + Array(arguments.dropFirst())
        let stat = try runGit(statArguments)
        try requireSuccessful(stat, arguments: statArguments)
        if String(decoding: stat.output, as: UTF8.self).split(whereSeparator: \.isNewline).contains(where: { $0.hasPrefix("-\t-\t") }) {
            return .binary
        }
        let result = try runGit(arguments)
        try requireSuccessful(result, arguments: arguments)
        return .diff(String(decoding: result.output, as: UTF8.self))
    }

    public func fileData(_ path: String) throws -> Data {
        let url = try accessibleFileURL(for: path)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= WorkingTreeText.maximumReadableFileSize else { throw WorkingTreeTextError.tooLarge }
        return try Data(contentsOf: url)
    }

    public func fileSize(_ path: String) throws -> Int {
        try accessibleFileURL(for: path).resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    }

    /// HTML の画像・フォント等は配信上限と包含確認を通して読む。
    public func resourceData(_ path: String) throws -> Data {
        try resourceData(path, read: { try Data(contentsOf: $0) })
    }

    func resourceData(_ path: String, read: @Sendable (URL) throws -> Data) throws -> Data {
        let url = try accessibleFileURL(for: path)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size, size <= Self.maximumHTMLResourceSize else { throw URLError(.dataLengthExceedsMaximum) }
        return try read(url)
    }

    public func save(
        path: String,
        content: String,
        expectedDiskContent: String?
    ) throws -> WorkingTreeSaveOutcome {
        try save(path: path, data: Data(content.utf8), expectedDiskBytes: expectedDiskContent.map { Data($0.utf8) })
    }

    public func save(path: String, data: Data, expectedDiskBytes: Data?) throws -> WorkingTreeSaveOutcome {
        let destination: URL
        do {
            destination = try accessibleFileURL(for: path, allowMissing: true)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile && expectedDiskBytes != nil {
            return .conflict
        }
        if let expectedDiskBytes {
            let currentDiskBytes: Data
            do {
                currentDiskBytes = try Data(contentsOf: destination)
            } catch {
                return .conflict
            }
            guard currentDiskBytes == expectedDiskBytes else {
                return .conflict
            }
        }

        try data.write(to: destination, options: .atomic)
        return .saved
    }

    private func requireRepository() throws -> URL {
        let arguments = ["rev-parse", "--show-toplevel"]
        let result = try runGit(arguments)
        guard result.terminationStatus == 0 else {
            let output = String(decoding: result.errorOutput, as: UTF8.self)
            if output.contains("not a git repository") { throw WorkingTreeServiceError.notRepository }
            throw WorkingTreeServiceError.gitCommandFailed(arguments: arguments, output: output)
        }

        let path = String(decoding: result.output, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw WorkingTreeServiceError.notRepository
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func hasHEAD(in repositoryURL: URL) -> Bool {
        (try? runGit(["rev-parse", "--verify", "HEAD"], in: repositoryURL))?.terminationStatus == 0
    }

    private func statusEntries(in repositoryURL: URL) throws -> [StatusEntry] {
        let arguments = ["status", "--porcelain=v1", "-z", "--untracked-files=all"]
        let result = try runGit(arguments, in: repositoryURL)
        try requireSuccessful(result, arguments: arguments)

        let records = result.output.split(separator: 0, omittingEmptySubsequences: false)
        var entries: [StatusEntry] = []
        var index = 0

        while index < records.count {
            let record = records[index]
            guard record.count >= 3 else {
                index += 1
                continue
            }

            let status = record.prefix(2)
            let path = String(decoding: record.dropFirst(3), as: UTF8.self)
            let isRenameOrCopy = status.contains(82) || status.contains(67) // R / C
            let original = isRenameOrCopy && index + 1 < records.count ? String(decoding: records[index + 1], as: UTF8.self) : nil
            let entry = StatusEntry(path: path, kind: changeKind(for: status), originalPath: original,
                                    indexStatus: status.first ?? 32, worktreeStatus: status.last ?? 32)
            if !path.hasSuffix("/") {
                entries.append(entry)
            }
            index += isRenameOrCopy ? 2 : 1
        }

        return entries
    }

    private func changeKind(for status: Data.SubSequence) -> WorkingTreeChange.Kind {
        if status.elementsEqual([63, 63]) { // ??
            return .untracked
        }
        if status.contains(82) || status.contains(67) { // R / C
            return .renamed
        }
        if status.contains(68) { // D
            return .deleted
        }
        if status.contains(65) { // A
            return .added
        }
        return .modified
    }

    private func binaryPathsChangedFromHEAD(
        in repositoryURL: URL,
        repositoryHasHEAD: Bool,
        limitedTo path: String? = nil
    ) throws -> Set<String> {
        guard repositoryHasHEAD else {
            return []
        }

        var arguments = ["diff", "--no-ext-diff", "--numstat", "-z", "HEAD"]
        if let path {
            arguments += ["--", path]
        }
        let result = try runGit(arguments, in: repositoryURL)
        try requireSuccessful(result, arguments: arguments)

        return Self.parseBinaryPaths(result.output)
    }

    private static func parseBinaryPaths(_ data: Data) -> Set<String> {
        var binaryPaths: Set<String> = []
        let records = data.split(separator: 0, omittingEmptySubsequences: false)
        var index = 0
        while index < records.count {
            let record = records[index]
            guard !record.isEmpty else {
                index += 1
                continue
            }
            guard let firstTab = record.firstIndex(of: 9),
                  let secondTab = record[record.index(after: firstTab)...].firstIndex(of: 9) else {
                index += 1
                continue
            }

            let added = record[..<firstTab]
            let deleted = record[record.index(after: firstTab)..<secondTab]
            let pathBytes = record[record.index(after: secondTab)...]
            let isBinary = added.elementsEqual([45]) || deleted.elementsEqual([45])

            if pathBytes.isEmpty {
                // --numstat -z のリネームは空パスのあとに旧・新パスが続く。
                guard index + 2 < records.count else { break }
                if isBinary {
                    binaryPaths.insert(String(decoding: records[index + 1], as: UTF8.self))
                    binaryPaths.insert(String(decoding: records[index + 2], as: UTF8.self))
                }
                index += 3
            } else {
                if isBinary {
                    binaryPaths.insert(String(decoding: pathBytes, as: UTF8.self))
                }
                index += 1
            }
        }
        return binaryPaths
    }

    private func isTracked(
        _ path: String,
        workingTreeFileURL: URL,
        in repositoryURL: URL
    ) throws -> Bool {
        let arguments = ["ls-files", "--error-unmatch", "--", path]
        let result = try runGit(arguments, in: repositoryURL)
        if result.terminationStatus == 0 {
            return true
        }
        guard !FileManager.default.fileExists(atPath: workingTreeFileURL.path),
              hasHEAD(in: repositoryURL) else {
            return false
        }
        return try runGit(["cat-file", "-e", "HEAD:\(path)"], in: repositoryURL).terminationStatus == 0
    }

    private func isBinaryFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        let data = try? handle.read(upToCount: 8_192)
        return data?.contains(0) == true
    }

    private func accessibleFileURL(for path: String, allowMissing: Bool = false) throws -> URL {
        let root = try fileRoot().resolvingSymlinksInPath().standardizedFileURL
        guard !fixedRoot || root.path.utf8.elementsEqual(repositoryRoot.path.utf8) else {
            throw WorkingTreeServiceError.outsideRoot(root.path)
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WorkingTreeServiceError.missingRoot(root.path)
        }
        let requested = try Self.relativeURL(for: path, relativeTo: root)
        let url = try Self.containedURL(requested, under: root)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [.isRegularFileKey])
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile && allowMissing {
            // 包含確認済みの親が存在する場合だけ、削除されたファイルを作り直す。
            let parent = try url.deletingLastPathComponent().resourceValues(forKeys: [.isDirectoryKey])
            guard parent.isDirectory == true else { throw error }
            return url
        }
        guard values.isRegularFile == true else {
            throw WorkingTreeServiceError.notRegularFile(url.path)
        }
        return url
    }

    nonisolated static func containedURL(_ requested: URL, under root: URL, allowRoot: Bool = false) throws -> URL {
        // 末尾が削除済みでも、親のリンクを先に解決して保存先を検査する。
        let url = requested.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(requested.lastPathComponent).resolvingSymlinksInPath().standardizedFileURL
        let rootComponents = root.pathComponents
        guard (allowRoot || url.pathComponents.count > rootComponents.count),
              url.pathComponents.starts(with: rootComponents) else {
            throw WorkingTreeServiceError.outsideRoot(url.path)
        }
        return url
    }

    private func fileRoot() throws -> URL {
        if fixedRoot { return repositoryRoot }
        let result = try runGit(["rev-parse", "--show-toplevel"])
        let baseURL: URL
        if result.terminationStatus == 0 {
            let path = String(decoding: result.output, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            baseURL = path.isEmpty ? repositoryRoot : URL(fileURLWithPath: path, isDirectory: true)
        } else {
            baseURL = repositoryRoot
        }
        return baseURL
    }

    nonisolated static func relativeURL(for path: String, relativeTo repositoryURL: URL, allowRoot: Bool = false) throws -> URL {
        if path.isEmpty, allowRoot { return repositoryURL }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !path.utf8.contains(0), !components.isEmpty,
              components.allSatisfy({ $0 != "." && $0 != ".." && !$0.isEmpty }) else {
            throw WorkingTreeServiceError.invalidRelativePath(path)
        }
        return repositoryURL.appendingPathComponent(path, isDirectory: false)
    }

    private func runGit(_ arguments: [String], in directory: URL? = nil) throws -> GitCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks"] + arguments
        process.currentDirectoryURL = directory ?? repositoryRoot

        let output = Pipe()
        let errorOutput = Pipe()
        process.standardOutput = output
        process.standardError = errorOutput
        try process.run()
        try output.fileHandleForWriting.close()
        try errorOutput.fileHandleForWriting.close()

        let outputCapture = GitDataCapture()
        let errorCapture = GitDataCapture()
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
        return GitCommandResult(
            terminationStatus: process.terminationStatus,
            output: outputCapture.value(),
            errorOutput: errorCapture.value()
        )
    }

    private func requireSuccessful(_ result: GitCommandResult, arguments: [String]) throws {
        guard result.terminationStatus == 0 else {
            throw WorkingTreeServiceError.gitCommandFailed(
                arguments: arguments,
                output: String(decoding: result.errorOutput.isEmpty ? result.output : result.errorOutput, as: UTF8.self)
            )
        }
    }
}
