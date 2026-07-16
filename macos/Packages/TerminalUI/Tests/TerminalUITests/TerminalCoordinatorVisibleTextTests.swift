import Testing
import Foundation
@testable import TerminalUI

@MainActor
struct TerminalCoordinatorVisibleTextTests {
    @Test
    func visibleText_afterFeed_containsWrittenText() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("Hello".utf8))
        #expect(coordinator.visibleText().contains("Hello"))
    }

    @Test
    func visibleText_onFreshCoordinator_isEmpty() {
        let coordinator = TerminalCoordinator()
        #expect(coordinator.visibleText() == "")
    }
}
