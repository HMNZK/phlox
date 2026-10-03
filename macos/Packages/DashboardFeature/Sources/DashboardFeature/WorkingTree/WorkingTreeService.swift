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
    public static let maximumEditableFileSize = 1_000_000

    public static func decode(_ data: Data) throws -> (text: String, bom: Data) {
        guard data.count <= maximumEditableFileSize else { throw WorkingTreeTextError.tooLarge }
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
        return "detached HEAD " + String(decoding: head.output, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func changes() throws -> [WorkingTreeChange] {
        let repositoryURL = try requireRepository()

        let entries = try statusEntries(in: repositoryURL)
        let repositoryHasHEAD = hasHEAD(in: repositoryURL)
        let binaryDiffPaths = try binaryPathsChangedFromHEAD(
            in: repositoryURL,
            repositoryHasHEAD: repositoryHasHEAD
        )

        return try entries.map { entry in
            let needsFileInspection = !repositoryHasHEAD
                || entry.kind == .untracked
                || entry.kind == .renamed
            var isBinary = binaryDiffPaths.contains(entry.path)
            if !isBinary, needsFileInspection {
                isBinary = isBinaryFile(at: try Self.relativeURL(for: entry.path, relativeTo: repositoryURL))
            }
            return WorkingTreeChange(path: entry.path, kind: entry.kind, isBinary: isBinary)
        }
        .sorted { $0.path < $1.path }
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

            let arguments: [String]
            if repositoryHasHEAD {
                arguments = ["diff", "--no-ext-diff", "HEAD", "--", path]
            } else {
                arguments = ["diff", "--no-ext-diff", "--cached", "--", path]
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

    /// 保存・読み込みと同じ基準（Git のルート）で解決した絶対パス。
    public func absolutePath(_ path: String) -> String? {
        try? accessibleFileURL(for: path).path
    }

    public func fileContents(_ path: String) throws -> String {
        let data = try Data(contentsOf: accessibleFileURL(for: path))
        return try WorkingTreeText.decodeUTF8(data)
    }

    public func fileData(_ path: String) throws -> Data {
        let url = try accessibleFileURL(for: path)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= WorkingTreeText.maximumEditableFileSize else { throw WorkingTreeTextError.tooLarge }
        return try Data(contentsOf: url)
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
            throw WorkingTreeServiceError.notRepository
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
        var entriesByPath: [String: StatusEntry] = [:]
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
            let entry = StatusEntry(path: path, kind: changeKind(for: status))
            if !path.hasSuffix("/") {
                if let existing = entriesByPath[path] {
                    entriesByPath[path] = preferredEntry(between: existing, and: entry)
                } else {
                    entriesByPath[path] = entry
                }
            }
            index += isRenameOrCopy ? 2 : 1
        }

        return Array(entriesByPath.values)
    }

    private func preferredEntry(between first: StatusEntry, and second: StatusEntry) -> StatusEntry {
        func priority(of kind: WorkingTreeChange.Kind) -> Int {
            switch kind {
            case .modified: 1
            case .added: 2
            case .deleted: 3
            case .renamed: 4
            case .untracked: 5
            }
        }
        return priority(of: second.kind) >= priority(of: first.kind) ? second : first
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

        var binaryPaths: Set<String> = []
        let records = result.output.split(separator: 0, omittingEmptySubsequences: false)
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
