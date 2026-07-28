import Foundation
import SwiftUI
import Testing
@testable import DesignSystemIOS

// task-2 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-2.md
// 目的:
//   B-1 段落・見出しが「…」で切れず、折り返して全文表示される。
//   B-2 表がセルを切り詰めず、横スクロール（スライド）で全列を読める。
//   B-3 コードブロックの長い行が横スクロールで全文読める。
//   B-4 ADR 0045 の一線を守る（MarkdownUI の表テーマへ fixedSize を持ち込まない）。

// MARK: - B-1 段落・見出しの折り返し

@Suite("Acceptance: チャット本文が「…」で切れず折り返す（task-2）")
@MainActor
struct MarkdownWrappingAcceptanceTests {

    /// 折り返しが要る幅と要らない幅で高さを比べるための本文。
    /// 段落 → 見出し → 段落の順に置き、段落と見出しの双方で縦サイズが確保されることを見る。
    private static let body = """
    phlox-cli スキルの記述が古いままでした。実コードに残っている制限は maxAPISpawnDepth と \
    maxAPISpawnConcurrency の2つだけで、maxAPISpawnSessionCount はコードから消えています。\
    したがって本数上限は制約なしなので不要という結論になります。

    ## 決めごとは片付きました

    既存の phlox-resume-after-reset.sh への追加として、予約の形はこうなります。
    """

    @Test("段落と見出し1〜6のテーマで折り返し行の高さを確保する（macOS ADR 0118 の移植）")
    func themeReservesWrappedHeightForParagraphAndHeadings() throws {
        let source = try MarkdownLayoutProbe.sourceText("Markdown/DSMarkdownText.swift")
        let fixedSizeCount = source.components(separatedBy: "fixedSize").count - 1

        #expect(source.contains(".paragraph {"), "段落テーマで縦サイズを確保すること")
        #expect(source.contains(".heading1 {"), "見出し1のテーマで縦サイズを確保すること")
        #expect(source.contains(".heading2 {"), "見出し2のテーマで縦サイズを確保すること")
        #expect(source.contains(".heading3 {"), "見出し3のテーマで縦サイズを確保すること")
        #expect(source.contains(".heading4 {"), "見出し4のテーマで縦サイズを確保すること")
        #expect(source.contains(".heading5 {"), "見出し5のテーマで縦サイズを確保すること")
        #expect(source.contains(".heading6 {"), "見出し6のテーマで縦サイズを確保すること")
        #expect(
            fixedSizeCount >= 8,
            """
            listItem に加えて段落・見出し1〜6 の各テーマフックへ
            .fixedSize(horizontal: false, vertical: true) を適用すること
            （MarkdownUI の空テーマは段落・見出しの label に縦サイズを確保せず、
            折り返しても1行高のままになって「…」で切り詰まる）。count=\(fixedSizeCount)
            """
        )
    }

    @Test("狭い幅では折り返した全行分の高さが確保される（1行分に潰れない）")
    func narrowWidthReservesWrappedHeight() {
        let wideHeight = MarkdownLayoutProbe.fittingHeight(DSMarkdownText(Self.body), width: 1400)
        let narrowHeight = MarkdownLayoutProbe.fittingHeight(DSMarkdownText(Self.body), width: 360)

        #expect(
            narrowHeight >= wideHeight + 14,
            """
            狭い幅では段落・見出しが折り返し、折り返した全行分の高さが親へ返ること。
            注（PM 実測）: このプローブは修正前でも green になる＝検出力が弱い。退行の粗い網として
            残すもので、B-1 の主たる凍結は上の themeReservesWrappedHeightForParagraphAndHeadings。
            wide=\(wideHeight) narrow=\(narrowHeight)
            """
        )
    }
}

// MARK: - B-2 表の横スクロール

@Suite("Acceptance: 表を切り詰めず横スクロールで読める（task-2）")
struct MarkdownTableAcceptanceTests {

    private static let table = """
    | 制限 | 値 | 影響 |
    | --- | --- | --- |
    | maxAPISpawnDepth | 3 | 深い spawn チェーンを止める |
    | maxAPISpawnConcurrency | 5 | 連続起動時に1秒あたりの本数を絞る |
    """

    private func tableContents(_ blocks: [MarkdownBlock]) -> [String] {
        blocks.compactMap { block in
            guard case let .table(markdown) = block else { return nil }
            return markdown
        }
    }

    private func paragraphContents(_ blocks: [MarkdownBlock]) -> [String] {
        blocks.compactMap { block in
            guard case let .paragraph(markdown) = block else { return nil }
            return markdown
        }
    }

    @Test("本文中の表を独立ブロックとして切り出す")
    func extractsTableAsItsOwnBlock() throws {
        let text = "実コードに残っているのは2つだけです。\n\n\(Self.table)\n\nmaxAPISpawnSessionCount は消えています。"

        let blocks = MarkdownBlockParser.blocks(from: text)

        let tables = tableContents(blocks)
        #expect(tables.count == 1, "表は1つの table ブロックとして切り出されること。blocks=\(blocks)")
        let table = try #require(tables.first)
        #expect(table.contains("| 制限 | 値 | 影響 |"), "ヘッダ行を保つこと")
        #expect(table.contains("| maxAPISpawnConcurrency | 5 | 連続起動時に1秒あたりの本数を絞る |"), "最終行を保つこと")
    }

    @Test("表を切り出しても前後の本文が失われない")
    func keepsSurroundingProseIntact() {
        let text = "実コードに残っているのは2つだけです。\n\n\(Self.table)\n\nmaxAPISpawnSessionCount は消えています。"

        let blocks = MarkdownBlockParser.blocks(from: text)

        let prose = paragraphContents(blocks).joined(separator: "\n")
        #expect(prose.contains("実コードに残っているのは2つだけです。"))
        #expect(prose.contains("maxAPISpawnSessionCount は消えています。"))
    }

    @Test("本文末尾で終わる表も切り出せる")
    func extractsTableAtEndOfBody() {
        let blocks = MarkdownBlockParser.blocks(from: "決めごとは片付きました\n\n\(Self.table)")

        #expect(tableContents(blocks).count == 1, "blocks=\(blocks)")
    }

    @Test("区切り行が無いパイプ行は表として扱わない")
    func pipesWithoutDelimiterRowStayProse() {
        let blocks = MarkdownBlockParser.blocks(from: "a | b | c")

        #expect(blocks == [.paragraph("a | b | c")])
    }

    @Test("コードフェンス内の表はコードブロックのまま扱う")
    func tableInsideFenceStaysCode() {
        let text = "```\n| a | b |\n| --- | --- |\n| 1 | 2 |\n```"

        let blocks = MarkdownBlockParser.blocks(from: text)

        #expect(blocks == [.code(language: nil, content: "| a | b |\n| --- | --- |\n| 1 | 2 |")])
    }

    @Test("表は横スクロールで提供すると宣言し、実装が伴っている")
    func tableIsProvidedWithHorizontalScroll() throws {
        let source = try MarkdownLayoutProbe.sourceText("Markdown/DSMarkdownText.swift")

        #expect(
            DSMarkdownText.providesTableHorizontalScroll,
            "実装と同時にフラグを反転すること（フラグだけの反転は虚偽報告として扱う）"
        )
        #expect(
            source.contains("ScrollView(.horizontal"),
            "表ブロックを横スクロールで描画すること（セルの切り詰めを起こさない）"
        )
    }

    @Test("MarkdownUI の表テーマへ手を入れない（ADR 0045 の表レイアウト非収束の再発防止）")
    func doesNotTouchMarkdownUITableTheme() throws {
        let source = try MarkdownLayoutProbe.sourceText("Markdown/DSMarkdownText.swift")

        #expect(
            !source.contains(".table {"),
            ".table テーマフックへ手を入れないこと（表の可読性はブロック切り出し＋横スクロールで達成する）"
        )
        #expect(
            !source.contains(".tableCell {"),
            ".tableCell テーマフックへ手を入れないこと（ADR 0045: 表レイアウト非収束→CPU 100% 固着の再発防止）"
        )
    }
}

// MARK: - B-3 コードブロックの横スクロール

@Suite("Acceptance: コードブロックの長い行が読める（task-2）")
@MainActor
struct CodeBlockAcceptanceTests {

    @Test("長い1行のコードは折り返さず横スクロールに載る（狭幅でも高さが増えない）")
    func longSingleLineDoesNotWrap() {
        let longLine = "commit c896cf0  refactor(spawn): " + String(repeating: "x", count: 240)
        let shortHeight = MarkdownLayoutProbe.fittingHeight(
            DSCodeBlock(language: "text", code: "commit c896cf0"),
            width: 320
        )
        let longHeight = MarkdownLayoutProbe.fittingHeight(
            DSCodeBlock(language: "text", code: longLine),
            width: 320
        )

        #expect(
            longHeight == shortHeight,
            """
            長い1行は折り返さず横スクロールで読ませること（折り返して高さが増えるなら
            桁揃えが壊れている）。short=\(shortHeight) long=\(longHeight)
            """
        )
    }

    @Test("コードは横スクロールで提供され続ける")
    func codeStaysHorizontallyScrollable() throws {
        let source = try MarkdownLayoutProbe.sourceText("Markdown/DSCodeBlock.swift")

        #expect(
            source.contains("ScrollView(.horizontal"),
            "コードは横スクロールで提供すること（折り返して桁揃えを壊さない）"
        )
    }
}

// MARK: - ハーネス

enum MarkdownLayoutProbe {
    /// 指定幅でレイアウトを確定させたときの高さ。`ImageRenderer` は macOS ホスト上での
    /// 相対比較用プローブであり、iOS 実機のレイアウトと同一ではない。
    @MainActor
    static func fittingHeight(_ view: some View, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(content: view.frame(width: width))
        var size = CGSize.zero
        renderer.render { renderedSize, _ in size = renderedSize }
        return size.height
    }

    /// テストファイル位置を起点に DesignSystemIOS のソースを読む。
    static func sourceText(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/DesignSystemIOSTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // PhloxKit
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/DesignSystemIOS/\(relativePath)"),
            encoding: .utf8
        )
    }
}
