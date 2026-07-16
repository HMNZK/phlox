import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - spawnNewSession limits

@Test @MainActor
func spawnNewSession_apiSpawnBeyondDepthLimitThrows() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    var parentID = try await dashboard.spawnNewSession(kind: .claudeCode)
    for _ in 0..<DashboardViewModel.maxAPISpawnDepth {
        parentID = try await dashboard.spawnNewSession(kind: .claudeCode, from: parentID)
    }

    await #expect(throws: AgentSpawnError.depthLimitExceeded) {
        try await dashboard.spawnNewSession(kind: .claudeCode, from: parentID)
    }
}

@Test @MainActor
func spawnNewSession_apiSpawnBeyondRateLimitThrows() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let requesterID = try await dashboard.spawnNewSession(kind: .claudeCode)
    for _ in 0..<DashboardViewModel.maxAPISpawnCountPerSecond {
        try await dashboard.spawnNewSession(kind: .claudeCode, from: requesterID)
    }

    await #expect(throws: AgentSpawnError.spawnRateLimited) {
        try await dashboard.spawnNewSession(kind: .claudeCode, from: requesterID)
    }
}
