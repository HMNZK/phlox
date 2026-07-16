// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — トップバーオーバーレイの実測高から本文上余白を確保する。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Testing
import CoreGraphics
@testable import DashboardFeature

@Suite("TopBarInsetPolicy acceptance (task-2)")
struct AcceptanceTopBarInsetTests {
    // contentTopInset = max(32, ceil(measuredOverlayHeight) + 8)

    @Test func 未計測ゼロでは従来の固定32を維持する() {
        #expect(TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: 0) == 32)
    }

    @Test func 低いオーバーレイでは下限32を維持する() {
        // ceil(24) + 8 = 32
        #expect(TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: 24) == 32)
    }

    @Test func 従来値ちょうどのオーバーレイには余裕8を足す() {
        // ceil(32) + 8 = 40
        #expect(TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: 32) == 40)
    }

    @Test func 二段メーター相当の高さでは実測基準になる() {
        // ceil(44) + 8 = 52
        #expect(TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: 44) == 52)
    }

    @Test func 端数は切り上げてから余裕を足す() {
        // ceil(43.4) = 44 → 52
        #expect(TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: 43.4) == 52)
    }
}
