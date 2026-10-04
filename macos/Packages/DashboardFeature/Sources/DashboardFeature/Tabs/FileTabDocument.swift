import Foundation
import AppKit
import Observation
import AgentDomain
import SessionFeature

public struct ActiveBlockEdit: Equatable, Sendable {
    public let id: UUID
    public let baseVersion: Int
    public let range: Range<Int>
    public let original: String
    public var current: String
}

/// 入力欄の履歴と確定済み文書の履歴を混ぜない。
private final class FileBlockUndoManager: UndoManager, @unchecked Sendable {
    var mayRestoreDocument: @MainActor (String) -> Bool = { _ in false }
    private var undoExpected: [String] = []
    private var redoExpected: [String] = []

    override var canUndo: Bool {
        MainActor.assumeIsolated { super.canUndo && undoExpected.last.map(mayRestoreDocument) == true }
    }

    override var canRedo: Bool {
        MainActor.assumeIsolated { super.canRedo && redoExpected.last.map(mayRestoreDocument) == true }
    }

    func expectDocument(_ text: String) {
        if isUndoing { redoExpected.append(text) }
        else {
            if !isRedoing { redoExpected.removeAll() }
            undoExpected.append(text)
        }
    }

    override func removeAllActions() {
        super.removeAllActions()
        undoExpected.removeAll()
        redoExpected.removeAll()
    }

    override func undo() {
        MainActor.assumeIsolated {
            guard canUndo else { return }
            super.undo()
            undoExpected.removeLast()
        }
    }

    override func redo() {
        MainActor.assumeIsolated {
            guard canRedo else { return }
            super.redo()
            redoExpected.removeLast()
        }
    }
}

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

    public enum DocumentError: Error, Equatable { case invalidated, blockEditVersionMismatch }

    public enum Presentation: Sendable { case rendered, source }
    private var storedPresentation: Presentation = .source
    public var presentation: Presentation {
        get { markdownPresentationLocked ? .source : storedPresentation }
        set { _ = setPresentation(newValue) }
    }
    public private(set) var htmlPreviewRevision = 0
    public var isHTML: Bool { ["html", "htm"].contains((path as NSString).pathExtension.lowercased()) }
    public var isMarkdown: Bool { ["md", "markdown"].contains((path as NSString).pathExtension.lowercased()) }
    public private(set) var version = 0
    public private(set) var activeBlockEdit: ActiveBlockEdit?
    public private(set) var blockEditFailure: String?
    @ObservationIgnored public var synchronizeActiveBlockEditor: (() -> Void)?
    @ObservationIgnored public private(set) lazy var undoManager: UndoManager = {
        let manager = FileBlockUndoManager()
        manager.groupsByEvent = false
        manager.mayRestoreDocument = { [weak self] expected in
            guard let self else { return false }
            return self.activeBlockEdit == nil && !self.invalidationRequested
                && self.draft.utf8.elementsEqual(expected.utf8)
        }
        return manager
    }()
    @ObservationIgnored private var cachedMarkdownBlocks: [MarkdownBlock] = []
    private var cachedMarkdownVersion = -1
    private var cachedMarkdownLocked = false
    public private(set) var markdownAnalysisFailure: String?
    @ObservationIgnored private var markdownAnalysisTask: Task<Void, Never>?
    @ObservationIgnored private var pendingMarkdownAnalysis: (version: Int, task: Task<MarkdownBlocks.Analysis, Never>)?
    private var pendingRenderedPresentation = false

    public var markdownBlocks: [MarkdownBlock] {
        if cachedMarkdownVersion != version {
            acceptMarkdownAnalysis(MarkdownBlocks.analyze(draft), version: version)
        }
        return cachedMarkdownBlocks
    }

    public var markdownPresentationLocked: Bool {
        guard isMarkdown else { return false }
        if draft.utf8.count > 500_000 {
            return true
        }
        // レンダリング中の古い結果は再判定し、固定中の入力では非同期解析を待つ。
        if storedPresentation == .rendered, !cachedMarkdownLocked, cachedMarkdownVersion != version {
            _ = markdownBlocks
        }
        return cachedMarkdownLocked
    }

    private func acceptMarkdownAnalysis(_ analysis: MarkdownBlocks.Analysis, version analyzedVersion: Int) {
        guard version == analyzedVersion, !invalidationRequested else { return }
        cachedMarkdownBlocks = analysis.blocks
        cachedMarkdownVersion = analyzedVersion
        cachedMarkdownLocked = !analysis.isSafe || analysis.blocks.count > 2_000
        markdownAnalysisFailure = analysis.isSafe ? nil : "文書の区間を安全に解析できないためソース表示で編集してください"
    }

    func refreshMarkdownAnalysis() async {
        guard isMarkdown, draft.utf8.count <= 500_000, cachedMarkdownVersion != version,
              !invalidationRequested else { return }
        let analyzedVersion = version
        let task: Task<MarkdownBlocks.Analysis, Never>
        if let pendingMarkdownAnalysis, pendingMarkdownAnalysis.version == analyzedVersion {
            task = pendingMarkdownAnalysis.task
        } else {
            let source = draft
            task = Task.detached(priority: .userInitiated) { MarkdownBlocks.analyze(source) }
            pendingMarkdownAnalysis = (analyzedVersion, task)
        }
        let analysis = await task.value
        acceptMarkdownAnalysis(analysis, version: analyzedVersion)
        if pendingMarkdownAnalysis?.version == analyzedVersion { pendingMarkdownAnalysis = nil }
    }

    private func scheduleMarkdownAnalysis() {
        markdownAnalysisTask?.cancel()
        guard isMarkdown, draft.utf8.count <= 500_000, !invalidationRequested else { return }
        let requestedVersion = version
        let switchToRendered = pendingRenderedPresentation
        markdownAnalysisTask = Task { [weak self] in
            if !switchToRendered {
                do { try await Task.sleep(for: .milliseconds(300)) }
                catch { return }
            }
            guard !Task.isCancelled, let self, self.version == requestedVersion else { return }
            await self.refreshMarkdownAnalysis()
            guard !Task.isCancelled, self.version == requestedVersion else { return }
            if self.pendingRenderedPresentation {
                self.pendingRenderedPresentation = false
                if !self.markdownPresentationLocked { self.storedPresentation = .rendered }
            }
        }
    }

    @discardableResult
    public func setPresentation(_ next: Presentation) -> Bool {
        guard !invalidationRequested else { return false }
        pendingRenderedPresentation = false
        markdownAnalysisTask?.cancel()
        if next == storedPresentation {
            if next == .source { scheduleMarkdownAnalysis() }
            return next != .rendered || !markdownPresentationLocked
        }
        synchronizeActiveBlockEditor?()
        guard commitActiveBlockEdit() else { return false }
        if next == .rendered, isMarkdown, storedPresentation == .source,
           draft.utf8.count <= 500_000, cachedMarkdownVersion != version {
            pendingRenderedPresentation = true
            scheduleMarkdownAnalysis()
            return false
        }
        if next == .rendered, markdownPresentationLocked { return false }
        storedPresentation = next
        if next == .source { scheduleMarkdownAnalysis() }
        if next == .rendered { reloadHTMLPreview() }
        return true
    }

    @discardableResult
    public func beginBlockEdit(range: Range<Int>) -> Bool {
        guard !invalidationRequested, isMarkdown, !markdownPresentationLocked else { return false }
        synchronizeActiveBlockEditor?()
        let previousEdit = activeBlockEdit
        if previousEdit?.range == range, previousEdit?.baseVersion == version { return true }
        guard commitActiveBlockEdit() else { return false }
        guard !markdownPresentationLocked else { return false }
        let selectedRange = previousEdit.map { rangeAfterCommitting($0, for: range) } ?? range
        let bytes = Array(draft.utf8)
        guard selectedRange.lowerBound >= 0, selectedRange.upperBound <= bytes.count else { return false }
        let original = String(decoding: bytes[selectedRange], as: UTF8.self)
        guard original.utf8.count == selectedRange.count,
              original.utf8.elementsEqual(bytes[selectedRange]) else { return false }
        activeBlockEdit = ActiveBlockEdit(id: UUID(), baseVersion: version, range: selectedRange,
                                          original: original, current: original)
        blockEditFailure = nil
        return true
    }

    func rangeAfterCommitting(_ edit: ActiveBlockEdit, for range: Range<Int>) -> Range<Int> {
        guard edit.range.upperBound <= range.lowerBound else { return range }
        let offset = edit.current.utf8.count - edit.range.count
        return (range.lowerBound + offset)..<(range.upperBound + offset)
    }

    public func updateActiveBlockEdit(id: UUID, current: String) {
        guard !invalidationRequested, activeBlockEdit?.id == id else { return }
        activeBlockEdit?.current = current
    }

    public func discardActiveBlockEdit(id: UUID) {
        guard activeBlockEdit?.id == id else { return }
        activeBlockEdit = nil
        synchronizeActiveBlockEditor = nil
        blockEditFailure = nil
    }

    @discardableResult
    func openSourceDiscardingBlockEdit(id: UUID, pasteboard: NSPasteboard = .general) -> Bool {
        guard !invalidationRequested, activeBlockEdit?.id == id else { return false }
        synchronizeActiveBlockEditor?()
        guard let edit = activeBlockEdit, edit.id == id else { return false }
        pasteboard.clearContents()
        guard pasteboard.setString(edit.current, forType: .string) else { return false }
        discardActiveBlockEdit(id: id)
        return setPresentation(.source)
    }

    @discardableResult
    public func commitActiveBlockEdit(id: UUID) -> Bool {
        guard activeBlockEdit?.id == id else { return false }
        return commitActiveBlockEdit()
    }

    @discardableResult
    public func commitActiveBlockEdit() -> Bool {
        guard !invalidationRequested else { return false }
        guard let edit = activeBlockEdit else { return true }
        guard edit.baseVersion == version else {
            blockEditFailure = "文書が先に変わったため確定できません"
            return false
        }
        let before = draft
        var bytes = Array(before.utf8)
        guard edit.range.lowerBound >= 0, edit.range.upperBound <= bytes.count else { return false }
        bytes.replaceSubrange(edit.range, with: edit.current.utf8)
        let after = String(decoding: bytes, as: UTF8.self)
        guard after.utf8.count == bytes.count, after.utf8.elementsEqual(bytes) else { return false }
        activeBlockEdit = nil
        synchronizeActiveBlockEditor = nil
        blockEditFailure = nil
        if !before.utf8.elementsEqual(after.utf8) {
            draft = after
            registerUndo(restoring: before, expected: after)
        }
        return true
    }

    private func registerUndo(restoring text: String, expected: String) {
        (undoManager as? FileBlockUndoManager)?.expectDocument(expected)
        if !undoManager.isUndoing, !undoManager.isRedoing { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                guard !document.invalidationRequested, document.activeBlockEdit == nil,
                      document.draft.utf8.elementsEqual(expected.utf8) else { return }
                let previous = document.draft
                document.draft = text
                document.registerUndo(restoring: previous, expected: text)
            }
        }
        undoManager.setActionName("ブロック編集")
        if !undoManager.isUndoing, !undoManager.isRedoing { undoManager.endUndoGrouping() }
    }

    public func reloadHTMLPreview() {
        guard isHTML, !invalidated else { return }
        htmlPreviewRevision += 1
    }

    /// worktree 直下からの相対パス。
    public let path: String
    private var draftContent = ""
    public var draft: String {
        get { draftContent }
        set {
            if !invalidationRequested,
               draftContent.utf8.count != newValue.utf8.count || !draftContent.utf8.elementsEqual(newValue.utf8) {
                draftContent = newValue
                version += 1
                scheduleMarkdownAnalysis()
            }
        }
    }
    public private(set) var loadState: LoadState = .unloaded
    public private(set) var fileSize: Int?
    public private(set) var readFailureReason: String?
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
        self.storedPresentation = isHTML || isMarkdown ? .rendered : .source
    }

    public init(path: String, root: String) {
        self.path = path
        let resolvedRoot = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
        self.workingDirectory = resolvedRoot
        self.root = resolvedRoot
        self.needsRootResolution = false
        self.service = WorkingTreeService(repositoryRoot: URL(fileURLWithPath: resolvedRoot, isDirectory: true), fixedRoot: true)
        self.storedPresentation = isHTML || isMarkdown ? .rendered : .source
    }

    public var isLoaded: Bool { loadState == .loaded }
    public var isDirty: Bool { isLoaded && savingBytes != loadedDiskBytes }
    public var hasUnsavedChanges: Bool {
        isDirty || activeBlockEdit.map { !$0.original.utf8.elementsEqual($0.current.utf8) } ?? false
    }
    public var unsavedDisplayName: String { path + (activeBlockEdit == nil ? "" : "（編集中）") }
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
            fileSize = try? await service.fileSize(path)
            loadState = .tooLarge
        } catch WorkingTreeTextError.binary {
            loadState = .binary
        } catch WorkingTreeServiceError.outsideRoot(let path) {
            loadState = .outsideRoot(path)
        } catch WorkingTreeTextError.invalidUTF8 {
            readFailureReason = "UTF-8 として読み込めませんでした。Shift_JIS など、別の文字コードで保存されている可能性があります。"
            loadState = .loadFailed
        } catch {
            readFailureReason = error.localizedDescription
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
        synchronizeActiveBlockEditor?()
        guard commitActiveBlockEdit() else { throw DocumentError.blockEditVersionMismatch }
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
            await self.refreshMarkdownAnalysis()
            let expected = overwrite ? nil : self.loadedDiskBytes
            switch try await self.service.save(path: self.path, data: saving, expectedDiskBytes: expected) {
            case .saved:
                self.loadedDiskBytes = saving
                self.baselineAt = Date()
                self.reloadHTMLPreview()
                NotificationCenter.default.post(name: .fileTreeFileSaved, object: nil,
                                                userInfo: ["root": self.root, "path": self.path])
                return SaveResult.saved
            case .conflict:
                return SaveResult.conflictDetected
            }
        }
        pendingSave = task
        return task
    }

    public func invalidate() {
        markdownAnalysisTask?.cancel()
        synchronizeActiveBlockEditor?()
        activeBlockEdit = nil
        synchronizeActiveBlockEditor = nil
        undoManager.removeAllActions()
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
           existing.workingDirectory == workingDirectory || existing.hasUnsavedChanges || existing.hasPendingSaves { return existing }
        storedDocuments[sessionID]?[path]?.invalidate()
        let created = FileTabDocument(path: path, workingDirectory: workingDirectory)
        storedDocuments[sessionID, default: [:]][path] = created
        return created
    }

    public func document(for sessionID: SessionID, path: String, root: String) -> FileTabDocument {
        let root = URL(fileURLWithPath: root, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath().path
        if let existing = storedDocuments[sessionID]?[path],
           existing.root == root || existing.hasUnsavedChanges || existing.hasPendingSaves { return existing }
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

    func documentEntries() -> [(SessionID, FileTabDocument)] {
        storedDocuments.flatMap { id, documents in documents.values.map { (id, $0) } }
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
        (storedDocuments[sessionID] ?? [:]).values.filter(\.hasUnsavedChanges).map(\.fileName).sorted()
    }
}
