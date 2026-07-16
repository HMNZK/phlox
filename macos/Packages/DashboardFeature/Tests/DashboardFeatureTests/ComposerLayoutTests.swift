import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-5 白箱テスト — `ComposerLayout.maxWidth` の数式・境界の回帰ガード。
@Suite("ComposerLayout whitebox")
struct ComposerLayoutTests {

    @Test
    func boundaryAtExactly800SixtyPercent() throws {
        // 60% がちょうど 800 になる幅: 800 / 0.6 ≈ 1333.333…
        let column = 800 / 0.6
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: column))
        #expect(abs(w - 800) < 0.001)
    }

    @Test
    func epsilonBelowBoundaryUses90Percent() throws {
        let column = (800 / 0.6) - 1
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: column))
        #expect(abs(w - column * 0.9) < 0.001)
    }

    @Test
    func veryWideColumnStillCapsAt800() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 10_000))
        #expect(abs(w - 800) < 0.001)
    }

    @Test
    func narrowColumnIs90PercentOfWidth() throws {
        let w = try #require(ComposerLayout.maxWidth(mainColumnWidth: 500))
        #expect(abs(w - 450) < 0.001)
    }
}
