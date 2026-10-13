import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

// MARK: - mainRoute

@Test @MainActor
func appRouter_defaultsToSessionsRoute() {
    let router = AppRouter()

    #expect(router.mainRoute == .sessions)
}

@Test @MainActor
func showSessions_setsMainRouteToSessions() {
    let router = AppRouter()

    router.showSessions()

    #expect(router.mainRoute == .sessions)
}

// MARK: - gridFilterProjectID

@Test @MainActor
func toggleGridFilter_setsProjectIDWhenNil() {
    let router = AppRouter()
    let projectID = ProjectID()

    router.toggleGridFilter(projectID: projectID)

    #expect(router.gridFilterProjectID == projectID)
}

@Test @MainActor
func toggleGridFilter_clearsWhenSameProjectID() {
    let router = AppRouter()
    let projectID = ProjectID()
    router.gridFilterProjectID = projectID

    router.toggleGridFilter(projectID: projectID)

    #expect(router.gridFilterProjectID == nil)
}

@Test @MainActor
func toggleGridFilter_replacesWhenDifferentProjectID() {
    let router = AppRouter()
    let first = ProjectID()
    let second = ProjectID()
    router.gridFilterProjectID = first

    router.toggleGridFilter(projectID: second)

    #expect(router.gridFilterProjectID == second)
}

@Test @MainActor
func clearGridFilter_resetsToNil() {
    let router = AppRouter()
    router.gridFilterProjectID = ProjectID()

    router.clearGridFilter()

    #expect(router.gridFilterProjectID == nil)
}

@Test @MainActor
func acceptance_showNewChat_setsDestinationWithoutSelectingAProjectTab() {
    let projectID = ProjectID()
    let router = AppRouter(selectedSession: SessionID(), viewMode: .grid)
    let focusToken = router.newChatFocusToken

    router.showNewChat(projectID: projectID)

    #expect(router.viewMode == .single)
    #expect(router.newChatProjectID == projectID)
    #expect(router.selectedProjectID == nil)
    #expect(router.selectedSession == nil)
    #expect(router.tabs.layout(for: projectID).items.isEmpty)
    #expect(router.newChatFocusToken == focusToken + 1)
}

@Test @MainActor
func acceptance_showNewChatWithoutExplicitProjectSendsToCurrentProject() {
    let projectID = ProjectID()
    let router = AppRouter(selectedSession: SessionID(), viewMode: .grid)
    router.selectProject(projectID)
    let focusToken = router.newChatFocusToken

    router.showNewChat(projectID: nil)

    #expect(router.viewMode == .single)
    #expect(router.newChatProjectID == projectID)
    #expect(router.selectedProjectID == nil)
    #expect(router.selectedSession == nil)
    #expect(router.tabs.layout(for: projectID).items.isEmpty)
    #expect(router.newChatFocusToken == focusToken + 1)
}

// 新規チャット画面の ⌘W は、送信先のプロジェクトで前に出していたタブへ戻る。戻り先が無ければウィンドウを閉じる（false）。
@Test @MainActor
func closeOnNewChatReturnsToTheDestinationsTabOrClosesTheWindow() {
    let project = ProjectID(), session = SessionID()
    let router = AppRouter(viewMode: .single)
    router.selectTab(.chat(session), in: project)
    router.showNewChat(projectID: nil)

    #expect(router.requestClose())
    #expect(router.selectedProjectID == project)
    #expect(router.selectedSession == session)
    #expect(router.tabRequest == nil)

    router.showNewChat(projectID: ProjectID())
    #expect(!router.requestClose())
}
