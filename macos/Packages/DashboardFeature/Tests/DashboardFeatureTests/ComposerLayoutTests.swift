import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-5 白箱テスト — `ComposerLayout.maxWidth` の数式・境界の回帰ガード。
/// 2026-09-26 ユーザー決定で「90%・上限 760」から「80%・上限なし」へ。
@Suite("ComposerLayout whitebox")
struct ComposerLayoutTests {

    @Test
    func oldBoundaryIsEightyPercent() throws {
        // 旧境界（800 / 0.6 ≈ 1333.333…）でも同じ割合。
        let column = 800 / 0.6
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: column))
        #expect(abs(w - column * 0.8) < 0.001)
    }

    @Test
    func epsilonBelowOldBoundaryIsEightyPercent() throws {
        let column = (800 / 0.6) - 1
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: column))
        #expect(abs(w - column * 0.8) < 0.001)
    }

    @Test
    func veryWideColumnHasNoCap() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 10_000))
        #expect(abs(w - 8_000) < 0.001)
    }

    @Test
    func narrowColumnIs80PercentOfWidth() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 500))
        #expect(abs(w - 400) < 0.001)
    }
}
