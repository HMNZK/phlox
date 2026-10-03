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
}
