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
func acceptance_showNewChat_keepsTheDestinationSelectedWithoutCreatingATab() {
    let projectID = ProjectID()
    let router = AppRouter(selectedSession: SessionID(), viewMode: .grid)
    let focusToken = router.newChatFocusToken

    router.showNewChat(projectID: projectID)

    #expect(router.viewMode == .single)
    #expect(router.newChatProjectID == projectID)
    #expect(router.selectedProjectID == projectID)
    #expect(router.showsNewChat)
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
    #expect(router.selectedProjectID == projectID)
    #expect(router.showsNewChat)
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

// 新規チャット画面の「前／次のプロジェクト」は送信先のプロジェクトから数える。
@Test @MainActor
func cycleProjectOnNewChatStartsFromTheDestination() {
    let a = ProjectID(), b = ProjectID(), c = ProjectID()
    let router = AppRouter(viewMode: .single)
    router.showNewChat(projectID: b)

    router.cycleProject(by: -1, ordered: [a, b, c])

    // タブの無いプロジェクトを新規チャットにするのは画面側の ensureProjectSelection（ここでは選択だけ見る）。
    #expect(router.selectedProjectID == a)
}

@Test @MainActor
func cycleProjectIgnoresStaleDestinationOutsideNewChat() {
    let a = ProjectID(), b = ProjectID(), c = ProjectID()
    let router = AppRouter(viewMode: .single)
    router.showNewChat(projectID: b)
    router.viewMode = .grid
    router.clearProjectScope()

    router.cycleProject(by: 1, ordered: [a, b, c])

    #expect(router.selectedProjectID == a)
}

// 送信先が決まらないときだけ、どのプロジェクトも選ばない新規チャット画面になる（要件 FR-1a）。
@Test @MainActor
func showNewChatWithoutAnyDestinationSelectsNoProject() {
    let router = AppRouter(viewMode: .single)

    router.showNewChat(projectID: nil)

    #expect(router.selectedProjectID == nil)
    #expect(!router.showsNewChat)
}

// プロジェクトに重ねた新規チャットは、子タブ・別のプロジェクト・セッションを選ぶと離れる。
@Test @MainActor
func newChatOverAProjectEndsWhenATabProjectOrSessionIsChosen() {
    let a = ProjectID(), b = ProjectID(), session = SessionID()
    let terminal = ProjectTab.terminal(TerminalTabID())
    let router = AppRouter(viewMode: .single)
    router.tabs.updateLayout(for: a) { $0.open(terminal) }

    router.showNewChat(projectID: a)
    router.ensureProjectSelection(chatTabs: [])
    #expect(router.showsNewChat, "重ねている間はタブを選び直さない")
    router.selectTab(terminal, in: a)
    #expect(!router.showsNewChat)

    router.showNewChat(projectID: a)
    router.selectProjectFromSidebar(b)
    #expect(!router.showsNewChat)

    router.showNewChat(projectID: a)
    router.selectedSession = session
    #expect(!router.showsNewChat)
}

// プロジェクトに重ねた新規チャットの ⌘W は、そのプロジェクトで前に出していたタブへ戻る。
@Test @MainActor
func closeOnNewChatOverAProjectReturnsToItsTab() {
    let project = ProjectID()
    let terminal = ProjectTab.terminal(TerminalTabID())
    let router = AppRouter(viewMode: .single)
    router.tabs.updateLayout(for: project) { $0.open(terminal) }
    router.selectTab(terminal, in: project)

    router.showNewChat(projectID: nil)

    #expect(router.requestClose())
    #expect(!router.showsNewChat)
    #expect(router.selectedProjectID == project)
    #expect(router.tabs.layout(for: project).selected == terminal)
}

// どのプロジェクトも選ばない新規チャット画面では、前／次のプロジェクトを送信先から数える。
@Test @MainActor
func cycleProjectOnStandaloneNewChatStartsFromTheDestination() {
    let a = ProjectID(), b = ProjectID(), c = ProjectID()
    let router = AppRouter(viewMode: .single)
    router.newChatProjectID = b
    router.showNewChat(projectID: nil)
    #expect(router.selectedProjectID == nil)

    router.cycleProject(by: 1, ordered: [a, b, c])

    #expect(router.selectedProjectID == c)
}

// 重ねて出している新規チャットのプロジェクトを消したら、新規チャットの状態も外れる。
@Test @MainActor
func forgettingTheProjectEndsNewChatOverIt() async {
    let project = ProjectID()
    let router = AppRouter(viewMode: .single)
    router.showNewChat(projectID: project)

    await router.forgetProject(project, terminals: nil, simulatorHub: nil)

    #expect(!router.showsNewChat)
    #expect(router.selectedProjectID == nil)
    #expect(router.newChatProjectID == nil)
}
