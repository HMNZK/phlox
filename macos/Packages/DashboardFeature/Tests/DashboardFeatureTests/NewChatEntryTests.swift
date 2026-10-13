import Foundation
import AgentDomain
import PTYKit
import Testing
@testable import DashboardFeature

@MainActor
private func makeNewChatEntryFixture() async throws -> (
    dashboard: DashboardViewModel,
    router: AppRouter,
    projectA: ProjectID,
    projectB: ProjectID
) {
    let projectA = Project(name: "Project A", directoryPath: "/tmp", createdAt: Date(), isManagedDirectory: false)
    let projectB = Project(name: "Project B", directoryPath: "/var/tmp", createdAt: Date(), isManagedDirectory: false)
    let projectStore = InMemoryProjectStore()
    try await projectStore.save([projectA, projectB])
    let dashboard = DashboardViewModel(environment: makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() },
        projects: projectStore,
        agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"],
        appServerClientFactory: { _, _, _, _, _ in EventYieldingStructuredClient() }
    ))
    await dashboard.start()
    return (dashboard, AppRouter(viewMode: .grid), projectA.id, projectB.id)
}

@MainActor
private func expectNewChat(
    router: AppRouter,
    dashboard: DashboardViewModel,
    projectID: ProjectID,
    previousSessionCount: Int,
    previousFocusToken: Int
) {
    #expect(router.selectedSession == nil)
    #expect(router.viewMode == .single)
    #expect(router.newChatProjectID == projectID)
    #expect(router.selectedProjectID == nil)
    #expect(router.tabs.layout(for: projectID).items.isEmpty)
    #expect(router.newChatFocusToken == previousFocusToken + 1)
    #expect(dashboard.sessionNodes.count == previousSessionCount)
}

@Suite("AC-1 新規チャットの入口")
@MainActor
struct NewChatEntryTests {
    @Test
    func AC1_fileMenuClearsSelectedSessionFromGrid() async throws {
        let (dashboard, router, projectA, _) = try await makeNewChatEntryFixture()
        let selectedSession = try await dashboard.spawnNewSession(
            kind: .claudeCode, projectID: projectA, backend: .appServer
        )
        router.selectedSession = selectedSession
        let sessionCount = dashboard.sessionNodes.count
        let focusToken = router.newChatFocusToken

        NewChatEntryActions(router: router, dashboard: dashboard).fileMenu()

        expectNewChat(router: router, dashboard: dashboard, projectID: projectA,
                      previousSessionCount: sessionCount, previousFocusToken: focusToken)
        #expect(dashboard.sessionNode(id: selectedSession) != nil)
        _ = await dashboard.removeSession(selectedSession)
    }

    @Test
    func AC1_sidebarFooterUsesCurrentProject() async throws {
        let (dashboard, router, projectA, _) = try await makeNewChatEntryFixture()
        router.viewMode = .single
        router.selectedProjectID = projectA
        router.selectedSession = SessionID()
        let sessionCount = dashboard.sessionNodes.count
        let focusToken = router.newChatFocusToken

        NewChatEntryActions(router: router, dashboard: dashboard).sidebarFooter()

        expectNewChat(router: router, dashboard: dashboard, projectID: projectA,
                      previousSessionCount: sessionCount, previousFocusToken: focusToken)
    }

    @Test
    func AC1_projectPlusUsesTheRowProject() async throws {
        let (dashboard, router, projectA, projectB) = try await makeNewChatEntryFixture()
        router.selectedProjectID = projectA
        router.selectedSession = SessionID()
        let sessionCount = dashboard.sessionNodes.count
        let focusToken = router.newChatFocusToken

        NewChatEntryActions(router: router, dashboard: dashboard).projectPlus(projectB)

        expectNewChat(router: router, dashboard: dashboard, projectID: projectB,
                      previousSessionCount: sessionCount, previousFocusToken: focusToken)
    }

    @Test
    func AC1_projectMenuUsesTheRowProject() async throws {
        let (dashboard, router, projectA, projectB) = try await makeNewChatEntryFixture()
        router.selectedProjectID = projectA
        router.selectedSession = SessionID()
        let sessionCount = dashboard.sessionNodes.count
        let focusToken = router.newChatFocusToken

        NewChatEntryActions(router: router, dashboard: dashboard).projectMenu(projectB)

        expectNewChat(router: router, dashboard: dashboard, projectID: projectB,
                      previousSessionCount: sessionCount, previousFocusToken: focusToken)
    }

    @Test
    func AC1_gridEmptyStateUsesFilteredProject() async throws {
        let (dashboard, router, projectA, projectB) = try await makeNewChatEntryFixture()
        router.selectedProjectID = projectA
        router.gridFilterProjectID = projectB
        router.selectedSession = SessionID()
        let sessionCount = dashboard.sessionNodes.count
        let focusToken = router.newChatFocusToken

        NewChatEntryActions(router: router, dashboard: dashboard)
            .gridEmptyState(projectID: router.gridFilterProjectID)

        expectNewChat(router: router, dashboard: dashboard, projectID: projectB,
                      previousSessionCount: sessionCount, previousFocusToken: focusToken)
    }
}

@Test
func AC9_fileAndProjectMenusContainNoTerminalSessionEntry() {
    #expect(FileMenuItem.allCases == [
        .newChat, .newTab, .openFile, .addProject, .divider, .exportConversation, .copyConversation,
    ])
    #expect(ProjectRowMenuItem.allCases == [.newChat, .rename, .delete])
}

// ヘッダーの名前は、新規チャット画面では「新規チャット」、プロジェクトでは選択中のタブ、グリッドでは出さない（FR-41）。
@MainActor
@Test func headerTitleFollowsTheShownScreen() async throws {
    let (dashboard, router, projectA, _) = try await makeNewChatEntryFixture()
    #expect(HeaderTabTitle.tab(router: router, viewModel: dashboard) == nil)

    router.showNewChat(projectID: projectA)
    #expect(HeaderTabTitle.tab(router: router, viewModel: dashboard) == .newChat)

    router.selectedProjectID = projectA
    router.openChildTab(.file("Sources/App.swift"))
    #expect(HeaderTabTitle.tab(router: router, viewModel: dashboard) == .file("Sources/App.swift"))
    #expect(ChildTabBar.titleText(for: .file("Sources/App.swift"), viewModel: dashboard, changeCount: 0,
                                  locale: Locale(identifier: "ja"), bundle: .main) == "App.swift")

    router.viewMode = .grid
    #expect(HeaderTabTitle.tab(router: router, viewModel: dashboard) == nil)

    let orphan = SessionID()
    router.viewMode = .single
    router.selectedProjectID = nil
    router.selectedSession = orphan
    #expect(HeaderTabTitle.tab(router: router, viewModel: dashboard) == .chat(orphan))
}
