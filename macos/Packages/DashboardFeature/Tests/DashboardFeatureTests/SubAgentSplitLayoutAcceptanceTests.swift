import Testing
import CoreGraphics
@testable import DashboardFeature
@testable import SessionFeature

/// task-2（Bug2/3/4）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// シングルビューのサブエージェント横並び分割で、右ペイン幅を決める純関数
/// `SubAgentSplitLayout.paneWidth(fraction:availableWidth:)` のクランプ契約を固定する。
/// レイアウト骨格・ドラッグ・ヘッダー整列・CPU 収束は runtime 検証（swift test では捕捉不可）。
@Suite("SubAgent split layout acceptance")
struct SubAgentSplitLayoutAcceptanceTests {

    @Test
    func defaultFractionWithinBounds() {
        // 既定 0.42・十分広いウィンドウ → 比率どおり。
        let w = SubAgentSplitLayout.paneWidth(fraction: 0.42, availableWidth: 1000)
        #expect(abs(w - 420) < 0.5)
    }

    @Test
    func clampsToLowerBound320() {
        // 比率が小さくても下限 320pt を割らない。
        let w = SubAgentSplitLayout.paneWidth(fraction: 0.1, availableWidth: 1000)
        #expect(abs(w - 320) < 0.5)
    }

    @Test
    func clampsToUpperBound60Percent() {
        // 比率が大きくてもウィンドウ幅の 60% を超えない。
        let w = SubAgentSplitLayout.paneWidth(fraction: 0.95, availableWidth: 1000)
        #expect(abs(w - 600) < 0.5)
    }

    @Test
    func tinyWindowDoesNotExceedUpperBound() {
        // 下限 320 と上限 60% が衝突する狭いウィンドウでは、上限（60%）を優先し
        // それを超えない（メイン側が消滅しない）。
        let w = SubAgentSplitLayout.paneWidth(fraction: 0.42, availableWidth: 400)
        #expect(w <= 400 * 0.6 + 0.5)
        #expect(w > 0)
    }
}
