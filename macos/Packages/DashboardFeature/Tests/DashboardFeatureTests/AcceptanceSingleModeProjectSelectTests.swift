import Testing
import AgentDomain
@testable import DashboardFeature

// セッション 0 件のプロジェクトを選ぶと、そのプロジェクトの新規チャットを開く。
@MainActor
@Test func selectProjectFromSidebar_inSingleModeShowsNewChatTabWhenNoSessions() {
    let router = AppRouter(viewMode: .single)
    router.selectedSession = SessionID()
    let project = ProjectID()
    let terminal = ProjectTab.terminal(TerminalTabID())
    router.tabs.updateLayout(for: project) { $0.open(terminal) }

    router.selectProjectFromSidebar(project)
    router.ensureProjectSelection(chatTabs: [])

    #expect(router.viewMode == .single)
    #expect(router.selectedProjectID == project)
    #expect(router.selectedSession == nil)
    #expect(router.tabs.layout(for: project).selected == .newChat)
    #expect(router.tabs.layout(for: project).items.contains(terminal))
    #expect(StartAreaPolicy.content(hasSelectedSession: false) == .newChat)
}

@MainActor
@Test func selectProjectFromSidebar_inGridMode_keepsFilterOnSecondClick() {
    let router = AppRouter(viewMode: .grid)
    let project = ProjectID()

    router.selectProjectFromSidebar(project)
    #expect(router.viewMode == .grid)
    #expect(router.selectedProjectID == project)
    #expect(router.gridFilterProjectID == project)

    router.selectProjectFromSidebar(project)
    #expect(router.gridFilterProjectID == project)
    #expect(router.viewMode == .grid)
}
