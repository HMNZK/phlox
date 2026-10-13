import Testing
import AgentDomain
@testable import DashboardFeature

// タブが 1 つも無いプロジェクトを選ぶと、そのプロジェクトを送信先にして新規チャットを開く（D21）。
@MainActor
@Test func selectProjectFromSidebar_inSingleModeShowsNewChatWhenProjectHasNoTabs() {
    let router = AppRouter(viewMode: .single)
    router.selectedSession = SessionID()
    let project = ProjectID()

    router.selectProjectFromSidebar(project)
    router.ensureProjectSelection(chatTabs: [])

    #expect(router.viewMode == .single)
    #expect(router.newChatProjectID == project)
    #expect(router.selectedProjectID == nil)
    #expect(router.selectedSession == nil)
    #expect(router.tabs.layout(for: project).items.isEmpty)
    #expect(StartAreaPolicy.content(hasSelectedSession: false) == .newChat)
}

// チャットが無くても、開いているタブがあればそれを出す。
@MainActor
@Test func selectProjectFromSidebar_inSingleModeShowsOpenTabWhenNoChats() {
    let router = AppRouter(viewMode: .single)
    let project = ProjectID()
    let terminal = ProjectTab.terminal(TerminalTabID())
    router.tabs.updateLayout(for: project) { $0.open(terminal) }

    router.selectProjectFromSidebar(project)
    router.ensureProjectSelection(chatTabs: [])

    #expect(router.selectedProjectID == project)
    #expect(router.tabs.layout(for: project).selected == terminal)
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
