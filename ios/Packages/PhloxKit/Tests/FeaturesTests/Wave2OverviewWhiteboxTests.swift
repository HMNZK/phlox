import Foundation
import Testing
import AgentDomain
import PhloxCore
@testable import Features
@testable import DesignSystemIOS

/// task-5 白箱テスト（実装役著）。SessionsOverview のレイアウト契約とモード切替の補強。
@Suite @MainActor struct Wave2OverviewWhiteboxTests {
    private func makeSession(id: String) -> Session {
        Session(
            id: id,
            name: id,
            agent: .claudeCode,
            status: .idle,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    @Test func gridModeUsesLazyVGridContractFlag() {
        #expect(SessionsOverviewView.gridUsesLazyVGrid)
    }

    @Test func gridMetricsUseCampCardCornerRadius() {
        #expect(SessionsOverviewMetrics.cardCornerRadius == DSRadius.card)
        #expect(SessionsOverviewMetrics.gridMinimumCardWidth == 160)
    }

    @Test func overviewCardBadgeUsesBrandArtworkSize() {
        #expect(SessionsOverviewCardMetrics.badgeSize == 32)
        #expect(DSAgentAvatar.usesBrandArtwork(for: .claudeCode))
        let avatar = DSAgentAvatar(kind: .claudeCode, size: SessionsOverviewCardMetrics.badgeSize)
        #expect(avatar.size == SessionsOverviewCardMetrics.badgeSize)
    }

    @Test func toggleModeDoesNotChangeGridSessions() {
        let sessions = [makeSession(id: "s1"), makeSession(id: "s2")]
        let viewModel = SessionsOverviewViewModel(sessions: sessions)

        viewModel.toggleMode()
        #expect(viewModel.mode == .single)
        #expect(viewModel.gridSessions.map(\.id) == ["s1", "s2"])

        viewModel.toggleMode()
        #expect(viewModel.mode == .grid)
        #expect(viewModel.gridSessions.map(\.id) == ["s1", "s2"])
    }

    @Test func selectSessionIgnoresUnknownID() {
        let sessions = [makeSession(id: "s1"), makeSession(id: "s2")]
        let viewModel = SessionsOverviewViewModel(sessions: sessions)

        viewModel.selectSession(id: "missing")

        #expect(viewModel.singleSession?.id == "s1")
    }

    @Test func accessibilityIDsAreStableForHosting() {
        #expect(SessionsOverviewAccessibilityID.overview == "sessionsOverview")
        #expect(SessionsOverviewAccessibilityID.modeToggle == "sessionsOverview.modeToggle")
        #expect(SessionsOverviewAccessibilityID.gridCard("abc") == "sessionsOverview.gridCard.abc")
        #expect(SessionsOverviewAccessibilityID.singleCard("abc") == "sessionsOverview.singleCard.abc")
    }
}
