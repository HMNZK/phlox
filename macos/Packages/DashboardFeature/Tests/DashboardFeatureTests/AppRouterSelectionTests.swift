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
    let router = AppRouter(viewMode: .team)
    let sessionID = SessionID()

    router.openSingle(sessionID: sessionID)

    #expect(router.viewMode == .single)
    #expect(router.selectedSession == sessionID)
}
