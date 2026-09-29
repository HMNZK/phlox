import AgentDomain
import Testing
@testable import DashboardFeature

@Test func leavingPreviousSessionDoesNotCloseCurrentHoverCard() {
    let first = SessionID()
    let second = SessionID()
    let third = SessionID()
    var selection = SidebarHoverCardSelection()

    selection.show(first)
    selection.show(second)
    selection.show(third)
    selection.hide(first)
    selection.hide(second)
    #expect(selection.sessionID == third)

    selection.hide(third)
    #expect(selection.sessionID == nil)
}
