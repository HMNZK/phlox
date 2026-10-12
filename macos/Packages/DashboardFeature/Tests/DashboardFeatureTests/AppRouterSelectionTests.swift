// task-0（PM 著・凍結面）: プロジェクト選択とドリルダウンのルーター状態。
import Testing
import AgentDomain
@testable import DashboardFeature

@MainActor
@Test func appRouter_selectProject_setsAndClearsSelection() {
    let router = AppRouter()
    #expect(router.selectedProjectID == nil)

    let projectID = ProjectID()
    router.selectProject(projectID)
    #expect(router.selectedProjectID == projectID)

    router.selectProject(nil)
    #expect(router.selectedProjectID == nil)
}

@MainActor
@Test func appRouter_openSingle_switchesModeAndSelection() {
    let router = AppRouter(viewMode: .grid)
    let sessionID = SessionID()

    router.openSingle(sessionID: sessionID)

    #expect(router.viewMode == .single)
    #expect(router.selectedSession == sessionID)
}

@MainActor
@Test func appRouter_reselectingProjectPreservesFocusedChat() {
    let router = AppRouter()
    let project = ProjectID()
    let session = SessionID()
    router.selectTab(.chat(session), in: project)
    router.selectProjectFromSidebar(project)
    #expect(router.selectedSession == session)
    #expect(router.tabs.layout(for: project).selected == .chat(session))
}

@MainActor
@Test func appRouter_splitRightSynchronizesFocusedSession() {
    let router = AppRouter()
    let project = ProjectID()
    let first = SessionID()
    let second = SessionID()
    router.selectTab(.chat(first), in: project)
    router.splitRight(.chat(second), in: project, chats: [.chat(first), .chat(second)])
    #expect(router.tabs.layout(for: project).selected == .chat(second))
    #expect(router.selectedSession == second)
}
