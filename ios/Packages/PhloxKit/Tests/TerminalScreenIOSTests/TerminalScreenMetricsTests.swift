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
}
