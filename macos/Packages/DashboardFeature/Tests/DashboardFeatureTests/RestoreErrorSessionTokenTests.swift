import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite(.serialized)
struct RestoreErrorSessionTokenTests {
    @Test @MainActor
    func restoreFailurePlaceholderSpawn_injectsRuntimePHLOXToken() async throws {
        let descriptor = makeCustomAgentDescriptor()
        let catalog = AgentCatalog(customDescriptors: [descriptor])
        let sessionID = SessionID()
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

        let persisted = PersistedSessionDescriptor(
            id: sessionID,
            agentRef: descriptor.ref,
            workingDirectory: workspaceURL.path,
            name: "Broken Restore",
            projectID: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            command: "/opt/homebrew/bin/aider",
            args: ["--model", "sonnet"],
            env: [
                "PATH": "/persisted/bin",
                "PHLOX_API_URL": "http://127.0.0.1:9999",
                "PHLOX_SESSION_ID": sessionID.rawValue.uuidString,
            ],
            token: nil
        )
        let sessionStore = InMemorySessionStore([persisted])
        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            sessions: sessionStore,
            workspaceDirectory: workspaceURL,
            customAgentBinaryPaths: [:],
            agentCatalog: catalog
        )
        let dashboard = DashboardViewModel(environment: environment)

        await dashboard.start()
        let vm = try #require(dashboard.sessions.first)
        #expect(vm.id == sessionID)

        await vm.spawnEager()

        let call = try #require(ptyManager.spawnCalls.first)
        let token = try #require(call.env["PHLOX_TOKEN"])
        #expect(!token.isEmpty)
        #expect(await environment.tokenStore.session(forToken: token) == sessionID)
    }
}
