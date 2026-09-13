// 実パス: macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptMarkdownPresentationTests.swift
// task-47（UX-05b）受け入れテスト（PM 著・不変）。TranscriptMarkdownPresentation と
// AgentMessageBody(text:bodyColor:) / RichMarkdownView 本文色付き入口が未実装ならコンパイル RED が正常。
// 期待値は tasks/task-47.md の独立リテラル。製品の prepare / summary / 切り詰めから生成しない。
//
// 凍結する公開面:
//   enum TranscriptMarkdownPresentation
//     static func prepare(_ source: String) -> String
//     static func summary(_ source: String) -> String?
//   AgentMessageBody(text:bodyColor:) 既定 primary（DSColor.chatTextPrimary）
//   RichMarkdownView(_:) / RichMarkdownView(streaming:) に bodyColor 既定 primary
//   RichMarkdownView.themeCacheKey(themeID:scale:bodyColor:)
// ChatMarkdownFormatter.splitFencedCodeBlocks / ChatMarkdownBlock は既存 API を維持する。

import DesignSystem
import Foundation
import Testing
@testable import SessionFeature

private func prepare(_ source: String) -> String {
    TranscriptMarkdownPresentation.prepare(source)
}

private func summary(_ source: String) -> String? {
    TranscriptMarkdownPresentation.summary(source)
}

private func utf8(_ value: String) -> [UInt8] {
    Array(value.utf8)
}

private func expectPrepared(_ source: String, _ want: String) {
    #expect(utf8(prepare(source)) == utf8(want))
}

private func expectSummary(_ source: String, _ want: String?) {
    let got = summary(source)
    switch (got, want) {
    case (nil, nil):
        break
    case let (got?, want?):
        #expect(utf8(got) == utf8(want))
    default:
        Issue.record("summary の Optional が一致しない got=\(String(describing: got)) want=\(String(describing: want))")
    }
}

private func expectBlocks(_ source: String, _ expected: [ChatMarkdownBlock]) {
    let blocks = ChatMarkdownFormatter.splitFencedCodeBlocks(source)
    #expect(blocks == expected)
    #expect(blocks.count == expected.count)
    for (got, want) in zip(blocks, expected) {
        switch (got, want) {
        case (.markdown(let gotText), .markdown(let wantText)):
            #expect(utf8(gotText) == utf8(wantText))
        case (.code(let gotLang, let gotText), .code(let wantLang, let wantText)):
            #expect(gotLang == wantLang)
            #expect(utf8(gotText) == utf8(wantText))
        default:
            Issue.record("ChatMarkdownBlock の case が一致しない")
        }
    }
}

private enum FrozenSixty {
    static let part1 = "あいうえおかきくけこ"
    static let part2 = "さしすせそたちつてと"
    static let part3 = "なにぬねのはひふへほ"
    static let part4 = "まみむめもやゆよわを"
    static let part5 = "0123456789"
    static let part6 = "Ae\u{301}👨‍👩‍👧‍👦BCDEFGH"
    static let sixty = part1 + part2 + part3 + part4 + part5 + part6
}

@Suite("task-47: TranscriptMarkdownPresentation prepare")
struct AcceptanceTranscriptMarkdownPrepareTests {
    @Test("閉じた強調・見出しは入力不変")
    func closedEmphasisUnchanged() {
        #expect(prepare("**確認済み**") == "**確認済み**")
        #expect(prepare("## **確認結果**") == "## **確認結果**")
    }

    @Test("未閉じの4区切りを最終物理行末で閉じる")
    func unclosedDelimitersOnLastPhysicalLine() {
        #expect(prepare("**確認") == "**確認**")
        #expect(prepare("*確認") == "*確認*")
        #expect(prepare("__確認") == "__確認__")
        #expect(prepare("_確認") == "_確認_")
        #expect(prepare("説明 **確認") == "説明 **確認**")
        #expect(prepare("説明 *確認") == "説明 *確認*")
        #expect(prepare("説明 __確認") == "説明 __確認__")
        #expect(prepare("説明 _確認") == "説明 _確認_")
    }

    @Test("部分閉じは不足1文字だけ補う")
    func partialCloseAddsOneDelimiter() {
        #expect(prepare("**確認*") == "**確認**")
        #expect(prepare("__確認_") == "__確認__")
    }

    @Test("閉じた強調の後の未閉じだけ補正し、最外だけ補正する")
    func closedThenUnclosedAndOutermostOnly() {
        #expect(prepare("**済み** と *確認") == "**済み** と *確認*")
        #expect(prepare("**外 *内") == "**外 *内**")
        #expect(prepare("**外 *内**") == "**外 *内**")
    }

    @Test("閉じ記号は行末空白・タブの直前へ補う")
    func closeBeforeTrailingWhitespace() {
        #expect(prepare("**確認  \t") == "**確認**  \t")
    }

    @Test("改行を跨ぐ未閉じは対象外、最終物理行と空行区切り段落は対象")
    func newlineBoundaries() {
        #expect(prepare("**確認\n次行") == "**確認\n次行")
        #expect(prepare("前行\n**確認") == "前行\n**確認**")
        #expect(prepare("**確認\n\n次段") == "**確認**\n\n次段")
        #expect(prepare("**確認\n\n") == "**確認**\n\n")
    }

    @Test("本文のない区切り・見出し・3連・識別子内部・演算子は補正しない")
    func outOfScopeKept() {
        #expect(prepare("**") == "**")
        #expect(prepare("*") == "*")
        #expect(prepare("__") == "__")
        #expect(prepare("_") == "_")
        #expect(prepare("## ") == "## ")
        #expect(prepare("***確認") == "***確認")
        #expect(prepare("___確認") == "___確認")
        #expect(prepare("説明**確認") == "説明**確認")
        #expect(prepare("a * b") == "a * b")
        #expect(prepare("2 ** 3") == "2 ** 3")
        #expect(prepare("foo_bar") == "foo_bar")
        #expect(prepare("C#") == "C#")
        #expect(prepare("##tag") == "##tag")
        #expect(prepare("\\*\\*literal\\*\\*") == "\\*\\*literal\\*\\*")
        #expect(prepare("~~未閉じ") == "~~未閉じ")
        #expect(prepare("[未閉じ](url") == "[未閉じ](url")
    }

    @Test("保護領域の内部は補正しない")
    func protectedRegionsUnchanged() {
        #expect(prepare("`**未閉じ`") == "`**未閉じ`")
        #expect(prepare("`**未閉じ") == "`**未閉じ")
        #expect(prepare("    **未閉じ") == "    **未閉じ")
        #expect(prepare("\t**未閉じ") == "\t**未閉じ")
        #expect(prepare("```\n**未閉じ") == "```\n**未閉じ")
        #expect(prepare("~~~\n**未閉じ") == "~~~\n**未閉じ")
    }

    @Test("CRLF は LF へ正規化し、その後の最終段落を補正する")
    func crlfNormalizedThenPrepared() {
        #expect(prepare("説明\r\n**確認\r\n\r\n") == "説明\n**確認**\n\n")
    }

    @Test("正常な Markdown は改行正規化を除いて入力不変")
    func wellFormedMarkdownUnchanged() {
        #expect(prepare("# 見出し") == "# 見出し")
        #expect(prepare("- 項目") == "- 項目")
        #expect(prepare("> 引用") == "> 引用")
        #expect(prepare("[詳細](https://example.com)") == "[詳細](https://example.com)")
        #expect(prepare("| A | B |\n| --- | --- |\n| x | y |") == "| A | B |\n| --- | --- |\n| x | y |")
        #expect(prepare("*斜体*") == "*斜体*")
        #expect(prepare("**太字**") == "**太字**")
    }

    @Test("ストリーミング原入力ごとに結果を作り、同長別内容を取り違えない")
    func progressiveAndSameLengthReplacement() {
        #expect(prepare("**確") == "**確**")
        #expect(prepare("**確認") == "**確認**")
        #expect(prepare("**確認**") == "**確認**")
        #expect(prepare("**更新") == "**更新**")
        #expect("**確認".count == "**更新".count)
        #expect(prepare("**確認") != prepare("**更新"))
    }

    @Test("固定入力は冪等で、呼び出し後も元入力の値は変わらない")
    func prepareIsIdempotentAndDoesNotMutateSource() {
        let sources = [
            "**確認済み**",
            "**確認",
            "**確認\n次行",
            "**確認\n\n次段",
            "`**未閉じ`",
            "```\n**未閉じ",
            "説明\r\n**確認\r\n\r\n",
            "foo_bar",
        ]
        for source in sources {
            let original = source
            let once = prepare(source)
            #expect(source == original)
            #expect(prepare(once) == once)
        }
    }
}

@Suite("task-47: TranscriptMarkdownPresentation summary")
struct AcceptanceTranscriptMarkdownSummaryTests {
    @Test("未閉じ強調は prepare の有限規則で補正してから装飾を除く")
    func summaryStripsPreparedEmphasis() {
        #expect(summary("**確認済み**") == "確認済み")
        #expect(summary("**確認") == "確認")
    }

    @Test("ATX 見出し 1〜6 と装飾除去、最終見出し優先、空なら遡る")
    func atxHeadings() {
        #expect(summary("# 一") == "一")
        #expect(summary("## 二") == "二")
        #expect(summary("### 三") == "三")
        #expect(summary("#### 四") == "四")
        #expect(summary("##### 五") == "五")
        #expect(summary("###### 六") == "六")
        #expect(summary("## **確認結果**") == "確認結果")
        #expect(summary("## 前\n## 後\n本文") == "後")
        #expect(summary("## 有効\n## ") == "有効")
        #expect(summary("## **有効**\n## ~~ ~~") == "有効")
        #expect(summary("本文\n## ") == "本文")
        #expect(summary("## ") == nil)
        #expect(summary("## 確認 ###") == "確認")
        #expect(summary("## C#") == "C#")
        #expect(summary("##tag") == "##tag")
        #expect(summary("####### 見出し外") == "####### 見出し外")
    }

    @Test("見出しが無ければ最後の通常段落の最後の非空文章行")
    func lastParagraphLine() {
        #expect(summary("一行目\n二行目") == "二行目")
    }

    @Test("Setext・箇条書き・番号・引用・表は候補外")
    func excludedBlocks() {
        #expect(summary("タイトル\n====") == nil)
        #expect(summary("残す\n\nタイトル\n----") == "残す")
        #expect(summary("- 項目") == nil)
        #expect(summary("1. 項目") == nil)
        #expect(summary("> 引用") == nil)
        #expect(summary("| A | B |\n| --- | --- |\n| x | y |") == nil)
        #expect(summary("本文\n\n- 項目") == "本文")
        #expect(summary("本文\n\n> 引用") == "本文")
        #expect(summary("## 見出し\n\n| A | B |\n| --- | --- |") == "見出し")
    }

    @Test("複数行インライン装飾とリンク表示名、取り消し線、エスケープ")
    func multilineInlineAndLinks() {
        #expect(summary("**前\n後**") == "後")
        #expect(summary("[前\n後](https://example.com)") == "後")
        #expect(summary("[詳細](\nhttps://example.com)") == "詳細")
        #expect(summary("[詳細](https://example.com/a#b)") == "詳細")
        #expect(summary("~~古い~~") == "古い")
        #expect(summary("`**x** ## y`") == "**x** ## y")
        #expect(summary("``a ` b **c**``") == "a ` b **c**")
        #expect(summary("\\*literal\\*") == "*literal*")
    }

    @Test("コード領域だけの入力は nil、文章があれば文章を残す")
    func codeOnlySummaryIsNil() {
        #expect(summary("```\n## コード\n```") == nil)
        #expect(summary("```\n**未閉じ") == nil)
        #expect(summary("~~~\n## コード\n~~~") == nil)
        #expect(summary("    ## コード") == nil)
        #expect(summary("\t## コード") == nil)
        #expect(summary("文章\n\n```\n## コード\n```") == "文章")
        #expect(summary("") == nil)
        #expect(summary(" \t\n") == nil)
    }

    @Test("60 Character は切り詰めず、61 は 60 文字の後に …。結合文字と家族絵文字は 1 Character")
    func characterLimitSixty() {
        let sixty = FrozenSixty.sixty
        #expect(FrozenSixty.part1.count == 10)
        #expect(FrozenSixty.part2.count == 10)
        #expect(FrozenSixty.part3.count == 10)
        #expect(FrozenSixty.part4.count == 10)
        #expect(FrozenSixty.part5.count == 10)
        #expect(FrozenSixty.part6.count == 10)
        #expect(sixty.count == 60)
        #expect(summary(sixty) == sixty)
        let sixtyOne = sixty + "追"
        #expect(sixtyOne.count == 61)
        #expect(summary(sixtyOne) == sixty + "…")
        #expect(sixty.contains("e\u{301}"))
        #expect(sixty != sixty.precomposedStringWithCanonicalMapping || sixty.contains("\u{301}"))
    }
}

@Suite("task-47: フェンス分割とコード保護")
struct AcceptanceTranscriptMarkdownSplitTests {
    @Test("閉じたバッククォートフェンスは .code へ分割する")
    func splitClosedBacktickFence() {
        expectBlocks(
            "Before\n```json\n{\"ok\": true}\n```\nAfter",
            [
                .markdown("Before"),
                .code(language: "json", text: "{\"ok\": true}"),
                .markdown("After"),
            ]
        )
    }

    @Test("未閉じ3本・字下げなしは既存の言語表記正規化で .markdown へ戻す")
    func splitUnclosedBareFenceStaysMarkdown() {
        expectBlocks(
            "Before\n```json\n{\"ok\": true}",
            [
                .markdown("Before"),
                .markdown("``` json\n{\"ok\": true}"),
            ]
        )
        expectBlocks(
            "```json\n**x\n\n",
            [
                .markdown("``` json\n**x\n\n"),
            ]
        )
    }

    @Test("0空白と3空白フェンスの .code.text は同じリテラルで、字下げと末尾空行を保持する")
    func splitIndentedFencesKeepCodeText() {
        let code = "\t  **x  \n"
        expectBlocks(
            "```swift\n\t  **x  \n\n```",
            [.code(language: "swift", text: code)]
        )
        expectBlocks(
            "   ```swift\n\t  **x  \n\n   ```",
            [.code(language: "swift", text: code)]
        )
        #expect(utf8(code) == utf8("\t  **x  \n"))
    }

    @Test("4空白とタブ字下げはインデントコードとして .markdown に残す")
    func splitFourSpaceAndTabStayMarkdown() {
        expectBlocks(
            "    ```swift\n    **x  \n\n    ```\n\n",
            [.markdown("    ```swift\n    **x  \n\n    ```\n\n")]
        )
        expectBlocks(
            "\t```swift\n\t**x\n\t```\n\n",
            [.markdown("\t```swift\n\t**x\n\t```\n\n")]
        )
    }

    @Test("フェンスの CRLF／単独 CR は LF へ正規化し、コード本文の空行改行は残す")
    func splitNormalizesFenceNewlines() {
        expectBlocks(
            "```swift\r\n\t  x  \r\n\r\n```",
            [.code(language: "swift", text: "\t  x  \n")]
        )
        expectBlocks(
            "```swift\r\t  x  \r\r```",
            [.code(language: "swift", text: "\t  x  \n")]
        )
        expectBlocks(
            "本文\r\n\r\n",
            [.markdown("本文\n\n")]
        )
    }

    @Test("3空白字下げ・4本以上・チルダの未閉じ開始行は 3本へ書き換えない")
    func splitDoesNotRewriteUnclosedOpeners() {
        expectBlocks(
            "   ```json\n  **x\n\n",
            [.markdown("   ```json\n  **x\n\n")]
        )
        expectBlocks(
            "````json\n```\n**x\n\n",
            [.markdown("````json\n```\n**x\n\n")]
        )
        expectBlocks(
            "~~~\n```\n**x\n~~~\n\n",
            [.markdown("~~~\n```\n**x\n~~~\n\n")]
        )
        expectBlocks(
            "~~~\n**x\n\n",
            [.markdown("~~~\n**x\n\n")]
        )
    }

    @Test("長いフェンスは短い終了候補や別文字種では閉じない")
    func splitFenceLengthAndInfoString() {
        expectBlocks(
            "````\na\n```\nb\n````",
            [.code(language: nil, text: "a\n```\nb")]
        )
        expectBlocks(
            "```\na\n~~~\nb\n```",
            [.code(language: nil, text: "a\n~~~\nb")]
        )
        expectBlocks(
            "```\na\n```text\nb\n```",
            [.code(language: nil, text: "a\n```text\nb")]
        )
        expectBlocks(
            "```\na\n````",
            [.code(language: nil, text: "a")]
        )
        expectBlocks(
            "```\na\n    ```\nb\n```",
            [.code(language: nil, text: "a\n    ```\nb")]
        )
    }

    @Test("分割後の未閉じ .markdown を prepare／summary してもコード内部は補正しない")
    func prepareAndSummaryProtectSplitMarkdown() {
        let unclosed = "``` json\n**x\n\n"
        expectBlocks("```json\n**x\n\n", [.markdown(unclosed)])
        #expect(prepare(unclosed) == unclosed)
        #expect(summary(unclosed) == nil)

        let fourSpace = "    ```swift\n    **x  \n\n    ```\n\n"
        #expect(prepare(fourSpace) == fourSpace)
        #expect(summary(fourSpace) == nil)
        #expect(prepare("    **未閉じ") == "    **未閉じ")
        #expect(summary("    ## コード") == nil)
        #expect(prepare("\t**未閉じ") == "\t**未閉じ")
        #expect(summary("\t## コード") == nil)
    }

    @Test("同長別内容を markdownBlocks へ渡しても取り違えない")
    func renderCacheDoesNotConfuseSameLength() {
        let first = "**確認済み**"
        let second = "**確認更新**"
        #expect(first.count == second.count)
        let a = ChatMessageRenderCache.markdownBlocks(first)
        let b = ChatMessageRenderCache.markdownBlocks(second)
        #expect(a != b)
        #expect(a == ChatMarkdownFormatter.splitFencedCodeBlocks(first))
        #expect(b == ChatMarkdownFormatter.splitFencedCodeBlocks(second))
    }
}

@Suite("task-47: 本文色と View 入口")
struct AcceptanceTranscriptMarkdownViewAPITests {
    @Test("AgentMessageBody は text のみと bodyColor 付きを受け、既定は primary")
    func agentMessageBodyColorDefault() {
        let defaulted = AgentMessageBody(text: "回答本文")
        let primary = AgentMessageBody(text: "回答本文", bodyColor: DSColor.chatTextPrimary)
        let secondary = AgentMessageBody(text: "回答本文", bodyColor: DSColor.chatTextSecondary)
        _ = defaulted
        _ = primary
        _ = secondary
    }

    @Test("RichMarkdownView の通常・streaming 両入口は bodyColor を省略できる")
    func richMarkdownViewEntriesAcceptBodyColor() {
        _ = RichMarkdownView("**確認")
        _ = RichMarkdownView("**確認", bodyColor: DSColor.chatTextPrimary)
        _ = RichMarkdownView("**確認", bodyColor: DSColor.chatTextSecondary)
        _ = RichMarkdownView(streaming: "**確認")
        _ = RichMarkdownView(streaming: "**確認", bodyColor: DSColor.chatTextPrimary)
        _ = RichMarkdownView(streaming: "**確認", bodyColor: DSColor.chatTextSecondary)
    }

    @Test("同じ theme ID・倍率でも primary／secondary のキャッシュキーは異なり、同じ役割は同じキー")
    func themeCacheKeySeparatesBodyColorRole() {
        let themeID = "phlox"
        let scale: CGFloat = 1.0
        let primary = RichMarkdownView.themeCacheKey(
            themeID: themeID,
            scale: scale,
            bodyColor: DSColor.chatTextPrimary
        )
        let secondary = RichMarkdownView.themeCacheKey(
            themeID: themeID,
            scale: scale,
            bodyColor: DSColor.chatTextSecondary
        )
        #expect(primary != secondary)
        #expect(
            RichMarkdownView.themeCacheKey(
                themeID: themeID,
                scale: scale,
                bodyColor: DSColor.chatTextPrimary
            ) == primary
        )
        #expect(
            RichMarkdownView.themeCacheKey(
                themeID: themeID,
                scale: scale,
                bodyColor: DSColor.chatTextSecondary
            ) == secondary
        )
    }

    @Test("明暗・倍率を変えても本文色の役割はキーに残り、キー不一致を実描画と読み替えない")
    func themeCacheKeyKeepsRoleAcrossThemeAndScale() {
        let lightPrimary = RichMarkdownView.themeCacheKey(
            themeID: "phlox-light",
            scale: 0.8,
            bodyColor: DSColor.chatTextPrimary
        )
        let lightSecondary = RichMarkdownView.themeCacheKey(
            themeID: "phlox-light",
            scale: 0.8,
            bodyColor: DSColor.chatTextSecondary
        )
        let darkPrimary = RichMarkdownView.themeCacheKey(
            themeID: "dracula",
            scale: 2.0,
            bodyColor: DSColor.chatTextPrimary
        )
        let darkSecondary = RichMarkdownView.themeCacheKey(
            themeID: "dracula",
            scale: 2.0,
            bodyColor: DSColor.chatTextSecondary
        )
        #expect(lightPrimary != lightSecondary)
        #expect(darkPrimary != darkSecondary)
        #expect(lightPrimary != darkPrimary)
        #expect(lightSecondary != darkSecondary)
    }
}
