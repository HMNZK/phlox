import AppKit
import SwiftUI
import MarkdownUI
import Testing
@testable import DashboardFeature

struct MarkdownReviewParityTests {
    @Test(arguments: ["段落\n\n", "- 項目\n\n", "# 見出し\n\n", "<div>\n本文\n</div>\n\n"])
    func leadingTableParagraph(prefix: String) throws {
        let source = prefix + "前の行\n| a | b |\n|---|---|\n| 1 | 2 |\n"
        let blocks = MarkdownBlocks.parse(source)
        let owner = try #require(blocks.first { $0.original.contains("前の行") })
        #expect(owner.renderedMarkdown.contains("前の行"))
        #expect(MarkdownContent { for block in blocks { MarkdownContent(block.renderedMarkdown) } }.renderHTML()
                == MarkdownContent(source).renderHTML())
    }

    @Test(arguments: [
        "- 箇条書き\n\n1. 番号\n",
        "- 項目\n\n  ```\n  code\n  ```\n",
        "- 項目\n\n    code\n",
        "```\n```\n",
        "段落\n\n```\n",
        "**_a_**\n",
        "*_a_*\n",
        "***a***\n",
        "_**a**_\n",
        "**a _b_ c**\n",
        "*a **b** c*\n",
        "**a*b*c**\n",
        "*a**b**c*\n",
        "*これは**重要***\n",
        "**これは*重要***\n",
        "**a*b***\n",
        "*a**b***\n",
        "これは***重要*です**\n",
        "これは***重要**です*\n",
        "a***b*c**\n",
        "a***b**c*\n",
        "**重要な*注意***です\n",
        "*a\n&#32;&#32;&#32;&#32;b*\n",
        "*a&#32;&#32;\nb*\n",
        "*a\n&#32;- b*\n",
        "**&#32;a**\n",
        "*a&#32;*\n",
        "***a**&#32;*\n",
        "*&#32;**a***\n",
        "**&#32;*a***\n",
        "***a*&#32;**\n",
        "*a\n&#32;**b***\n",
        "**a\n&#32;*b***\n",
        "***a**&#32;\nb*\n",
        "*a&#32;**b**&#32;\nc*\n",
        "*~~旧~~**新***\n",
        "**~~旧~~*新***\n",
        "***新**~~旧~~*\n",
        "***新*~~旧~~**\n",
        "_~~a~~**b**_\n",
        "*a~~b~~**c***\n",
        "*~~a~~**b**c*\n",
        "*a**b**~~c~~*\n",
        "**a~~b~~*c***\n",
        "***a*~~b~~c**\n",
        "*~~a~~**b**~~c~~*\n",
        "**~~a~~*b*~~c~~**\n",
        "*~~[旧](old.md)~~**新***\n",
        "***新**~~[旧](old.md)~~*\n",
        "**~~[旧](old.md)~~*新***\n",
        "***新*~~[旧](old.md)~~**\n",
        "*~~`旧`~~**新***\n",
        "***新**~~`旧`~~*\n",
        "**~~`旧`~~*新***\n",
        "***新*~~`旧`~~**\n",
        "*~~![旧](old.png)~~**新***\n",
        "***新**~~![旧](old.png)~~*\n",
        "**~~![旧](old.png)~~*新***\n",
        "***新*~~![旧](old.png)~~**\n",
        "*[~~旧~~**新**](new.md)*\n",
        "**[~~旧~~*新*](new.md)**\n",
        "*![~~旧~~**新**](new.png)*\n",
        "**![~~旧~~*新*](new.png)**\n",
        "*`前`~~旧~~**新***\n",
        "***新**~~旧~~`後`*\n",
        "*[前](a.md)~~旧~~**新***\n",
        "***新**~~旧~~![後](b.png)*\n",
        "**名前（説明）**続く文\n最後の**字**続く文。\n",
        "*外側 *中側 *内側 *中心* 終わり* 終わり* 終わり*\n",
        "__外側 __中側 __内側 __中心__ 終わり__ 終わり__ 終わり__\n",
        "***外側 ***中側 ***内側 ***中心*** 終わり*** 終わり*** 終わり***\n",
        "* ---\n",
        "- [x] a\n- ```\n  code\n  ```\n",
        "```&amp;amp;\ncode\n```\n",
        "```a\\\\\\*\ncode\n```\n",
        "999999999. a\n999999999. b\n",
        "- 項目\n\n```\ncode\n```\n",
        "- A\n  ```swift\n  code\n  ```\n  B\n- C\n",
        "前の行\n後の行\n---\n",
        "本文\n     | a | b |\n     |---|---|\n     | 1 | 2 |\n",
        "| a | b |\n|---|---|\n| ` ` | `  ` |\n",
        "- 親\n  1. A\n  2) B\n",
        "a*強調*b **太字** *a*_b_ **a**__b__ ***入れ子***\n",
        "文字 <span>HTML</span> ` ` と ![**画像**](image.png)\n",
        "| a | b |\n|---|---|\n| <span>HTML</span> | ` ` ![画像](image.png) |\n",
        "[リンク](<guide (1).md>) と [空]()\n",
        "- [x] A\n  ```\n  code\n  ```\n  B\n- [ ] C\n",
        "````\n```\nコード\n````\n",
        "[先][r]\n\n[r]: first.md\n\n[後][r]\n\n[r]: second.md\n",
        "[先][r]\n\n```\n[r]: hidden.md\n"
    ])
    func renderingParity(source: String) {
        let blocks = MarkdownBlocks.parse(source)
        #expect(MarkdownContent { for block in blocks { MarkdownContent(block.renderedMarkdown) } }.renderHTML()
                == MarkdownContent(source).renderHTML())
    }
}

@MainActor
struct MarkdownReviewStateTests {
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
