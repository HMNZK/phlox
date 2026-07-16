import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

private func fixedSessionID(_ value: UInt8) -> SessionID {
    SessionID(rawValue: UUID(uuid: (
        value, 0, 0, 0,
        0, 0,
        0, 0,
        0, 0,
        0, 0, 0, 0, 0, 0
    )))
}

private func fixedProjectID(_ value: UInt8 = 1) -> ProjectID {
    ProjectID(rawValue: UUID(uuid: (
        value, 0, 0, 0,
        0, 0,
        0, 0,
        0, 0,
        0, 0, 0, 0, 0, 1
    )))
}

private func otherProjectID() -> ProjectID {
    ProjectID(rawValue: UUID(uuid: (
        2, 0, 0, 0,
        0, 0,
        0, 0,
        0, 0,
        0, 0, 0, 0, 0, 2
    )))
}

private func input(
    _ value: UInt8,
    projectID: ProjectID = fixedProjectID(),
    parent: SessionID? = nil,
    launchContext: SessionLaunchContext = .interactive,
    status: SessionStatus = .idle
) -> SessionTreeInput {
    SessionTreeInput(
        id: fixedSessionID(value),
        parentSessionID: parent,
        projectID: projectID,
        launchContext: launchContext,
        status: status,
        name: "session-\(value)",
        agentRef: .builtin(.claudeCode)
    )
}

@Suite struct RunningSessionCountTests {
    @Test func parentRunningWithNestedOrchestrationRunning_returnsVisibleOneNestedOne() {
        let projectID = fixedProjectID()
        let parent = input(1, projectID: projectID, status: .running)
        let child = input(
            2,
            projectID: projectID,
            parent: parent.id,
            launchContext: .orchestration,
            status: .running
        )

        let breakdown = DashboardViewModel.runningBreakdown(in: projectID, from: [parent, child])

        #expect(breakdown.visible == 1)
        #expect(breakdown.nestedOrchestration == 1)
        #expect(breakdown.total == 2)
    }

    @Test func onlyVisibleInteractiveRunning_matchesLegacyTotalWhenNoHiddenOrchestration() {
        let projectID = fixedProjectID()
        let first = input(1, projectID: projectID, status: .running)
        let second = input(2, projectID: projectID, status: .running)
        let idle = input(3, projectID: projectID, status: .idle)

        let breakdown = DashboardViewModel.runningBreakdown(in: projectID, from: [first, second, idle])

        #expect(breakdown.visible == 2)
        #expect(breakdown.nestedOrchestration == 0)
        #expect(breakdown.total == 2)
    }

    @Test func multiLevelNestedOrchestrationRunning_sumsNestedAcrossDepth() {
        let projectID = fixedProjectID()
        let parent = input(1, projectID: projectID, status: .running)
        let child = input(
            2,
            projectID: projectID,
            parent: parent.id,
            launchContext: .orchestration,
            status: .running
        )
        let grandchild = input(
            3,
            projectID: projectID,
            parent: child.id,
            launchContext: .orchestration,
            status: .running
        )

        let breakdown = DashboardViewModel.runningBreakdown(in: projectID, from: [parent, child, grandchild])

        #expect(breakdown.visible == 1)
        #expect(breakdown.nestedOrchestration == 2)
        #expect(breakdown.total == 3)
    }

    @Test func hiddenTopLevelOrchestrationRunning_isExcludedFromReachableCount() {
        let projectID = fixedProjectID()
        let visible = input(1, projectID: projectID, status: .running)
        let hidden = input(
            2,
            projectID: projectID,
            launchContext: .orchestration,
            status: .running
        )

        let breakdown = DashboardViewModel.runningBreakdown(in: projectID, from: [visible, hidden])

        #expect(breakdown.visible == 1)
        #expect(breakdown.nestedOrchestration == 0)
        #expect(breakdown.total == 1)
    }

    @Test func nestedInteractiveRunningUnderVisibleParent_countsAsVisible() {
        let projectID = fixedProjectID()
        let parent = input(1, projectID: projectID, status: .running)
        let child = input(
            2,
            projectID: projectID,
            parent: parent.id,
            launchContext: .interactive,
            status: .running
        )

        let breakdown = DashboardViewModel.runningBreakdown(in: projectID, from: [parent, child])

        #expect(breakdown.visible == 2)
        #expect(breakdown.nestedOrchestration == 0)
        #expect(breakdown.total == 2)
    }

    @Test func nestedOrchestrationRunningUnderIdleVisibleParent_countsOnlyNested() {
        let projectID = fixedProjectID()
        let parent = input(1, projectID: projectID, status: .idle)
        let child = input(
            2,
            projectID: projectID,
            parent: parent.id,
            launchContext: .orchestration,
            status: .running
        )

        let breakdown = DashboardViewModel.runningBreakdown(in: projectID, from: [parent, child])

        #expect(breakdown.visible == 0)
        #expect(breakdown.nestedOrchestration == 1)
        #expect(breakdown.total == 1)
    }

    @Test func otherProjectSessions_areIgnored() {
        let projectID = fixedProjectID()
        let other = otherProjectID()
        let inProject = input(1, projectID: projectID, status: .running)
        let elsewhere = input(2, projectID: other, status: .running)

        let breakdown = DashboardViewModel.runningBreakdown(in: projectID, from: [inProject, elsewhere])

        #expect(breakdown.total == 1)
    }

    @Test @MainActor
    func dashboardRunningSessionCount_delegatesToBreakdownTotal() async throws {
        let ptyManager = MockPTYManager()
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

        let projectFolder = workspaceURL.appendingPathComponent("running-count", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
        )

        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = try #require(
            dashboard.addProject(name: "Running Count", directoryPath: projectFolder.path)
        )
        let firstID = try await dashboard.spawnNewSession(kind: .codex, projectID: projectID)
        let secondID = try await dashboard.spawnNewSession(kind: .codex, projectID: projectID)

        let firstVM = try #require(dashboard.sessions.first { $0.id == firstID })
        let secondVM = try #require(dashboard.sessions.first { $0.id == secondID })
        try await waitUntil { firstVM.status == .idle && secondVM.status == .idle }
        firstVM.markInputSubmitted()
        secondVM.markInputSubmitted()

        let breakdown = dashboard.runningBreakdown(in: projectID)
        #expect(breakdown.visible == 2)
        #expect(breakdown.nestedOrchestration == 0)
        #expect(dashboard.runningSessionCount(in: projectID) == breakdown.total)
        #expect(dashboard.runningSessionCount(in: projectID) == 2)
    }
}
