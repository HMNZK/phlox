import Testing
import CoreGraphics
@testable import DashboardFeature

@Suite("TopBarInsetPolicy whitebox (task-2)")
struct TopBarInsetPolicyTests {
    @Test func 下限境界の直前は32を維持する() {
        // ceil(23.999) + 8 = 32
        #expect(TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: 23.999) == 32)
    }

    @Test func 下限境界の直後は33になる() {
        // ceil(24.001) + 8 = 33
        #expect(TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: 24.001) == 33)
    }

    @Test func 負の計測値でも下限32を維持する() {
        #expect(TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: -10) == 32)
    }

    @Test func 大きな計測値は切り上げと余裕8を反映する() {
        // ceil(100.2) + 8 = 109
        #expect(TopBarInsetPolicy.contentTopInset(measuredOverlayHeight: 100.2) == 109)
    }
}
