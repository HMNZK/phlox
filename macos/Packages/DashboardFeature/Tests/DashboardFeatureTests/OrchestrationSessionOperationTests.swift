import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite struct OrchestrationSessionOperationTests {
    @MainActor
    private func makeDashboardWithProject() async throws -> (
        dashboard: DashboardViewModel,
        projectID: ProjectID,
        ptyManager: MockPTYManager
    ) {
        let ptyManager = MockPTYManager()
        let workspaceURL = try makeTemporaryWorkspaceRoot()

        let projectFolder = workspaceURL.appendingPathComponent("orchestration-ops", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            agentBinaryPaths: [
                .claudeCode: "/usr/local/bin/claude",
                .codex: "/usr/local/bin/codex",
            ]
        )

        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = try #require(
            dashboard.addProject(name: "Orchestration Ops", directoryPath: projectFolder.path)
        )
        return (dashboard, projectID, ptyManager)
    }

    private func flattenForest(_ nodes: [SessionTreeNode]) -> [SessionTreeNode] {
        nodes.flatMap { [$0] + flattenForest($0.children) }
    }

    @Test @MainActor
    func sessionForest_keepsNestedOrchestrationChildAndExcludesOrphanOrchestrationRoot() async throws {
        let (dashboard, projectID, ptyManager) = try await makeDashboardWithProject()

        let parentID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )
        let nestedChildID = try await dashboard.spawnNewSession(
            kind: .codex,
            projectID: projectID,
            from: parentID,
            launchContext: .orchestration
        )
        let orphanOrchestrationID = try await dashboard.spawnNewSession(
            kind: .codex,
            projectID: projectID,
            launchContext: .orchestration
        )

        try await waitUntil { ptyManager.spawnCalls.count == 3 }

        let forest = dashboard.sessionForest(in: projectID)
        let flattened = flattenForest(forest)

        #expect(forest.map(\.id) == [parentID])
        #expect(forest[0].children.map(\.id) == [nestedChildID])
        #expect(forest[0].children[0].launchContext == .orchestration)
        #expect(forest[0].children[0].depth == 1)

        let flattenedIDs = Set(flattened.map(\.id))
        #expect(flattenedIDs.contains(nestedChildID))
        #expect(!flattenedIDs.contains(orphanOrchestrationID))

        #expect(dashboard.sessionNodes(in: projectID).map(\.id) == [parentID])
        #expect(dashboard.sessionNodes.map(\.id).contains(orphanOrchestrationID))
    }

    @Test @MainActor
    func sessionNode_resolvesNestedOrchestrationSessionForDetailPane() async throws {
        let (dashboard, projectID, ptyManager) = try await makeDashboardWithProject()

        let parentID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )
        let nestedChildID = try await dashboard.spawnNewSession(
            kind: .codex,
            projectID: projectID,
            from: parentID,
            launchContext: .orchestration
        )

        try await waitUntil { ptyManager.spawnCalls.count == 2 }

        let parentNode = try #require(dashboard.sessionNode(id: parentID))
        let childNode = try #require(dashboard.sessionNode(id: nestedChildID))

        #expect(parentNode.launchContext == .interactive)
        #expect(parentNode.projectID == projectID)
        #expect(childNode.launchContext == .orchestration)
        #expect(childNode.projectID == projectID)
        #expect(childNode.controllable.parentSessionID == parentID)
        #expect(dashboard.sessionNodes(in: projectID).map(\.id) == [parentID])
        #expect(dashboard.sessionNode(id: nestedChildID)?.pty != nil)
    }

    @Test @MainActor
    func sessionNode_resolvesOrphanOrchestrationRootForDetailPane() async throws {
        let (dashboard, projectID, ptyManager) = try await makeDashboardWithProject()

        let orphanOrchestrationID = try await dashboard.spawnNewSession(
            kind: .codex,
            projectID: projectID,
            launchContext: .orchestration
        )

        try await waitUntil { ptyManager.spawnCalls.count == 1 }

        // サイドバー forest からは除外されるが、選択時に端末が出る契約（id 解決＋pty 非nil）は満たす。
        #expect(dashboard.sessionForest(in: projectID).isEmpty)
        let orphanNode = try #require(dashboard.sessionNode(id: orphanOrchestrationID))
        #expect(orphanNode.launchContext == .orchestration)
        #expect(orphanNode.pty != nil)
    }

    @Test @MainActor
    func topLevelInteractiveSession_selectionAndRemovalRemainUnchanged() async throws {
        let (dashboard, projectID, ptyManager) = try await makeDashboardWithProject()

        let topLevelID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )

        try await waitUntil { ptyManager.spawnCalls.count == 1 }

        let forest = dashboard.sessionForest(in: projectID)
        #expect(forest.map(\.id) == [topLevelID])
        #expect(forest[0].children.isEmpty)

        let node = try #require(dashboard.sessionNode(id: topLevelID))
        #expect(node.launchContext == .interactive)
        #expect(node.projectID == projectID)
        #expect(dashboard.sessionNodes(in: projectID).map(\.id) == [topLevelID])

        await dashboard.removeSession(topLevelID)

        #expect(dashboard.sessionNode(id: topLevelID) == nil)
        #expect(dashboard.sessionForest(in: projectID).isEmpty)
        #expect(ptyManager.killedIDs == [topLevelID])
    }

    @Test @MainActor
    func removeSession_onNestedOrchestrationChild_keepsParentAndUsesExistingKillPath() async throws {
        let (dashboard, projectID, ptyManager) = try await makeDashboardWithProject()

        let parentID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )
        let nestedChildID = try await dashboard.spawnNewSession(
            kind: .codex,
            projectID: projectID,
            from: parentID,
            launchContext: .orchestration
        )

        try await waitUntil { ptyManager.spawnCalls.count == 2 }

        #expect(await dashboard.removeSession(nestedChildID))

        #expect(dashboard.sessionNode(id: nestedChildID) == nil)
        #expect(dashboard.sessionNode(id: parentID) != nil)
        #expect(ptyManager.killedIDs == [nestedChildID])

        let forest = dashboard.sessionForest(in: projectID)
        #expect(forest.map(\.id) == [parentID])
        #expect(forest[0].children.isEmpty)
    }
}
