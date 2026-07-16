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
    // 固定時計を注入し、上限までの spawn 全てが同一の 1 秒窓に入ることを保証する（実時計依存の除去）。
    let dashboard = DashboardViewModel(
        environment: environment,
        rateLimitNow: { Date(timeIntervalSince1970: 1_800_000_000) }
    )
    await dashboard.start()

    let requesterID = try await dashboard.spawnNewSession(kind: .claudeCode)
    for _ in 0..<DashboardViewModel.maxAPISpawnCountPerSecond {
        try await dashboard.spawnNewSession(kind: .claudeCode, from: requesterID)
    }

    await #expect(throws: AgentSpawnError.spawnRateLimited) {
        try await dashboard.spawnNewSession(kind: .claudeCode, from: requesterID)
    }
}
