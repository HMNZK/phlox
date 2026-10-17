import Testing
@testable import Features

@MainActor
@Suite("App shell view model") struct AppShellViewModelTests {
    @Test func tabsAreSessionsAndSettingsInOrder() {
        #expect(AppTab.allCases == [.sessions, .settings])
    }

    @Test func selectingTabChangesSelectedTab() {
        let vm = AppShellViewModel(selectedTab: .sessions)

        vm.selectTab(.settings)
        #expect(vm.selectedTab == .settings)

        vm.selectTab(.sessions)
        #expect(vm.selectedTab == .sessions)
    }
}
