import AppKit
import AgentDomain
import Testing
@testable import DashboardFeature

@Suite("ブロック編集のレビュー回帰", .serialized)
@MainActor
struct MarkdownBlockRegressionTests {
    @Test func paragraphBeforeTableHasUniqueNonemptyRanges() {
        let source = "前の行\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        let blocks = MarkdownBlocks.parse(source)
        #expect(blocks.allSatisfy { !$0.range.isEmpty })
        #expect(Set(blocks.map(\.id)).count == blocks.count)
        #expect(blocks.map(\.original).joined().utf8.elementsEqual(source.utf8))
    }

    @Test func headingBeforeParagraphAndTableDoesNotCrash() {
        let source = "# 見出し\n\n前の行\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        #expect(MarkdownBlocks.parse(source).map(\.original).joined().utf8.elementsEqual(source.utf8))
    }

    @Test(arguments: ["\u{FEFF}# A\n\nB\n", "# A\n\n\u{FEFF}B\n"])
    func leadingFEFFSurvivesCommit(source: String) throws {
        let document = FileTabDocument(path: "a.md", root: "/")
        document.draft = source
        let block = try #require(document.markdownBlocks.last)
        #expect(document.beginBlockEdit(range: block.range))
        #expect(document.commitActiveBlockEdit())
        #expect(document.draft.utf8.elementsEqual(source.utf8))
        #expect(document.beginBlockEdit(range: block.range))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "C\n")
        #expect(document.commitActiveBlockEdit())
        #expect(Array(document.draft.utf8) == Array(source.utf8.prefix(block.range.lowerBound)) + Array("C\n".utf8))
    }

    @Test func blockUndoDoesNotOverwriteLaterSourceInput() throws {
        let document = FileTabDocument(path: "a.md", root: "/")
        document.draft = "元"
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "確定")
        #expect(document.commitActiveBlockEdit())
        #expect(document.setPresentation(.source))
        document.draft += "その後の入力"
        document.undoManager.undo()
        #expect(document.draft == "確定その後の入力")
    }

    @Test func sourceKeystrokesStayUnderSixteenMilliseconds() {
        let source = String(repeating: "a\n\n", count: 166_000)
        let document = FileTabDocument(path: "a.md", root: "/")
        #expect(document.setPresentation(.source))
        document.draft = source
        let clock = ContinuousClock()
        for _ in 0..<3 {
            let elapsed = clock.measure {
                document.draft += "x"
                _ = document.presentation
                _ = document.markdownPresentationLocked
            }
            print("ソース表示の打鍵: \(elapsed)")
            #expect(elapsed < .milliseconds(16))
        }
    }

    @Test func sessionDeletionIncludesEditingTag() throws {
        let registry = FileTabDocumentRegistry()
        let files = FileTabDocuments()
        let window = registryTestWindow("確認")
        defer { window.close() }
        registry.register(files: files, window: window)
        let session = SessionID()
        let document = files.document(for: session, path: "notes/a.md", root: "/")
        document.draft = "元"
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "入力中")
        #expect(registry.dirtyFileNames(for: [session]) == ["notes/a.md（編集中）"])
    }

    @Test func fileBOMIsSeparatedOnceAndContentFEFFSurvivesSave() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let bom = Data([0xEF, 0xBB, 0xBF])
        let source = "\u{FEFF}# A\n\n\u{FEFF}B\n"
        let file = root.appendingPathComponent("a.md")
        try (bom + Data(source.utf8)).write(to: file)
        let document = FileTabDocument(path: "a.md", root: root.path)
        await document.loadIfNeeded()
        #expect(document.bom == bom)
        #expect(document.draft.utf8.elementsEqual(source.utf8))
        let block = try #require(document.markdownBlocks.last)
        #expect(document.beginBlockEdit(range: block.range))
        #expect(document.commitActiveBlockEdit())
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == bom + Data(source.utf8))
        #expect(document.beginBlockEdit(range: block.range))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "C\n")
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == bom + Data(source.utf8.prefix(block.range.lowerBound)) + Data("C\n".utf8))
    }

    @Test func failedEditCanBeDiscardedWithoutChangingDraft() throws {
        let document = try failedEdit()
        let id = try #require(document.activeBlockEdit?.id)
        document.discardActiveBlockEdit(id: id)
        #expect(document.activeBlockEdit == nil)
        #expect(document.blockEditFailure == nil)
        #expect(document.draft == "別の版")
        #expect(document.setPresentation(.source))
        document.updateActiveBlockEdit(id: id, current: "古い通知")
        #expect(document.activeBlockEdit == nil)
    }

    @Test func failedEditCopiesLatestInputBeforeOpeningSource() throws {
        let document = try failedEdit()
        let id = try #require(document.activeBlockEdit?.id)
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ブロック回帰-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        document.synchronizeActiveBlockEditor = {
            document.updateActiveBlockEdit(id: id, current: "未通知の入力\u{FEFF}")
        }
        #expect(!document.openSourceDiscardingBlockEdit(id: UUID(), pasteboard: pasteboard))
        #expect(document.activeBlockEdit != nil)
        #expect(document.openSourceDiscardingBlockEdit(id: id, pasteboard: pasteboard))
        #expect(pasteboard.string(forType: .string)?.utf8.elementsEqual("未通知の入力\u{FEFF}".utf8) == true)
        #expect(document.activeBlockEdit == nil)
        #expect(document.blockEditFailure == nil)
        #expect(document.draft == "別の版")
        #expect(document.presentation == .source)
    }

    @Test func escapeAfterVersionMismatchKeepsInput() throws {
        let document = try failedEdit()
        let id = try #require(document.activeBlockEdit?.id)
        let editor = CurrentLineTextView(usingTextLayoutManager: false)
        editor.string = "確定できない入力"
        editor.blockEditID = id
        editor.synchronizeBlockEdit = { document.updateActiveBlockEdit(id: $0, current: $1) }
        editor.commitBlockEdit = { document.commitActiveBlockEdit(id: $0) }
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                                timestamp: 0, windowNumber: 0, context: nil,
                                                characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}",
                                                isARepeat: false, keyCode: 53))
        editor.keyDown(with: event)
        #expect(document.activeBlockEdit?.id == id)
        #expect(document.activeBlockEdit?.current == "確定できない入力")
        #expect(document.draft == "別の版")
    }

    @Test func intervalValidatorRejectsGapsOverlapsAndEmptyBlocks() {
        func block(_ range: Range<Int>, _ original: String) -> MarkdownBlock {
            MarkdownBlock(range: range, original: original, renderedMarkdown: "", kind: .raw)
        }
        #expect(MarkdownBlocks.coversSource([block(0..<1, "a"), block(1..<2, "b")], source: "ab"))
        for blocks in [[block(0..<1, "a")], [block(1..<2, "b")],
                       [block(0..<2, "ab"), block(1..<2, "b")],
                       [block(0..<0, ""), block(0..<2, "ab")],
                       [block(0..<3, "abc")], [block(0..<2, "xy")]] {
            #expect(!MarkdownBlocks.coversSource(blocks, source: "ab"))
        }
    }

    @Test func rejectsARangeEndingInsideAUTF8Character() {
        let document = FileTabDocument(path: "a.md", root: "/")
        document.draft = "👩"
        #expect(!document.beginBlockEdit(range: 0..<3))
        #expect(document.activeBlockEdit == nil)
        #expect(document.draft.utf8.elementsEqual("👩".utf8))
    }

    @Test func sourceAnalysisRefreshesLockForTheCurrentVersion() async {
        let document = FileTabDocument(path: "a.md", root: "/")
        #expect(document.setPresentation(.source))
        document.draft = String(repeating: "a\n\n", count: 2_001)
        await document.refreshMarkdownAnalysis()
        #expect(document.markdownPresentationLocked)
        #expect(document.markdownBlocks.count == 2_001)
        document.draft = "小さい文書"
        await document.refreshMarkdownAnalysis()
        #expect(!document.markdownPresentationLocked)
        #expect(document.markdownBlocks.count == 1)
        #expect(document.setPresentation(.rendered))
    }

    private func failedEdit() throws -> FileTabDocument {
        let document = FileTabDocument(path: "a.md", root: "/")
        document.draft = "元"
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "残す入力")
        document.draft = "別の版"
        #expect(!document.commitActiveBlockEdit())
        return document
    }
}
