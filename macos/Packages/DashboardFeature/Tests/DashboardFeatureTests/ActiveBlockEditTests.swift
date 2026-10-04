import Foundation
import AgentDomain
import Testing
@testable import DashboardFeature

@MainActor
struct ActiveBlockEditTests {
    @Test
    func commitsOnlyTheOriginalByteRangeOnce() throws {
        let document = FileTabDocument(path: "a.md", root: "/tmp")
        let source = "# 日本語\r\n\r\n元\r\n\r\n[ref]: other.md\r\n"
        document.draft = source
        let block = try #require(document.markdownBlocks.last)
        #expect(document.beginBlockEdit(range: block.range))
        let edit = try #require(document.activeBlockEdit)
        document.updateActiveBlockEdit(id: edit.id, current: "新しい本文\r\n")
        #expect(document.draft.utf8.elementsEqual(source.utf8))
        let version = document.version
        #expect(document.commitActiveBlockEdit(id: edit.id))
        #expect(document.draft == "# 日本語\r\n\r\n新しい本文\r\n")
        #expect(document.version == version + 1)
        #expect(!document.commitActiveBlockEdit(id: edit.id))
        document.updateActiveBlockEdit(id: edit.id, current: "古い通知")
        #expect(document.activeBlockEdit == nil)
        #expect(document.version == version + 1)
    }

    @Test
    func rejectsVersionMismatchAndKeepsEditingText() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("元\n".utf8).write(to: root.appendingPathComponent("a.md"))
        let document = FileTabDocument(path: "a.md", root: root.path)
        await document.loadIfNeeded()
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "未確定")
        document.draft = "別の変更"
        #expect(!document.commitActiveBlockEdit())
        #expect(document.activeBlockEdit?.current == "未確定")
        #expect(document.draft == "別の変更")
        #expect(!document.setPresentation(.source))
        #expect(document.presentation == .rendered)
        await #expect(throws: FileTabDocument.DocumentError.blockEditVersionMismatch) {
            try await document.save()
        }
        #expect(document.blockEditFailure != nil)
        #expect(try String(contentsOf: root.appendingPathComponent("a.md"), encoding: .utf8) == "元\n")
    }

    @Test
    func detachedEditorAndDirtyNamesRetainUncommittedBytes() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("é".utf8).write(to: root.appendingPathComponent("a.md"))
        let files = FileTabDocuments()
        let sessionID = SessionID()
        let document = files.document(for: sessionID, path: "a.md", root: root.path)
        await document.loadIfNeeded()
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "e\u{301}")
        document.synchronizeActiveBlockEditor = nil
        #expect(files.document(for: sessionID, path: "a.md", root: root.path) === document)
        #expect(document.activeBlockEdit?.id == id)
        #expect(document.hasUnsavedChanges)
        #expect(!document.isDirty)
        #expect(files.dirtyFileNames(for: sessionID) == ["a.md"])
        #expect(document.unsavedDisplayName == "a.md（編集中）")
        document.discardActiveBlockEdit(id: id)
        document.updateActiveBlockEdit(id: id, current: "撤去後の通知")
        #expect(!document.hasUnsavedChanges)
        #expect(document.activeBlockEdit == nil)
    }

    @Test
    func commitSaveUndoRedoPreservesNewlinesAndOneDocumentHistoryEntry() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.md")
        try Data("元\n".utf8).write(to: file)
        let document = FileTabDocument(path: "a.md", root: root.path)
        await document.loadIfNeeded()
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.synchronizeActiveBlockEditor = {
            document.updateActiveBlockEdit(id: id, current: "変更\n追加行\n")
        }
        #expect(try await document.save() == .saved)
        #expect(document.activeBlockEdit == nil)
        #expect(!document.hasUnsavedChanges)
        #expect(try Data(contentsOf: file) == Data("変更\n追加行\n".utf8))
        document.undoManager.undo()
        #expect(document.draft == "元\n")
        #expect(document.hasUnsavedChanges)
        #expect(!document.undoManager.canUndo)
        #expect(document.markdownBlocks.first?.original == "元\n")
        document.undoManager.redo()
        #expect(document.draft == "変更\n追加行\n")
        #expect(!document.hasUnsavedChanges)
        #expect(document.markdownBlocks.first?.original == "変更\n追加行\n")
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        document.undoManager.undo()
        #expect(document.draft == "変更\n追加行\n")
        let second = try #require(document.activeBlockEdit)
        #expect(second.id != id)
        document.updateActiveBlockEdit(id: second.id, current: "次の変更\n")
        #expect(document.commitActiveBlockEdit())
        document.undoManager.undo()
        #expect(document.draft == "変更\n追加行\n")
        document.undoManager.undo()
        #expect(document.draft == "元\n")
    }

    @Test
    func savesDetectExternalChangeAfterCommittingBlock() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.md")
        try Data("元\n".utf8).write(to: file)
        let document = FileTabDocument(path: "a.md", root: root.path)
        await document.loadIfNeeded()
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "変更\n")
        try Data("外部\n".utf8).write(to: file)
        #expect(try await document.save() == .conflictDetected)
        #expect(document.draft == "変更\n")
        #expect(document.hasUnsavedChanges)
        #expect(try Data(contentsOf: file) == Data("外部\n".utf8))
    }

    @Test
    func pendingSaveKeepsNewerUncommittedEditDirty() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a.md")
        try Data("元\n".utf8).write(to: file)
        let document = FileTabDocument(path: "a.md", root: root.path)
        await document.loadIfNeeded()
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let firstID = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: firstID, current: "保存する版\n")
        let save = try document.enqueueSave(overwrite: false)
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let second = try #require(document.activeBlockEdit)
        document.updateActiveBlockEdit(id: second.id, current: "次の未確定版\n")
        #expect(try await save.value == .saved)
        #expect(document.draft == "保存する版\n")
        #expect(document.activeBlockEdit?.current == "次の未確定版\n")
        #expect(document.activeBlockEdit?.baseVersion == document.version)
        #expect(document.hasUnsavedChanges)
        #expect(!document.isDirty)
        #expect(try Data(contentsOf: file) == Data("保存する版\n".utf8))
        #expect(try await document.save() == .saved)
        #expect(!document.hasUnsavedChanges)
        #expect(try Data(contentsOf: file) == Data("次の未確定版\n".utf8))
    }

    @Test
    func movingToFollowingBlockAdjustsItsOriginalRange() throws {
        let document = FileTabDocument(path: "a.md", root: "/tmp")
        document.draft = "前\n\n後\n"
        let blocks = document.markdownBlocks
        #expect(document.beginBlockEdit(range: blocks[0].range))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "長くなった前\n\n")
        #expect(document.beginBlockEdit(range: blocks[1].range))
        #expect(document.activeBlockEdit?.original == "後\n")
        #expect(document.activeBlockEdit?.baseVersion == document.version)
    }

    @Test
    func invalidationRejectsOldCallbacks() throws {
        let document = FileTabDocument(path: "a.md", root: "/tmp")
        document.draft = "元"
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.invalidate()
        document.updateActiveBlockEdit(id: id, current: "変更")
        #expect(document.activeBlockEdit == nil)
        #expect(!document.commitActiveBlockEdit(id: id))
        #expect(document.draft == "元")
    }

    @Test
    func confirmationLabelsAndExplainsActiveEditing() {
        let summary = UnsavedChangesContent(windows: [UnsavedWindow(name: "ウィンドウ", files: [
            UnsavedFile(name: "a.md", context: "", editingBlock: true),
        ])]).textSummary
        #expect(summary.contains("a.md（編集中）"))
        #expect(summary.contains("編集中のブロックの内容も保存されていません。"))
    }
}
