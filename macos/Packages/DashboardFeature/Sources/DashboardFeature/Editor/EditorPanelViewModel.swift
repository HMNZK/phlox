import Foundation
import Observation
import AgentDomain

@MainActor
@Observable
public final class EditorPanelViewModel {
    public enum ListState: Equatable, Sendable {
        case noProject
        case notARepository
        case ready
    }

    public enum Detail: Equatable, Sendable {
        case none
        case diff(String)
        case content(String)
        case binary
    }

    public enum SaveResult: Equatable, Sendable {
        case saved
        case conflictDetected
    }

    public private(set) var listState: ListState = .noProject
    public private(set) var changes: [WorkingTreeChange] = []
    public private(set) var selectedPath: String?
    public private(set) var detail: Detail = .none
    /// 変更一覧の帰属範囲。`ListState`（表示対象の有無）とは分離して保持する。
    public private(set) var changeScope: SessionChangeScope
    var listErrorMessage: String?
    var readOnlyMessage: String?
    public var draft = "" {
        didSet {
            isDirty = loadedDiskContent.map { draft != $0 } ?? false
        }
    }
    public private(set) var isDirty = false

    private let service: WorkingTreeService?
    private static let maximumEditableFileSize = 1_000_000
    /// 選択時に読んだ内容。競合検出の基準であり、draft そのものではない。
    private var loadedDiskContent: String?
    private var selectionGeneration = 0

    /// バイナリや読み込みに失敗したファイルを TextEditor に渡さないための内部状態。
    var canEdit: Bool {
        selectedPath != nil && loadedDiskContent != nil
    }

    public init(
        service: WorkingTreeService?,
        changeScope: SessionChangeScope = .unavailable
    ) {
        self.service = service
        self.changeScope = changeScope
    }

    /// 共有相手の増減など、表示対象の変更を伴わない帰属範囲の変化だけを反映する。
    public func updateChangeScope(_ changeScope: SessionChangeScope) {
        self.changeScope = changeScope
    }

    public func refresh() async {
        guard let service else {
            listState = .noProject
            listErrorMessage = nil
            changes = []
            clearSelection()
            return
        }

        guard await service.isGitRepository() else {
            listState = .notARepository
            listErrorMessage = nil
            changes = []
            clearSelection()
            return
        }

        do {
            changes = try await service.changes()
            listState = .ready
            listErrorMessage = nil
        } catch {
            changes = []
            clearSelection()
            listState = .ready
            listErrorMessage = "Unable to load changes. Try refreshing."
        }
    }

    public func select(_ path: String) async {
        selectionGeneration &+= 1
        let generation = selectionGeneration
        guard let service else {
            clearSelection()
            return
        }

        do {
            let workingTreeDetail = try await service.detail(for: path)
            guard generation == selectionGeneration else { return }
            switch workingTreeDetail {
            case .binary:
                selectedPath = path
                detail = .binary
                clearDraft()
                readOnlyMessage = "Binary files cannot be edited."
            case .diff(let diff):
                selectedPath = path
                detail = .diff(diff)
                do {
                    let contents = try await service.fileContents(path)
                    guard generation == selectionGeneration else { return }
                    loadDraft(contents)
                } catch {
                    guard generation == selectionGeneration else { return }
                    clearDraft()
                    readOnlyMessage = "This file is unavailable or is not valid UTF-8. Its diff is read-only."
                }
            case .untrackedContent(let contents):
                selectedPath = path
                detail = .content(contents)
                loadDraft(contents)
            }
        } catch {
            guard generation == selectionGeneration else { return }
            // 非 UTF-8・削除済み・不正パスを UI へ例外として出さない。
            clearSelection()
        }
    }

    public func save() async throws -> SaveResult {
        let (service, path, expectedDiskContent) = try editableSelection()
        let savedDraft = draft
        let generation = selectionGeneration
        switch try await service.save(path: path, content: savedDraft, expectedDiskContent: expectedDiskContent) {
        case .saved:
            await reloadAfterSaving(path, savedDraft: savedDraft, generation: generation)
            return .saved
        case .conflict:
            return .conflictDetected
        }
    }

    public func overwrite() async throws {
        let (service, path, _) = try editableSelection()
        let savedDraft = draft
        let generation = selectionGeneration
        _ = try await service.save(path: path, content: savedDraft, expectedDiskContent: nil)
        await reloadAfterSaving(path, savedDraft: savedDraft, generation: generation)
    }

    private func editableSelection() throws -> (WorkingTreeService, String, String) {
        guard let service, let selectedPath, let loadedDiskContent else {
            throw EditorPanelError.noEditableSelection
        }
        return (service, selectedPath, loadedDiskContent)
    }

    private func reloadAfterSaving(_ path: String, savedDraft: String, generation: Int) async {
        await refresh()
        guard generation == selectionGeneration, selectedPath == path else { return }
        guard draft == savedDraft else {
            loadedDiskContent = savedDraft
            isDirty = true
            return
        }
        await select(path)
    }

    private func loadDraft(_ contents: String) {
        guard contents.utf8.count <= Self.maximumEditableFileSize else {
            clearDraft()
            readOnlyMessage = "This file is too large to edit here."
            return
        }

        readOnlyMessage = nil
        loadedDiskContent = contents
        draft = contents
        isDirty = false
    }

    private func clearDraft() {
        loadedDiskContent = nil
        draft = ""
        isDirty = false
    }

    private func clearSelection() {
        selectedPath = nil
        detail = .none
        readOnlyMessage = nil
        clearDraft()
    }
}

private enum EditorPanelError: Error {
    case noEditableSelection
}
