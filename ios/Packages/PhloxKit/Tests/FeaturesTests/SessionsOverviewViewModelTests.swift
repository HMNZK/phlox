import Foundation
import Testing
import PhloxCore
@testable import Features

/// SessionsOverview（グリッド/シングル切替）の純ロジック: モード遷移・grid/single の対象選択・空状態。
@MainActor
@Suite("Sessions overview view model") struct SessionsOverviewViewModelTests {
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

    @Test func defaultModeIsGridAndToggleFlipsBetweenGridAndSingle() {
        let vm = SessionsOverviewViewModel(sessions: [makeSession(id: "s1")])

        #expect(vm.mode == .grid)

        vm.toggleMode()
        #expect(vm.mode == .single)

        vm.toggleMode()
        #expect(vm.mode == .grid)
    }

    @Test func gridShowsAllSessionsAndSingleDefaultsToFirst() {
        let sessions = [makeSession(id: "s1"), makeSession(id: "s2"), makeSession(id: "s3")]
        let vm = SessionsOverviewViewModel(sessions: sessions)

        #expect(vm.gridSessions.map(\.id) == ["s1", "s2", "s3"])
        #expect(vm.singleSession?.id == "s1")
    }

    @Test func selectingSessionUpdatesSingleSessionWithoutAffectingGrid() {
        let sessions = [makeSession(id: "s1"), makeSession(id: "s2"), makeSession(id: "s3")]
        let vm = SessionsOverviewViewModel(sessions: sessions)

        vm.selectSession(id: "s2")

        #expect(vm.singleSession?.id == "s2")
        #expect(vm.gridSessions.map(\.id) == ["s1", "s2", "s3"])
    }

    @Test func selectSessionIgnoresUnknownID() {
        let sessions = [makeSession(id: "s1"), makeSession(id: "s2")]
        let vm = SessionsOverviewViewModel(sessions: sessions)

        vm.selectSession(id: "missing")

        #expect(vm.singleSession?.id == "s1")
    }

    @Test func toggleModeDoesNotChangeGridSessions() {
        let sessions = [makeSession(id: "s1"), makeSession(id: "s2")]
        let vm = SessionsOverviewViewModel(sessions: sessions)

        vm.toggleMode()
        #expect(vm.gridSessions.map(\.id) == ["s1", "s2"])

        vm.toggleMode()
        #expect(vm.gridSessions.map(\.id) == ["s1", "s2"])
    }

    @Test func emptySessionsSetsEmptyFlagAndNilSingleSession() {
        let vm = SessionsOverviewViewModel(sessions: [])

        #expect(vm.isEmpty == true)
        #expect(vm.gridSessions.isEmpty)
        #expect(vm.singleSession == nil)
    }

    /// UI テストが画面要素を引く識別子（外部との約束）。
    @Test func accessibilityIDsAreStableForHosting() {
        #expect(SessionsOverviewAccessibilityID.overview == "sessionsOverview")
        #expect(SessionsOverviewAccessibilityID.modeToggle == "sessionsOverview.modeToggle")
        #expect(SessionsOverviewAccessibilityID.gridCard("abc") == "sessionsOverview.gridCard.abc")
        #expect(SessionsOverviewAccessibilityID.singleCard("abc") == "sessionsOverview.singleCard.abc")
    }
}
