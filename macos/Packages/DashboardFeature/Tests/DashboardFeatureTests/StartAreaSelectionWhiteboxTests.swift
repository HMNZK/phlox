import AgentDomain
import Foundation
import PTYKit
import Testing
@testable import DashboardFeature

@MainActor
private func whiteboxDashboardWithTwoProjects() async throws -> (
    dashboard: DashboardViewModel,
    projectA: ProjectID,
    projectB: ProjectID,
    workspaceRoot: URL
) {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    let folderA = workspaceRoot.appendingPathComponent("project-a", isDirectory: true)
    let folderB = workspaceRoot.appendingPathComponent("project-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)

    let projectA = Project(
        name: "Project A",
        directoryPath: folderA.path,
        createdAt: Date(timeIntervalSince1970: 100),
        isManagedDirectory: false
    )
    let projectB = Project(
        name: "Project B",
        directoryPath: folderB.path,
        createdAt: Date(timeIntervalSince1970: 200),
        isManagedDirectory: false
    )

    let projectStore = InMemoryProjectStore()
    try await projectStore.save([projectA, projectB])

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: hookStream,
        projects: projectStore,
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"]
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    return (dashboard, projectA.id, projectB.id, workspaceRoot)
}

@Suite(.serialized)
struct StartAreaSelectionWhiteboxTests {
    @Test @MainActor
    func fileMenuNewChatUsesSelectedProjectWithoutSpawning() async throws {
        let (dashboard, projectA, projectB, workspaceRoot) = try await whiteboxDashboardWithTwoProjects()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
        let router = AppRouter(selectedSession: SessionID(), viewMode: .grid)
        router.selectedProjectID = projectB
        let sessionCount = dashboard.sessionNodes.count

        NewChatEntryActions(router: router, dashboard: dashboard).fileMenu()

        #expect(router.selectedProjectID == projectB)
        #expect(router.selectedProjectID != projectA)
        #expect(router.selectedSession == nil)
        #expect(router.viewMode == .single)
        #expect(router.tabs.layout(for: projectB).selected == .newChat)
        #expect(dashboard.sessionNodes.count == sessionCount)
    }

    @Test @MainActor
    func selectingSessionlessProjectInSingleModeShowsNewChatWithoutSpawning() async throws {
        let (dashboard, _, projectB, workspaceRoot) = try await whiteboxDashboardWithTwoProjects()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
        let router = AppRouter(selectedSession: SessionID(), viewMode: .single)
        let sessionCount = dashboard.sessionNodes.count

        router.selectProjectFromSidebar(projectB)
        router.ensureProjectSelection(chatTabs: dashboard.chatTabs(in: projectB))

        #expect(router.selectedProjectID == projectB)
        #expect(router.selectedSession == nil)
        #expect(router.viewMode == .single)
        #expect(router.tabs.layout(for: projectB).selected == .newChat)
        #expect(dashboard.sessionNodes.count == sessionCount)
    }
}

@Test
func startAreaPolicy_routesToNewChatOrProjectOnboarding() {
    #expect(StartAreaPolicy.content(hasSelectedSession: true) == .sessionContent)
    #expect(StartAreaPolicy.content(hasSelectedSession: false) == .newChat)
    #expect(StartAreaPolicy.content(hasSelectedSession: false, hasProjects: false) == .projectOnboarding)
    #expect(StartAreaPolicy.content(hasSelectedSession: true, hasProjects: false) == .projectOnboarding)
}
