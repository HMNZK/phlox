import Foundation
import Testing
@testable import DashboardFeature

@MainActor
struct FileTabToolbarTests {
    @Test
    func saveCommandWritesEditableDocument() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("readme.md")
        try Data("元の段落".utf8).write(to: file)
        let document = FileTabDocument(path: "readme.md", root: root.path)
        await document.loadIfNeeded()
        document.draft = "保存する段落"
        let view = FileTabView(document: document, lastWriter: { _ in nil },
                               isFocused: true, openFile: { _, _ in })

        let task = try #require(view.requestSave())
        await task.value
        #expect(try String(contentsOf: file, encoding: .utf8) == "保存する段落")
        #expect(!document.hasUnsavedChanges)
    }

    @Test
    func rejectedSaveCommandPreservesConflictingBlockDraftAndDisk() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("readme.md")
        try Data("元の段落".utf8).write(to: file)
        let document = FileTabDocument(path: "readme.md", root: root.path)
        await document.loadIfNeeded()
        let block = try #require(document.markdownBlocks.first)
        #expect(document.beginBlockEdit(range: block.range))
        document.draft = "先に変わった段落"
        #expect(!document.commitActiveBlockEdit())
        let edit = try #require(document.activeBlockEdit)
        let view = FileTabView(document: document, lastWriter: { _ in nil },
                               isFocused: true, openFile: { _, _ in })

        #expect(view.requestSave() == nil)
        #expect(document.activeBlockEdit?.id == edit.id)
        #expect(document.draft == "先に変わった段落")
        #expect(try String(contentsOf: file, encoding: .utf8) == "元の段落")
    }

    @Test
    func largeMarkdownHelpUsesUTF8BytesRatherThanCharacterCount() {
        let document = FileTabDocument(path: "readme.md", root: "/")
        document.draft = String(repeating: "あ", count: 170_000)
        let view = FileTabView(document: document, lastWriter: { _ in nil },
                               isFocused: true, openFile: { _, _ in })

        #expect(document.markdownPresentationLocked)
        let help = view.markdownReasonDetail(locale: Locale(identifier: "ja"))
        #expect(help.contains("510 KB"))
        #expect(!help.contains("170 KB"))
        #expect(document.draft.count == 170_000)
    }

    @Test
    func manySmallMarkdownBlocksExplainTheBlockLimitRatherThanTheByteLimit() async {
        let document = FileTabDocument(path: "readme.md", root: "/")
        document.draft = (1...2_005).map { "段落 \($0)\n\n" }.joined()
        await document.refreshMarkdownAnalysis()
        let view = FileTabView(document: document, lastWriter: { _ in nil },
                               isFocused: true, openFile: { _, _ in })

        #expect(document.draft.utf8.count < 500_000)
        #expect(document.markdownBlocks.count > 2_000)
        #expect(document.markdownPresentationLocked)
        let help = view.markdownReasonDetail(locale: Locale(identifier: "ja"))
        #expect(help.contains("2,005 ブロック"))
        #expect(!help.contains("KB"))
    }
}
