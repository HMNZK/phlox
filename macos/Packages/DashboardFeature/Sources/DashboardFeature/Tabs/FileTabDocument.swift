import Foundation
import Observation
import AgentDomain
import SessionFeature

/// ファイルの子タブの中身（02 の移動表「編集 → ファイルタブ」）。読み込んだ時点の内容を覚えておき、
/// 保存時にディスクが変わっていれば競合として返す（旧エディタパネルと同じ規則）。
@MainActor
@Observable
public final class FileTabDocument {
    public enum SaveResult: Equatable, Sendable {
        case saved
        case conflictDetected
    }

    public enum LoadState: Equatable, Sendable {
        case unloaded, loading, loaded, tooLarge, binary, loadFailed
        case outsideRoot(String)
    }

    public enum DocumentError: Error, Equatable { case invalidated }

    /// worktree 直下からの相対パス。
    public let path: String
    private var draftContent = ""
    public var draft: String {
        get { draftContent }
        set { if !invalidationRequested { draftContent = newValue } }
    }
    public private(set) var loadState: LoadState = .unloaded
    public private(set) var loadedDiskBytes = Data()
    public private(set) var bom = Data()
    public private(set) var invalidated = false
    private var invalidationRequested = false
    public var loadFailed: Bool {
        switch loadState {
        case .tooLarge, .binary, .outsideRoot, .loadFailed: true
        default: false
        }
    }
    /// ディスクの内容を最後に読んだ／書いた時刻。これより後の他セッションの書き換えを競合相手とみなす。
    public private(set) var baselineAt: Date?
    /// 読み込んだファイルの絶対パス（保存と同じく Git のルート基準）。
    private var absolutePath: String?

    /// 開いたときの作業ディレクトリ。セッションの作業場所が変わったら作り直す。
    public let workingDirectory: String
    public private(set) var root: String
    @ObservationIgnored private var service: WorkingTreeService
    @ObservationIgnored private var needsRootResolution: Bool
    @ObservationIgnored private var pendingSave: Task<SaveResult, Error>?
    @ObservationIgnored private var pendingSaveCount = 0

    public init(path: String, workingDirectory: String) {
        self.path = path
        self.workingDirectory = workingDirectory
        self.root = workingDirectory
        self.needsRootResolution = true
        self.service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: workingDirectory, isDirectory: true))
    }

    public init(path: String, root: String) {
        self.path = path
        let resolvedRoot = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
        self.workingDirectory = resolvedRoot
        self.root = resolvedRoot
        self.needsRootResolution = false
        self.service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: resolvedRoot, isDirectory: true), fixedRoot: true)
    }

    public var isLoaded: Bool { loadState == .loaded }
    public var isDirty: Bool { isLoaded && savingBytes != loadedDiskBytes }
    public var hasUnsavedChanges: Bool { isDirty }
    private var savingBytes: Data { bom + Data(draft.utf8) }
    var hasPendingSaves: Bool { pendingSaveCount > 0 }
    public var fileName: String { (path as NSString).lastPathComponent }

    /// 開いてからこのファイルを書き換えた別セッションの表示名（07「アザミ · Codex」）。
    /// 分かるのはチャット型のファイル変更だけ。その後にターミナルやエディタが書き換えていれば分からないので nil。
    public func lastWriter(among sessions: [SessionNode], excluding sessionID: SessionID) -> String? {
        guard let baselineAt, let absolutePath else { return nil }
        let target = Self.canonical(absolutePath, relativeTo: "/")
        var latest: (date: Date, name: String)?
        for node in sessions where node.id != sessionID {
            guard case .appServer(let chat) = node else { continue }
            for case .fileChange(_, let changes, let timestamp) in chat.transcript
            where timestamp > baselineAt && timestamp > (latest?.date ?? .distantPast)
                && changes.contains(where: { Self.canonical($0.path, relativeTo: node.rawWorkspacePath) == target }) {
                latest = (timestamp, "\(node.displayName) · \(node.agentDescriptor.displayName)")
            }
        }
        // ponytail: 変更の記録時刻とディスクの更新時刻を 5 秒の幅で突き合わせる。書き手の記録が要るなら保存経路で記録する。
        guard let latest,
              let modified = (try? FileManager.default.attributesOfItem(atPath: absolutePath))?[.modificationDate] as? Date,
              modified <= latest.date.addingTimeInterval(Self.writeTolerance)
        else { return nil }
        return latest.name
    }

    static let writeTolerance: TimeInterval = 5

    private static func canonical(_ path: String, relativeTo base: String) -> String {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : URL(fileURLWithPath: base, isDirectory: true).appendingPathComponent(path)
        return url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// 未読込のときだけ読む（タブの切り替えで下書きを失わない）。
    public func loadIfNeeded() async {
        guard loadState == .unloaded, !invalidated else { return }
        loadState = .loading
        do {
            if needsRootResolution {
                root = await service.resolvedRepositoryRootPath() ?? workingDirectory
                service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: root, isDirectory: true), fixedRoot: true)
                needsRootResolution = false
            }
            absolutePath = await service.absolutePath(path)
            // 読み始める前の時刻を基準にする（読んでいる間の他セッションの書き換えも相手とみなす）。
            let startedAt = Date()
            let bytes = try await service.fileData(path)
            let decoded = try WorkingTreeText.decode(bytes)
            guard !invalidated else { return }
            loadedDiskBytes = bytes
            bom = decoded.bom
            baselineAt = startedAt
            draft = decoded.text
            loadState = .loaded
        } catch WorkingTreeTextError.tooLarge {
            loadState = .tooLarge
        } catch WorkingTreeTextError.binary {
            loadState = .binary
        } catch WorkingTreeServiceError.outsideRoot(let path) {
            loadState = .outsideRoot(path)
        } catch {
            loadState = .loadFailed
        }
    }

    public func save() async throws -> SaveResult {
        try await enqueueSave(overwrite: false).value
    }

    public func overwrite() async throws {
        _ = try await enqueueSave(overwrite: true).value
    }

    func enqueueSave(overwrite: Bool) throws -> Task<SaveResult, Error> {
        guard !invalidationRequested else { throw DocumentError.invalidated }
        guard isLoaded else { return Task { .conflictDetected } }
        let saving = savingBytes
        let previous = pendingSave
        pendingSaveCount += 1
        let task = Task { @MainActor in
            defer {
                self.pendingSaveCount -= 1
                if self.pendingSaveCount == 0 {
                    self.pendingSave = nil
                    if self.invalidationRequested { self.invalidated = true }
                }
            }
            if let previous { _ = await previous.result }
            let expected = overwrite ? nil : self.loadedDiskBytes
            switch try await self.service.save(path: self.path, data: saving, expectedDiskBytes: expected) {
            case .saved:
                self.loadedDiskBytes = saving
                self.baselineAt = Date()
                return SaveResult.saved
            case .conflict:
                return SaveResult.conflictDetected
            }
        }
        pendingSave = task
        return task
    }

    public func invalidate() {
        invalidationRequested = true
        if pendingSaveCount == 0 { invalidated = true }
    }

    public func waitForPendingSaves() async {
        if let pendingSave { _ = await pendingSave.result }
    }
}

/// セッション × パスごとのファイルタブ。表示の途中で作ってよいよう観測対象にはしない。
@MainActor
public final class FileTabDocuments {
    private var storedDocuments: [SessionID: [String: FileTabDocument]] = [:]

    public init() {}

    /// セッションの作業場所が変わっていたら、旧い場所の下書きは捨てて開き直す
    /// （作業場所の変更は「進行中の作業は失われます」と確認してから行われる）。
    public func document(for sessionID: SessionID, path: String, workingDirectory: String) -> FileTabDocument {
        if let existing = storedDocuments[sessionID]?[path],
           existing.workingDirectory == workingDirectory || existing.isDirty || existing.hasPendingSaves { return existing }
        storedDocuments[sessionID]?[path]?.invalidate()
        let created = FileTabDocument(path: path, workingDirectory: workingDirectory)
        storedDocuments[sessionID, default: [:]][path] = created
        return created
    }

    public func document(for sessionID: SessionID, path: String, root: String) -> FileTabDocument {
        let root = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
        if let existing = storedDocuments[sessionID]?[path],
           existing.root == root || existing.isDirty || existing.hasPendingSaves { return existing }
        storedDocuments[sessionID]?[path]?.invalidate()
        let created = FileTabDocument(path: path, root: root)
        storedDocuments[sessionID, default: [:]][path] = created
        return created
    }

    public func existing(for sessionID: SessionID, path: String) -> FileTabDocument? {
        storedDocuments[sessionID]?[path]
    }

    public func remove(for sessionID: SessionID, path: String) async {
        guard let document = storedDocuments[sessionID]?[path] else { return }
        document.invalidate()
        await document.waitForPendingSaves()
        if storedDocuments[sessionID]?[path] === document { storedDocuments[sessionID]?[path] = nil }
    }

    public func removeAll(for sessionID: SessionID) async {
        await invalidateAndWait(for: [sessionID])
    }

    public func documents(for sessionIDs: Set<SessionID>? = nil) -> [FileTabDocument] {
        storedDocuments.filter { sessionIDs?.contains($0.key) ?? true }.values.flatMap { $0.values }
    }

    public func invalidateAndWait(for sessionIDs: Set<SessionID>? = nil) async {
        let affected = documents(for: sessionIDs)
        for document in affected { document.invalidate() }
        for document in affected { await document.waitForPendingSaves() }
        for (sessionID, entries) in storedDocuments {
            for (path, document) in entries where affected.contains(where: { $0 === document }) {
                storedDocuments[sessionID]?[path] = nil
            }
        }
    }

    /// 未保存のファイル名（セッション削除の確認に出す）。
    public func dirtyFileNames(for sessionID: SessionID) -> [String] {
        (storedDocuments[sessionID] ?? [:]).values.filter(\.isDirty).map(\.fileName).sorted()
    }
}
