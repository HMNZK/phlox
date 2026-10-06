import Foundation
import Testing
import PhloxCore
@testable import Features

// 概要（overview）タブは廃止済み。タブ選択と、注入した overview インスタンス保持の契約を検証する。
@MainActor
@Suite("App shell view model") struct AppShellViewModelTests {
    @Test func tabsAreSessionsSettingsUsageInOrder() {
        #expect(AppTab.allCases == [.sessions, .settings, .usage])
    }

    @Test func selectingTabChangesSelectedTab() {
        let vm = AppShellViewModel(
            selectedTab: .sessions,
            overview: SessionsOverviewViewModel(sessions: [makeSession(id: "s1")])
        )

        vm.selectTab(.settings)
        #expect(vm.selectedTab == .settings)

        vm.selectTab(.usage)
        #expect(vm.selectedTab == .usage)
    }

    @Test func selectingCurrentNonOverviewTabDoesNotChangeOverviewMode() {
        let overview = SessionsOverviewViewModel(sessions: [makeSession(id: "s1")])
        let shell = AppShellViewModel(selectedTab: .settings, overview: overview)

        shell.selectTab(.settings)
        shell.selectTab(.usage)
        shell.selectTab(.usage)

        #expect(shell.selectedTab == .usage)
        #expect(overview.mode == .grid)
    }

    @Test func shellRetainsTheInjectedOverviewInstanceAndItsSelection() {
        let overview = SessionsOverviewViewModel(
            sessions: [makeSession(id: "s1"), makeSession(id: "s2")]
        )
        overview.selectSession(id: "s2")

        let shell = AppShellViewModel(overview: overview)
        shell.selectTab(.settings)

        #expect(shell.overview === overview)
        #expect(shell.overview.singleSession?.id == "s2")
    }

    private func makeSession(id: String) -> Session {
        Session(
            id: id,
            name: id,
            agent: .claudeCode,
            status: .idle,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
