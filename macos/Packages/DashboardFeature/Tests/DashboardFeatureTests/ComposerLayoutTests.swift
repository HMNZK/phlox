import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// `ComposerLayout.maxWidth` の数式・境界。composer 幅は親から演繹された幅のみを入力とする純関数で、
/// 計測→@State→レイアウトの往復を持たない（自励発振の再発防止）。
/// 2026-09-26 ユーザー決定: 「90%・上限 760」から「80%・上限なし」へ。
@Suite("ComposerLayout")
struct ComposerLayoutTests {

    @Test
    func zeroWidthFallsBackToNil() {
        // 初回フレーム（幅未確定）は制約なし。
        #expect(ComposerLayout.maxWidth(mainColumnWidth: 0) == nil)
    }

    @Test
    func negativeWidthFallsBackToNil() {
        // 演繹式のクランプ前提が崩れても破綻しない。
        #expect(ComposerLayout.maxWidth(mainColumnWidth: -50) == nil)
    }

    @Test
    func narrowColumnIs80PercentOfWidth() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 500))
        #expect(abs(w - 400) < 0.001)
    }

    @Test
    func veryWideColumnHasNoCap() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 10_000))
        #expect(abs(w - 8_000) < 0.001)
    }

    @Test
    func oldBoundaryHasNoJump() throws {
        // 旧境界（約 1333）の前後でも同じ割合: 親を広げた際の急減が無い。
        let below = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1332))
        let above = try #require(ComposerLayout.maxWidth(mainColumnWidth: 1334))
        #expect(abs(below - 1065.6) < 0.001)
        #expect(abs(above - 1067.2) < 0.001)
    }
}
