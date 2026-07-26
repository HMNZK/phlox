import Foundation
import SwiftUI
import Testing
import DesignSystem
import MarkdownUI
@testable import DesignSystemIOS

@Suite("Whitebox: Markdown の可読性（task-2）")
struct MarkdownReadabilityWhiteboxTests {
    @Test("コロン付き区切り行を持つ表を切り出す")
    func extractsTableWithAlignedDelimiter() {
        let table = """
        | 名前 | 値 |
        | :--- | ---: |
        | depth | 3 |
        """

        #expect(MarkdownBlockParser.blocks(from: table) == [.table(table)])
    }

    @Test("データ行が無い表候補は本文のまま保つ")
    func tableCandidateWithoutDataRowStaysProse() {
        let text = """
        | 名前 | 値 |
        | :---: | ---: |
        """

        #expect(MarkdownBlockParser.blocks(from: text) == [.paragraph(text)])
    }

    @Test("空行なしで続く表と前後の本文を順序どおり分離する")
    func extractsTableWithoutBlankLineBeforeIt() {
        let table = """
        | 名前 | 値 |
        | --- | --- |
        | depth | 3 |
        """
        let text = "前置き\n\(table)\n後置き"

        #expect(MarkdownBlockParser.blocks(from: text) == [
            .paragraph("前置き"),
            .table(table),
            .paragraph("後置き"),
        ])
    }

    @Test("セル内のパイプを含むデータ行も表本文として失わない")
    func preservesNestedPipesInTableRows() {
        let table = """
        | 項目 | 値 |
        | --- | --- |
        | コマンド | `a | b` |
        """

        #expect(MarkdownBlockParser.blocks(from: table) == [.table(table)])
    }

    @Test("区切り行が無い複数行のパイプ本文は表にしない")
    func multiLinePipesWithoutDelimiterStayProse() {
        let text = "a | b | c\nd | e | f\ng | h | i"

        #expect(MarkdownBlockParser.blocks(from: text) == [.paragraph(text)])
    }

    @Test("GFM の短い・単一列の区切り行を持つ表を切り出す")
    func extractsTablesWithShortAndSingleColumnDelimiters() {
        let tables = [
            "| a | b |\n| - | - |\n| 1 | 2 |",
            "| a | b |\n| -- | -- |\n| 1 | 2 |",
            "| a | b |\n| :-: | :-: |\n| 1 | 2 |",
            "| a |\n| --- |\n| 1 |",
        ]

        for table in tables {
            #expect(MarkdownBlockParser.blocks(from: table) == [.table(table)])
        }
    }

    @Test("ヘッダと区切り行のセル数が異なる候補は表にしない")
    func mismatchedHeaderAndDelimiterStayProse() {
        let text = "| a | b | c |\n| --- | --- |\n| 1 | 2 | 3 |"

        #expect(MarkdownBlockParser.blocks(from: text) == [.paragraph(text)])
    }

    @Test("ヘッダ行のエスケープされたパイプはセル区切りとして数えない")
    func escapedPipeInHeaderDoesNotBreakTableDetection() {
        let table = "| a \\| b | c |\n| --- | --- |\n| 1 | 2 |"

        #expect(MarkdownBlockParser.blocks(from: table) == [.table(table)])
    }

    @Test("ヘッダのコードスパン内の素のパイプでセル数が不一致なら表にしない")
    func rawPipeInHeaderCodeSpanKeepsMismatchedCandidateAsProse() {
        // GFM table: header と delimiter row のセル数が一致しなければ表ではない。
        // GFM は inline span 内でもパイプをセルに含めるには escape が必要である。
        let text = "| `a|b` | c |\n| --- | --- |\n| 1 | 2 |"

        #expect(MarkdownBlockParser.blocks(from: text) == [.paragraph(text)])
    }

    @Test("パイプのないヘッダ候補は区切り行があっても表にしない")
    func headerWithoutPipeDoesNotBecomeTable() {
        let text = "|a|\n---\n|b|"

        #expect(MarkdownBlockParser.blocks(from: text) == [.paragraph(text)])
    }

    @Test("空の区切りセルを区切り行として認めない")
    func emptyDelimiterCellsDoNotBecomeTable() {
        let text = "| a | b |\n| | |\n| 1 | 2 |"

        #expect(MarkdownBlockParser.blocks(from: text) == [.paragraph(text)])
    }

    @Test("リスト項目内にインデントされた表候補はリスト本文のまま保つ")
    func indentedTableCandidateInsideListStaysProse() {
        let text = "- 項目\n  | a | b |\n  | --- | --- |\n  | 1 | 2 |\n- 次の項目"

        #expect(MarkdownBlockParser.blocks(from: text) == [.paragraph(text)])
    }

    @Test("4 スペースのコードブロック内にある表候補は表にしない")
    func fourSpaceIndentedTableCandidateStaysProse() {
        let text = "    | a | b |\n    | --- | --- |\n    | 1 | 2 |"

        #expect(MarkdownBlockParser.blocks(from: text) == [.paragraph(text)])
    }
}

@Suite("Whitebox: 表の必要幅見積り（task-2）")
struct MarkdownTableWidthEstimatorWhiteboxTests {
    @Test("列数とセル長が増えると必要幅は単調に増える")
    func contentWidthIncreasesWithColumnsAndCellLengths() {
        let oneShortColumn = "| a |\n| - |\n| b |"
        let twoShortColumns = "| a | b |\n| - | - |\n| c | d |"
        let longerCells = "| alphaBetaGamma | deltaEpsilonZeta |\n| - | - |\n| etaThetaIota | kappaLambdaMu |"

        let containerWidth: CGFloat = 100
        let one = MarkdownTableWidthEstimator.contentWidth(for: oneShortColumn, containerWidth: containerWidth)
        let two = MarkdownTableWidthEstimator.contentWidth(for: twoShortColumns, containerWidth: containerWidth)
        let longer = MarkdownTableWidthEstimator.contentWidth(for: longerCells, containerWidth: containerWidth)

        #expect(one < two)
        #expect(two < longer)
    }

    @Test("必要幅は容器幅より小さくならず有限の上限でクランプされる")
    func contentWidthRespectsContainerAndUpperBound() {
        let smallTable = "| a | b |\n| - | - |\n| c | d |"
        let veryLongCell = String(repeating: "w", count: 1_000)
        let wideTable = "| \(veryLongCell) | \(veryLongCell) |\n| - | - |\n| a | b |"

        #expect(MarkdownTableWidthEstimator.contentWidth(for: smallTable, containerWidth: 390) == 390)
        #expect(MarkdownTableWidthEstimator.contentWidth(for: wideTable, containerWidth: 390) == MarkdownTableWidthEstimator.maximumContentWidth)
        #expect(MarkdownTableWidthEstimator.contentWidth(for: wideTable, containerWidth: 5_000) == 5_000)
    }

    @Test("全角文字は半角の2倍幅として見積もる")
    func fullWidthCharactersCountAsTwoUnits() {
        let cjk = "| ああああ |\n| - |\n| あ |"
        let ascii = "| aaaa |\n| - |\n| a |"

        #expect(MarkdownTableWidthEstimator.contentWidth(for: cjk, containerWidth: 0) == 96)
        #expect(MarkdownTableWidthEstimator.contentWidth(for: ascii, containerWidth: 0) == 64)
    }

    @Test("必要幅はヘッダ行ではなく各列の全行の最長セルで決まる")
    func widthFollowsWidestCellIncludingDataRows() {
        let table = "| a |\n| - |\n| aaaaaaaaaaaaaaaaaaaa |"

        #expect(MarkdownTableWidthEstimator.contentWidth(for: table, containerWidth: 0) == 192)
    }

    @Test("区切り行のダッシュ長は必要幅の見積りに含めない")
    func widthIgnoresDelimiterRowLength() {
        let table = "| 名 | 説 |\n| -------------------------------------------------- | - |\n| a | b |"

        #expect(MarkdownTableWidthEstimator.contentWidth(for: table, containerWidth: 0) == 112)
    }

    @Test("区切り行だけを除外すると行が空になっても有限の容器幅を返す")
    func delimiterOnlyInputUsesContainerWidth() {
        #expect(MarkdownTableWidthEstimator.contentWidth(for: "| - |", containerWidth: 390) == 390)
    }
}

@Suite("Whitebox: 表のレイアウト収束（task-2）")
@MainActor
struct MarkdownTableLayoutWhiteboxTests {
    @Test("表ブロックは View 経由でも必要幅で描かれ、狭い容器で縦に潰れない")
    func dsMarkdownTextAppliesEstimatedTableWidth() {
        var lines = [
            "| A | B | C | D | E | F | G | H |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
        ]
        for index in 0..<3 {
            lines.append("| maxAPISpawnDepth\(index) | maxAPISpawnConcurrency\(index) | maxAPISpawnSessionCount\(index) | 値\(index) | 深い spawn チェーンを止める | 連続起動時に本数を絞る | コードから消えている | 制約なし |")
        }

        let height = MarkdownLayoutProbe.fittingHeight(
            DSMarkdownText(lines.joined(separator: "\n")),
            width: 390
        )
        #expect(height < 300, "View は見積り幅を表へ渡すこと。height=\(height)（結線を切ると 1173 になる）")
    }

    @Test("8 列の表は狭い容器でも必要幅で描画され縦に潰れない")
    func wideTableUsesEstimatedContentWidth() {
        let table = """
        | 項目 | 設定名 | 現在値 | 推奨値 | 影響範囲 | 変更理由 | 注意事項 | 詳細説明 |
        | --- | --- | --- | --- | --- | --- | --- | --- |
        | API | maxAPISpawnDepth | 3 | 5 | すべての子エージェント | 深い spawn チェーンを止める | 負荷が高い場合は下げる | 並列実行時に十分な余裕を持たせるための説明 |
        | API | maxAPISpawnConcurrency | 5 | 8 | セッション全体 | 連続起動を抑制する | 外部サービスの上限に注意 | 1 秒あたりの本数を絞りながら処理を継続する説明 |
        """
        let containerWidth: CGFloat = 390
        let contentWidth = MarkdownTableWidthEstimator.contentWidth(
            for: table,
            containerWidth: containerWidth
        )
        let narrowHeight = MarkdownTableLayoutProbe.height(of: table, width: containerWidth)
        let expandedHeight = MarkdownTableLayoutProbe.height(of: table, width: contentWidth)

        #expect(contentWidth > containerWidth, "8 列の表には容器幅を超える有限幅を与えること。width=\(contentWidth)")
        #expect(expandedHeight < narrowHeight, "必要幅では列が圧縮されず、狭幅時より高さが小さくなること。narrow=\(narrowHeight) expanded=\(expandedHeight)")
        #expect(expandedHeight < 300, "表は必要幅へ伸ばし、狭い容器で縦に潰れないこと。height=\(expandedHeight)")
    }

    @Test("外側の縦スクロールと同じ幅固定・高さ未指定の提案で表が収束する")
    func tableLayoutConvergesWithBoundedWidthProposal() {
        let table = """
        | 制限 | 値 | 説明 |
        | --- | --- | --- |
        | maxAPISpawnDepth | 3 | 深い spawn チェーンを止めるための十分に長い説明文 |
        | maxAPISpawnConcurrency | 5 | 連続起動時に 1 秒あたりの本数を絞るための十分に長い説明文 |
        """
        let sink = LayoutSizeSink()
        let renderer = ImageRenderer(
            content: MarkdownProposalProbe(width: 390, sink: { sink.size = $0 }) {
                DSMarkdownText(table)
            }
        )
        let startedAt = ContinuousClock.now

        renderer.render { _, _ in }

        let elapsed = startedAt.duration(to: .now)
        #expect(sink.size.width == 390, "外側の幅制約を保ったままレイアウトすること。size=\(sink.size)")
        #expect(sink.size.height > 0, "表を含む本文が有限の高さを返すこと。size=\(sink.size)")
        #expect(elapsed < .milliseconds(500), "表の測定は数百 ms 以内に収束すること。elapsed=\(elapsed)")
    }
}

private final class LayoutSizeSink: @unchecked Sendable {
    var size = CGSize.zero
}

/// 外側の縦 ScrollView が子へ渡す「幅固定・高さ未指定」の提案を再現する。
private struct MarkdownProposalProbe: Layout {
    let width: CGFloat
    let sink: @Sendable (CGSize) -> Void

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let size = subviews[0].sizeThatFits(ProposedViewSize(width: width, height: nil))
        sink(size)
        return size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {}
}

@MainActor
private enum MarkdownTableLayoutProbe {
    static func height(of markdown: String, width: CGFloat) -> CGFloat {
        let renderer = ImageRenderer(
            content: Markdown(markdown)
                .font(DSFont.body)
                .frame(width: width, alignment: .leading)
        )
        var size = CGSize.zero
        renderer.render { renderedSize, _ in size = renderedSize }
        return size.height
    }
}
