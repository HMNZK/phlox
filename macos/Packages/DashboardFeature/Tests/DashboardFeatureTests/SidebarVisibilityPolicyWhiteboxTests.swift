import Testing
@testable import DashboardFeature

@Suite("SidebarVisibilityPolicy whitebox")
struct SidebarVisibilityPolicyWhiteboxTests {

    @Test
    func gridPreservesCurrentVisibility() {
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .grid, currentVisible: true, hasGridFilter: false) == true)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .grid, currentVisible: false, hasGridFilter: false) == false)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .grid, currentVisible: true, hasGridFilter: true) == true)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .grid, currentVisible: false, hasGridFilter: true) == false)
    }

    @Test
    func singleAndTeamForceOpen() {
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .single, currentVisible: false, hasGridFilter: false) == true)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .team, currentVisible: false, hasGridFilter: true) == true)
    }
}
