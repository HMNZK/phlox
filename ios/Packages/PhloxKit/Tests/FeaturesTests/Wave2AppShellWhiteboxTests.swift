import Foundation
import Testing
import PhloxCore
@testable import Features

// wave-4 で概要（overview）タブを廃止したため overview 再選択トグルの白箱テストは supersede した
// （決定は decision-log.md「task-1 波及テスト処理」）。非 overview タブの選択と、注入した
// overview インスタンス保持の契約は引き続き検証する。
@MainActor
@Suite struct Wave2AppShellWhiteboxTests {
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
