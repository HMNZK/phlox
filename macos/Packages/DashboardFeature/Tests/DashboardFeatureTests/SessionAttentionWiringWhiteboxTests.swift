import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

@Suite("SessionAttention wiring whitebox (task-2)")
struct SessionAttentionWiringWhiteboxTests {
    @Test @MainActor
    func hasAttention_detectsAwaitingApprovalAfterMarkCompletionSeen() async throws {
        let ptyManager = MockPTYManager()
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
        let sessionID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )
        let vm = try #require(dashboard.sessions.first { $0.id == sessionID })

        hookContinuation.yield((sessionID, .notification(message: "Approve?")))
        try await waitUntil {
            if case .awaitingApproval = vm.status { return true }
            return false
        }

        let node = try #require(dashboard.sessionNode(id: sessionID))
        node.markCompletionSeen()

        #expect(vm.hasUnseenCompletion == false)
        #expect(dashboard.hasUnseenCompletion(in: projectID) == false)
        #expect(dashboard.requiresAttention(for: node))
        #expect(dashboard.hasAttention(in: projectID))
    }

    @Test @MainActor
    func hasAttention_usesUnseenCompletionWhenNotAwaiting() async throws {
        let ptyManager = MockPTYManager()
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
        let sessionID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )
        let vm = try #require(dashboard.sessions.first { $0.id == sessionID })
        vm.hasUnseenCompletion = true

        #expect(dashboard.hasAttention(in: projectID))
    }
}
