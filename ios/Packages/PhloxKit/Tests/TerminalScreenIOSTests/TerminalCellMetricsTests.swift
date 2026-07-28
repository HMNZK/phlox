import Foundation
import Testing
@testable import TerminalScreenIOS

@MainActor
@Suite("端末の桁と、それに揃えるための字送り")
struct TerminalCellMetricsTests {

    private let fontSize: CGFloat = 12

    private var cellWidth: CGFloat {
        TerminalScreenView.cellWidth(fontSize: fontSize)
    }

    // MARK: - 桁数（端末側の格子と一致すること）

    @Test("半角は1桁")
    func halfWidthCharactersTakeOneColumn() {
        #expect(TerminalCellMetrics.columns(of: "W") == 1)
        #expect(TerminalCellMetrics.columns(of: " ") == 1)
        #expect(TerminalCellMetrics.columns(of: "$") == 1)
    }

    @Test("全角は2桁")
    func fullWidthCharactersTakeTwoColumns() {
        #expect(TerminalCellMetrics.columns(of: "あ") == 2)
        #expect(TerminalCellMetrics.columns(of: "漢") == 2)
        #expect(TerminalCellMetrics.columns(of: "（") == 2)
        #expect(TerminalCellMetrics.columns(of: "－") == 2)
    }

    @Test("罫線・記号は1桁（端末は曖昧幅を半角として扱う）")
    func boxDrawingCharactersTakeOneColumn() {
        #expect(TerminalCellMetrics.columns(of: "│") == 1)
        #expect(TerminalCellMetrics.columns(of: "─") == 1)
        #expect(TerminalCellMetrics.columns(of: "┼") == 1)
        #expect(TerminalCellMetrics.columns(of: "→") == 1)
        #expect(TerminalCellMetrics.columns(of: "❯") == 1)
    }

    // MARK: - 描き方（桁数ちょうどの幅になること）

    /// この不変条件が崩れると表・罫線が桁ごとずれる（→ ADR 0040）。
    @Test("どの文字も、倍率と字送りを当てると桁数ちょうどの幅になる")
    func layoutMakesEveryCharacterFitItsColumns() {
        for character in ["W", " ", "あ", "（", "│", "─", "→", "漢", "$", "－", "⏺", "✳"] as [Character] {
            let layout = TerminalCellMetrics.layout(of: character, fontSize: fontSize, cellWidth: cellWidth)
            let drawn = TerminalCellMetrics.advance(of: character, fontSize: fontSize * layout.scale)
            let expected = CGFloat(TerminalCellMetrics.columns(of: character)) * cellWidth

            #expect(
                abs(drawn + layout.kerning - expected) < 0.01,
                "\(character): 描画幅 \(drawn) + 字送り \(layout.kerning) が \(expected) にならない"
            )
        }
    }

    /// 字送りが負になると、その文字が次の文字へ重なる（ユーザー報告:「文字が重なっている」）。
    @Test("字送りは決して負にならない（重なりを作らない）")
    func kerningIsNeverNegative() {
        for character in ["W", "あ", "（", "│", "⏺", "✳", "→", "🙂"] as [Character] {
            let layout = TerminalCellMetrics.layout(of: character, fontSize: fontSize, cellWidth: cellWidth)

            #expect(layout.kerning >= 0, "\(character): 字送りが負（\(layout.kerning)）")
        }
    }

    @Test("半角は等幅フォントのままなので、縮めも字送りも要らない")
    func halfWidthCharactersAreDrawnAsIs() {
        let layout = TerminalCellMetrics.layout(of: "W", fontSize: fontSize, cellWidth: cellWidth)

        #expect(layout.scale == 1)
        #expect(abs(layout.kerning) < 0.001)
    }

    /// 全角が 2 桁ぶんの幅で描かれないことが、桁ずれの直接の原因だった。
    @Test("桁数より狭い全角は、縮めずに字送りで送る")
    func narrowFullWidthCharactersAreKernedNotScaled() {
        let advance = TerminalCellMetrics.advance(of: "あ", fontSize: fontSize)
        let layout = TerminalCellMetrics.layout(of: "あ", fontSize: fontSize, cellWidth: cellWidth)

        #expect(advance < 2 * cellWidth, "前提: 全角が2桁ぶん描かれていないこと（実幅 \(advance)）")
        #expect(layout.scale == 1)
        #expect(layout.kerning > 0)
    }

    /// `⏺` は 1 桁の枠に 2 桁ぶん描かれる。縮めないと次の文字へ重なる。
    @Test("桁数より広い文字は縮めて枠に収める")
    func wideGlyphsAreScaledDownToFit() {
        let advance = TerminalCellMetrics.advance(of: "⏺", fontSize: fontSize)
        let layout = TerminalCellMetrics.layout(of: "⏺", fontSize: fontSize, cellWidth: cellWidth)

        #expect(advance > cellWidth, "前提: 1桁より広く描かれていること（実幅 \(advance)）")
        #expect(layout.scale < 1)
        #expect(layout.kerning == 0)
    }

    @Test("同じ文字を測り直しても同じ値を返す（キャッシュが値を変えない）")
    func repeatedMeasurementIsStable() {
        let first = TerminalCellMetrics.advance(of: "漢", fontSize: fontSize)
        let second = TerminalCellMetrics.advance(of: "漢", fontSize: fontSize)

        #expect(first == second)
    }
}
