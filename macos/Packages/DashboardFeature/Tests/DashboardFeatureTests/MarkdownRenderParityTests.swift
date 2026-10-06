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

    // ブロック分割して個別に描画しても、文書全体を描画した HTML と一致する（ブロック境界の取り違えの回帰防止）。
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
