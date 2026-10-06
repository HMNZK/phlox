import AppKit
import SwiftUI
import Testing
@testable import DashboardFeature

@MainActor
struct PresentationLockTests {
    @Test(arguments: [2_000, 2_001])
    func blockCountBoundary(count: Int) {
        let document = FileTabDocument(path: "a.md", root: "/tmp")
        document.draft = String(repeating: "本文\n\n", count: count)
        #expect(document.markdownBlocks.count == count)
        #expect(document.markdownPresentationLocked == (count > 2_000))
        #expect(document.presentation == (count > 2_000 ? .source : .rendered))
        #expect(document.setPresentation(.rendered) == (count <= 2_000))
    }

    @Test(arguments: [500_000, 500_001])
    func byteCountBoundary(count: Int) {
        let document = FileTabDocument(path: "a.markdown", root: "/tmp")
        document.draft = String(repeating: "a", count: count)
        #expect(document.markdownPresentationLocked == (count > 500_000))
        #expect(document.setPresentation(.rendered) == (count <= 500_000))
        if count > 500_000 {
            document.presentation = .rendered
            #expect(document.presentation == .source)
            #expect(!document.beginBlockEdit(range: 0..<count))
        }
    }

    @Test
    func countsUTF8BytesAndReevaluatesAfterUndo() throws {
        let document = FileTabDocument(path: "a.md", root: "/tmp")
        document.draft = "元"
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: String(repeating: "あ", count: 166_667))
        #expect(document.commitActiveBlockEdit())
        #expect(document.markdownPresentationLocked)
        #expect(!document.setPresentation(.rendered))
        document.undoManager.undo()
        #expect(!document.markdownPresentationLocked)
        #expect(document.draft == "元")
    }

    @Test
    func modeSwitchSynchronizesAndCommitsPendingInput() throws {
        let document = FileTabDocument(path: "a.md", root: "/tmp")
        document.draft = "元"
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.synchronizeActiveBlockEditor = { document.updateActiveBlockEdit(id: id, current: "同期した入力") }
        #expect(document.setPresentation(.source))
        #expect(document.draft == "同期した入力")
        #expect(document.activeBlockEdit == nil)
        #expect(document.presentation == .source)
    }

    @Test func firstPresentationAfterLoadLocksLargeDocument() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(".読み込み検証-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { Issue.record("一時フォルダの削除に失敗: \(error)") }
        }
        #expect(root.deletingLastPathComponent().resolvingSymlinksInPath()
                == FileManager.default.temporaryDirectory.resolvingSymlinksInPath())
        let source = String(repeating: "a\n\n", count: 2_001)
        try Data(source.utf8).write(to: root.appendingPathComponent("a.md"))
        let document = FileTabDocument(path: "a.md", root: root.path)
        defer { document.invalidate() }
        await document.loadIfNeeded()
        #expect(document.loadState == .loaded)
        #expect(document.draft == source)
        #expect(document.presentation == .source)
    }

    @Test func firstPresentationAfterCommitLocksLargeDocument() throws {
        let document = FileTabDocument(path: "a.md", root: "/")
        defer { document.invalidate() }
        document.draft = String(repeating: "a\n\n", count: 2_000)
        #expect(document.presentation == .rendered)
        #expect(document.beginBlockEdit(range: 0..<3))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "a\n\na\n\n")
        #expect(document.commitActiveBlockEdit())
        #expect(document.presentation == .source)
    }

    @Test func firstPresentationAfterUndoLocksLargeDocument() async throws {
        let document = FileTabDocument(path: "a.md", root: "/")
        defer { document.invalidate() }
        #expect(document.setPresentation(.source))
        let source = String(repeating: "a\n\n", count: 2_001)
        document.draft = source
        #expect(document.beginBlockEdit(range: 0..<source.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "小さい")
        #expect(document.commitActiveBlockEdit())
        await document.refreshMarkdownAnalysis()
        #expect(document.setPresentation(.rendered))
        #expect(document.presentation == .rendered)
        #expect(document.undoManager.canUndo)
        document.undoManager.undo()
        #expect(document.draft == source)
        #expect(document.presentation == .source)
    }

    @Test func temporarySourceLockDoesNotParseDuringInput() async throws {
        let document = FileTabDocument(path: "a.md", root: "/")
        defer { document.invalidate() }
        let source = String(repeating: String(repeating: "a", count: 68) + "\n\n", count: 6_816)
        #expect(source.utf8.count <= 500_000)
        document.draft = source
        await document.refreshMarkdownAnalysis()
        #expect(document.markdownBlocks.count > 2_000)
        #expect(document.presentation == .source)
        let drafts = (1...5).map { source + String(repeating: "b", count: $0) }
        let clock = ContinuousClock()
        let started = clock.now
        for draft in drafts {
            document.draft = draft
            #expect(document.presentation == .source)
        }
        let elapsed = started.duration(to: clock.now)
        print("ソース固定中の入力5回: \(elapsed)")
        #expect(elapsed < .milliseconds(50))
        document.draft = "小さい"
        try await Task.sleep(for: .milliseconds(800))
        #expect(document.presentation == .rendered)
    }

    @Test func refusedRenderRequestDoesNotSurviveSourceLock() async throws {
        let document = FileTabDocument(path: "a.md", root: "/")
        defer { document.invalidate() }
        #expect(document.setPresentation(.source))
        document.draft = String(repeating: "a\n\n", count: 2_001)
        #expect(!document.setPresentation(.rendered))
        try await Task.sleep(for: .milliseconds(800))
        #expect(document.presentation == .source)
        document.draft = "小さい"
        try await Task.sleep(for: .milliseconds(800))
        #expect(document.presentation == .source)
    }

    @Test func renderRequestSurvivesInput() async throws {
        let document = FileTabDocument(path: "a.md", root: "/")
        #expect(document.setPresentation(.source))
        document.draft = "# A\n"
        _ = document.setPresentation(.rendered)
        document.draft = "# A\nB\n"
        try await Task.sleep(for: .milliseconds(800))
        #expect(document.presentation == .rendered)
    }

    @Test func laterSourceChoiceWins() async throws {
        let document = FileTabDocument(path: "a.md", root: "/")
        #expect(document.setPresentation(.source))
        document.draft = String(repeating: "段落\n\n", count: 1_500)
        _ = document.setPresentation(.rendered)
        #expect(document.setPresentation(.source))
        try await Task.sleep(for: .milliseconds(800))
        #expect(document.presentation == .source)
    }

    @Test func refusedUndoKeepsHistory() throws {
        let document = FileTabDocument(path: "a.md", root: "/")
        document.draft = "元"
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "確定")
        #expect(document.commitActiveBlockEdit())
        #expect(document.setPresentation(.source))
        document.draft = "確定後"
        let hosting = DocumentHostingView(rootView: SwiftUI.Text("文書"), document: document)
        let undo = NSMenuItem(title: "取り消す", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        #expect(!hosting.validateUserInterfaceItem(undo))
        document.undoManager.undo()
        #expect(document.draft == "確定後")
        #expect(!document.undoManager.canRedo)
        document.draft = "確定"
        #expect(document.undoManager.canUndo)
        #expect(hosting.validateUserInterfaceItem(undo))
        document.undoManager.undo()
        #expect(document.draft == "元")
        document.undoManager.redo()
        #expect(document.draft == "確定")
    }

    @Test(arguments: [true, false])
    func temporarySourceLockPreservesChoice(byteLimit: Bool) async {
        let document = FileTabDocument(path: "a.md", root: "/")
        document.draft = "小さい"
        #expect(document.presentation == .rendered)
        document.draft = byteLimit ? String(repeating: "a", count: 500_001) : String(repeating: "a\n\n", count: 2_001)
        #expect(document.presentation == .source)
        document.draft = "小さい"
        await document.refreshMarkdownAnalysis()
        #expect(document.presentation == .rendered)
        #expect(document.setPresentation(.source))
        document.draft = String(repeating: "a", count: 500_001)
        #expect(document.presentation == .source)
        document.draft = "小さい"
        #expect(document.presentation == .source)
    }
}
