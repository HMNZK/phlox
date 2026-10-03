import Foundation
import Testing
@testable import DashboardFeature

struct MarkdownBlocksTests {
    @Test(arguments: [
        "", " \n\t\n", "[ref]: /guide.md\n", "# 見出し\n\n本文\n",
        "- 親\n  - 子\n    1. 孫\n\n後段\n",
        "| 左 | 右 |\n| :--- | ---: |\n| あ | い |\n\n次\n",
        "```swift\nlet a = 1\n\nlet b = 2\n```\n\n後段\n",
        "前段\n\n```swift\n未閉鎖\n\n# フェンス内\n",
        "<div>\nHTML\n</div>\n\n後段\n",
        "[先][ref]\n\n[ref]: /guide.md\n\n[後][ref]\n",
        "[ref]: /guide.md\n[ref]: /other.md\n\n[先][ref]\n\n[後][ref]\n",
        "本文\n[ref]: /guide.md\n\n[リンク][ref]\n",
        "---\ntitle: 文書\n---\n\n# 本文\n\n終わり\n",
        "---\ntitle: 文書\n---",
        "# 見出し\r\n\r\n本文 👩‍💻\r\n",
        "# 見出し\r\r本文\r",
        "# 見出し\n\n前の行\n| a | b |\n|---|---|\n| 1 | 2 |\n",
        "前の行\n| a | b |\n|---|---|\n| 1 | 2 |\n",
        "\u{FEFF}# 見出し\n\n\u{FEFF}本文\n",
        "\n[ref]: /guide.md\n\n# 先頭の残余\n\n本文\n"
    ])
    func rangesCoverOriginalBytesExactly(source: String) {
        let blocks = MarkdownBlocks.parse(source)
        #expect(!blocks.isEmpty)
        #expect(Array(blocks.map(\.original).joined().utf8) == Array(source.utf8))
        #expect(blocks.first?.range.lowerBound == 0)
        #expect(blocks.last?.range.upperBound == source.utf8.count)
        #expect(Set(blocks.map(\.id)).count == blocks.count)
        if !source.isEmpty { #expect(blocks.allSatisfy { !$0.range.isEmpty }) }
        for index in blocks.indices {
            #expect(blocks[index].range.count == blocks[index].original.utf8.count)
            if index > 0 { #expect(blocks[index - 1].range.upperBound == blocks[index].range.lowerBound) }
            let bytes = Array(source.utf8)
            let start = blocks[index].range.lowerBound
            #expect(start == 0 || bytes[start - 1] == 10 || bytes[start - 1] == 13)
        }
    }

    @Test func definitionsAndGapsBelongToOriginalRanges() {
        let source = "[先][ref]\n\n[ref]: /first.md\n\n[後][ref]\n\n[ref]: /second.md\n"
        let blocks = MarkdownBlocks.parse(source)
        #expect(blocks.count == 2)
        #expect(blocks[0].original == "[先][ref]\n\n[ref]: /first.md\n\n")
        #expect(blocks[1].original == "[後][ref]\n\n[ref]: /second.md\n")
        #expect(blocks[0].renderedMarkdown.contains("[先](/first.md)"))
        #expect(blocks[1].renderedMarkdown.contains("[後](/first.md)"))
        #expect(!blocks[0].renderedMarkdown.contains("[ref]:"))
    }

    @Test func leadingDefinitionUsesFirstDefinitionForEveryNode() {
        let blocks = MarkdownBlocks.parse("[ref]: /first.md\n\n[先][ref]\n\n[ref]: /second.md\n\n[後][ref]\n")
        #expect(blocks.count == 2)
        #expect(blocks[0].original.hasPrefix("[ref]: /first.md\n"))
        #expect(blocks.allSatisfy { $0.renderedMarkdown.contains("/first.md") && !$0.renderedMarkdown.contains("/second.md") })
    }

    @Test func unfinishedFenceIsClosedOnlyInRendering() {
        let blocks = MarkdownBlocks.parse("前段\n\n```swift\n未閉鎖\n\n# コード\n")
        #expect(blocks.count == 2)
        #expect(blocks[1].original == "```swift\n未閉鎖\n\n# コード\n")
        #expect(blocks[1].renderedMarkdown.hasSuffix("```\n"))
        #expect(blocks[1].renderedMarkdown.contains("# コード"))
    }

    @Test func frontMatterIsIndependentAndOffsetsBody() {
        let front = "---\r\ntitle: 文書\r\n---\r\n"
        let blocks = MarkdownBlocks.parse(front + "\r\n# 見出し\r\n\r\n本文\r\n")
        #expect(blocks.count == 3)
        #expect(blocks[0].kind == .frontMatter)
        #expect(blocks[0].original == front)
        #expect(blocks[0].renderedMarkdown.isEmpty)
        #expect(blocks[1].range.lowerBound == front.utf8.count)
        #expect(blocks[1].kind == .heading(level: 1))
        #expect(blocks[1].original == "\r\n# 見出し\r\n\r\n")
    }

    @Test func absentNodesRemainEditable() {
        #expect(MarkdownBlocks.parse("").first?.kind == .empty)
        #expect(MarkdownBlocks.parse(" \n").first?.kind == .raw)
        #expect(MarkdownBlocks.parse("[ref]: /guide.md\n").first?.kind == .raw)
        #expect(MarkdownBlocks.parse("---\n本文\n").first?.kind == .markdown)
    }

    @Test @MainActor func oneReplacementPreservesEveryOtherByte() throws {
        let source = "# 表題\r\n\r\n[本文][ref]\r\n\r\n[ref]: /guide.md\r\n\r\n```\r\n原文\r\n"
        let blocks = MarkdownBlocks.parse(source)
        let edited = try #require(blocks.dropFirst().first)
        let bytes = Array(source.utf8)
        let replacement = Array("変更後 👩‍💻\r\n\r\n".utf8)
        let document = FileTabDocument(path: "a.md", root: "/")
        document.draft = source
        #expect(document.beginBlockEdit(range: edited.range))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: String(decoding: replacement, as: UTF8.self))
        #expect(document.commitActiveBlockEdit(id: id))
        let result = Array(document.draft.utf8)
        #expect(Array(result[edited.range.lowerBound..<(edited.range.lowerBound + replacement.count)]) == replacement)
        #expect(Array(result.prefix(edited.range.lowerBound)) == Array(bytes.prefix(edited.range.lowerBound)))
        #expect(Array(result.suffix(bytes.count - edited.range.upperBound)) == Array(bytes.suffix(bytes.count - edited.range.upperBound)))
    }
}
