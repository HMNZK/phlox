import Foundation
import Testing
import AgentDomain
import PTYKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// Control API 契約 1〜4 の DashboardViewModel 写像を直接検証する（非 E2E）。
@Suite @MainActor
struct ControlDashboardMappingTests {
    private static let subToolUseId = "toolu_control_mapping_subagent"

    @MainActor
    private func makeDashboardWithPTYAndStructuredSessions() async throws -> (
        dashboard: DashboardViewModel,
        ptyID: SessionID,
        structuredID: SessionID,
        workspaceRoot: URL
    ) {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        let projectFolder = workspaceRoot.appendingPathComponent("control-mapping-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceRoot,
            appServerClientFactory: { _, _, _, _, _ in EventYieldingStructuredClient() }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Control Mapping", directoryPath: projectFolder.path))

        let ptyID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID, backend: .pty)
        let structuredID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            backend: .appServer
        )
        return (dashboard, ptyID, structuredID, workspaceRoot)
    }

    @Test
    func absentSession_interruptReturnsNotFoundBeforeAppServerCheck() async throws {
        let (dashboard, _, _, workspaceRoot) = try await makeDashboardWithPTYAndStructuredSessions()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let unknownID = SessionID()
        let outcome = await dashboard.controlInterruptSession(unknownID)
        #expect(outcome == .notFound)
        #expect(dashboard.controlSubAgents(for: unknownID) == nil)
        #expect(dashboard.controlSubAgentMessages(for: unknownID, subAgentID: "any") == nil)
        #expect(dashboard.controlUsage(for: unknownID) == nil)
    }

    @Test
    func ptySession_interruptUnsupportedAndStructuredFieldsNil() async throws {
        let (dashboard, ptyID, _, workspaceRoot) = try await makeDashboardWithPTYAndStructuredSessions()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let outcome = await dashboard.controlInterruptSession(ptyID)
        #expect(outcome == .unsupported)
        #expect(dashboard.controlSubAgents(for: ptyID) == nil)
        #expect(dashboard.controlSubAgentMessages(for: ptyID, subAgentID: Self.subToolUseId) == nil)
        #expect(dashboard.controlUsage(for: ptyID) == nil)
    }

    @Test
    func structuredSession_interruptAcceptedWhileIdle() async throws {
        let (dashboard, _, structuredID, workspaceRoot) = try await makeDashboardWithPTYAndStructuredSessions()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let outcome = await dashboard.controlInterruptSession(structuredID)
        #expect(outcome == .accepted)
    }

    @Test
    func structuredSession_subAgentsReturnsArrayAndUnknownSubAgentMessagesNil() async throws {
        let (dashboard, _, structuredID, workspaceRoot) = try await makeDashboardWithPTYAndStructuredSessions()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let subAgents = dashboard.controlSubAgents(for: structuredID)
        #expect(subAgents != nil)
        #expect(subAgents == [])

        #expect(dashboard.controlSubAgentMessages(for: structuredID, subAgentID: "unknown-subagent") == nil)

        let usage = dashboard.controlUsage(for: structuredID)
        #expect(usage == ControlSessionUsage(turn: nil))
    }

    @Test
    func structuredSession_subAgentsReflectsPopulatedSubAgent() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let projectFolder = workspaceRoot.appendingPathComponent("control-mapping-subagent", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        let client = EventYieldingStructuredClient()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceRoot,
            appServerClientFactory: { _, _, _, _, _ in client }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "SubAgent", directoryPath: projectFolder.path))
        let structuredID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            backend: .appServer
        )

        client.yield(.subAgentStarted(
            toolUseId: Self.subToolUseId,
            subagentType: "explore",
            description: "scan"
        ))
        client.yield(.subAgentCompleted(
            toolUseId: Self.subToolUseId,
            status: "completed",
            summary: "done",
            outputFile: nil
        ))
        client.yield(.turnCompleted(nativeSessionId: nil))

        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            guard let appServer = dashboard.sessionNodes.first(where: { $0.id == structuredID })?.appServer else {
                return false
            }
            return appServer.subAgents.contains { $0.id == Self.subToolUseId }
        }

        let subAgents = try #require(dashboard.controlSubAgents(for: structuredID))
        #expect(subAgents.count == 1)
        #expect(subAgents[0].id == Self.subToolUseId)

        let messages = dashboard.controlSubAgentMessages(for: structuredID, subAgentID: Self.subToolUseId)
        #expect(messages != nil)
    }
}
