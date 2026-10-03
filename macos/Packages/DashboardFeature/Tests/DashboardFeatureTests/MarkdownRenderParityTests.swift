import MarkdownUI
import Testing
@testable import DashboardFeature

struct MarkdownRenderParityTests {
    @Test(arguments: [
        "# 見出し\n\n*強調*と**太字**と~~取り消し~~、`inline`。\n",
        "[ref]: guide.md \"案内\"\n\n[先][ref]\n\n[ref]: wrong.md\n\n[後][ref]\n",
        "本文\n[ref]: guide.md\n\n[リンク][ref]\n",
        "| 左 | 中央 | 右 |\n| :--- | :---: | ---: |\n| **太字** | [参照][r] | `a` |\n| あ | い | う |\n\n[r]: guide.md\n",
        "- 親\n  - *子*\n    1. 孫\n\n> 引用\n>\n> - 入れ子\n",
        "- [x] 完了\n- [ ] 未完了\n\nhttps://example.com\n",
        "```swift\nlet a = 1\n\n// 空行を含む\n```\n\n後段\n",
        "前段\n\n```swift\n未閉鎖\n\n# コード\n",
        "<div>\nHTML\n</div>\n\n本文\n"
    ])
    func markdownUIStructureMatchesWholeDocument(source: String) {
        let blocks = MarkdownBlocks.parse(source)
        let blockContent = MarkdownContent {
            for block in blocks { MarkdownContent(block.renderedMarkdown) }
        }
        // 裸の自動リンクには描画されない空テキストノードが付くが、cmark の再出力では消える。
        // 正規出力と HTML の双方を比較し、リンク先・表の配置とセル・入れ子・強調・コード内容を固定する。
        #expect(blockContent.renderMarkdown() == MarkdownContent(source).renderMarkdown())
        #expect(blockContent.renderHTML() == MarkdownContent(source).renderHTML())
    }

    @Test func bareAndAngleAutolinksHaveIdenticalPresentation() {
        let bare = MarkdownContent("https://example.com\n")
        let angle = MarkdownContent("<https://example.com>\n")
        #expect(bare.renderMarkdown() == angle.renderMarkdown())
        #expect(bare.renderHTML() == angle.renderHTML())
        #expect(bare.renderHTML().contains("href=\"https://example.com\""))
    }
}
