import Foundation
import Testing
import AgentDomain
import AppBootstrap
import ControlServer
import MessageStore
import SessionFeature
import StructuredChatKit
@testable import DashboardFeature

actor RoleSessionStore: SessionStoreProtocol {
    private var stored: [PersistedSessionDescriptor]

    init(_ sessions: [PersistedSessionDescriptor] = []) {
        self.stored = sessions
    }

    func load() async -> [PersistedSessionDescriptor] { stored }

    func save(_ sessions: [PersistedSessionDescriptor]) async throws {
        stored = sessions
    }
}

@MainActor
@Suite struct AgoraRoleWhiteboxTests {
    @Test func persistSessionRole_updatesDescriptorOnly() async throws {
        let id = SessionID()
        let descriptor = PersistedSessionDescriptor(
            id: id,
            kind: .claudeCode,
            workingDirectory: "/tmp",
            name: "Daisy",
            projectID: nil,
            startedAt: Date(timeIntervalSince1970: 1),
            command: "claude",
            args: [],
            env: [:],
            role: nil
        )
        let store = RoleSessionStore([descriptor])
        let coordinator = SessionPersistenceCoordinator(
            sessionStore: store,
            projectStore: NoOpProjectStore(),
            logError: { _, _ in }
        )
        coordinator.persistSession(descriptor)
        coordinator.persistSessionRole(id: id, role: "批判者")
        await coordinator.waitForPendingWrites()

        let saved = await store.load()
        let updated = try #require(saved.first { $0.id == id })
        #expect(updated.role == "批判者")
        #expect(updated.name == "Daisy")
    }

    @MainActor
    private final class SpawnRoleDashboardStub: ControlActionDashboard {
        var controlSessionSummaries: [ControlSessionSummary] = []
        var spawnResult: Result<SessionID, any Error> = .success(SessionID())
        private(set) var persistedRoles: [(SessionID, String)] = []

        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?
        ) async throws -> SessionID {
            try spawnResult.get()
        }

        func persistSessionRole(id: SessionID, role: String) {
            persistedRoles.append((id, role))
        }

        func sendMessage(
            to recipient: Recipient,
            text: String,
            submit: Bool,
            from: SessionID?,
            inReplyTo: UUID?,
            images: [ControlImageAttachment]
        ) async -> DashboardViewModel.SendOutcome { .sent }
        func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { true }
        func removeSession(_ id: SessionID) async -> Bool { true }
        func renameSession(_ id: SessionID, to name: String) {}
        func sessionOutput(for id: SessionID) -> String? { nil }
        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? { nil }
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .notFound }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
        func waitUntilDone(
            for id: SessionID,
            timeout: Duration,
            sentinel: String?
        ) async -> DashboardViewModel.DoneResult { .done(output: "") }
        func listApprovals() async -> [ApprovalDTO] { [] }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
    }

    @Test func handleSpawn_persistsRoleWhenTaskLocalSet() async throws {
        let dashboard = SpawnRoleDashboardStub()
        let id = SessionID()
        dashboard.spawnResult = .success(id)
        let handler = ControlActionHandler()
        handler.dashboard = dashboard

        let response = await ControlSpawnContext.$role.withValue("推進者") {
            await handler.handle(ControlRequest(
                requester: nil,
                action: .spawn(ref: .builtin(.claudeCode), backend: .pty, workingDirectory: nil)
            ))
        }

        #expect(response.statusCode == 201)
        #expect(dashboard.persistedRoles.count == 1)
        #expect(dashboard.persistedRoles[0].0 == id)
        #expect(dashboard.persistedRoles[0].1 == "推進者")
    }
}
