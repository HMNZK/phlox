import CoreGraphics
import Foundation
import Testing
@testable import TerminalScreenIOS

@Suite("Mac の端末画面をモバイル幅へ収める計算")
struct TerminalScreenMetricsTests {

    // MARK: - フォントサイズ

    @Test("Mac の桁数がそのまま収まるならフォントは縮めない")
    func keepsPreferredSizeWhenContentAlreadyFits() {
        let size = TerminalScreenMetrics.fittingFontSize(
            columns: 40,
            availableWidth: 360,
            preferredFontSize: 12,
            cellWidthAtPreferredSize: 7
        )

        #expect(size == 12)
    }

    @Test("Mac の桁数がはみ出すときは、収まるところまでフォントを縮める")
    func shrinksUntilMacColumnsFit() {
        let size = TerminalScreenMetrics.fittingFontSize(
            columns: 80,
            availableWidth: 360,
            preferredFontSize: 12,
            cellWidthAtPreferredSize: 7
        )

        #expect(size < 12)
        // 縮めた比率でセル幅も縮む前提なので、その幅で 80 桁が収まること。
        let shrunkCellWidth = 7 * (size / 12)
        #expect(80 * shrunkCellWidth <= 360.001)
    }

    @Test("読める下限より小さくはしない（そこから先は折り返して読ませる）")
    func neverShrinksBelowTheReadableFloor() {
        let size = TerminalScreenMetrics.fittingFontSize(
            columns: 400,
            availableWidth: 360,
            preferredFontSize: 12,
            cellWidthAtPreferredSize: 7
        )

        #expect(size == TerminalScreenMetrics.minimumFontSize)
    }

    @Test("桁数が分からないときは既定のフォントで描く")
    func unknownColumnCountFallsBackToPreferredSize() {
        let size = TerminalScreenMetrics.fittingFontSize(
            columns: 0,
            availableWidth: 360,
            preferredFontSize: 12,
            cellWidthAtPreferredSize: 7
        )

        #expect(size == 12)
    }

    // MARK: - 桁数

    @Test("桁数は与えられた幅に収まる数（はみ出さない＝横スクロールが要らない）")
    func columnsNeverOverflowTheAvailableWidth() {
        let columns = TerminalScreenMetrics.columns(availableWidth: 360, cellWidth: 7)

        #expect(columns == 51)
        #expect(CGFloat(columns) * 7 <= 360)
    }

    @Test("極端に狭くても最低桁数は確保する（1文字ずつ折り返させない）")
    func narrowWidthStillKeepsMinimumColumns() {
        let columns = TerminalScreenMetrics.columns(availableWidth: 40, cellWidth: 7)

        #expect(columns == TerminalScreenMetrics.minimumColumns)
    }

    // MARK: - 行数

    @Test("桁に収まる行はそのまま1行")
    func shortLinesOccupyOneRowEach() {
        #expect(TerminalScreenMetrics.wrappedRowCount(plainText: "one\ntwo", columns: 20) == 2)
    }

    @Test("桁を超えた行は折り返した回数ぶん行を使う")
    func longLinesWrapIntoMultipleRows() {
        let line = String(repeating: "x", count: 45)

        #expect(TerminalScreenMetrics.wrappedRowCount(plainText: line, columns: 20) == 3)
    }

    @Test("空の本文でも1行分は確保する")
    func emptyTextStillOccupiesOneRow() {
        #expect(TerminalScreenMetrics.wrappedRowCount(plainText: "", columns: 20) == 1)
    }

    @Test("空行も1行として数える（詰めると以降の行がずれる）")
    func blankLinesStillCountAsRows() {
        #expect(TerminalScreenMetrics.wrappedRowCount(plainText: "a\n\nb", columns: 20) == 3)
    }

    // MARK: - 表示幅

    @Test("全角は2桁を占めるので、半角より早く折り返す")
    func fullWidthCharactersTakeTwoColumns() {
        #expect(TerminalScreenMetrics.displayWidth(of: "あいう") == 6)
        #expect(TerminalScreenMetrics.wrappedRowCount(plainText: String(repeating: "あ", count: 11), columns: 20) == 2)
    }

    @Test("罫線などの半角記号は1桁のまま（TUI の枠が余計に折り返さない）")
    func boxDrawingCharactersStayOneColumn() {
        #expect(TerminalScreenMetrics.displayWidth(of: "│─┌┐") == 4)
    }
}
