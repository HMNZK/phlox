import Foundation
import Testing
@testable import DashboardFeature

@Test func sidebarTitleShimmerWaitsOneSecondAfterSweepingRight() {
    func phase(_ seconds: TimeInterval) -> Double {
        SidebarTitleShimmer.phase(at: Date(timeIntervalSinceReferenceDate: seconds))
    }

    #expect(abs(phase(0.7) - 0.5) < 0.0001)
    #expect(phase(1.4) == 1)
    #expect(phase(2.39) == 1)
    #expect(abs(phase(2.4)) < 0.0001)
}
