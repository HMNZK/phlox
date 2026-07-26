import Foundation
import XCTest
@testable import PhloxCore

final class ConnectingStateWhiteboxTests: XCTestCase {
    func testUnknownRefreshesWithoutEmittingOfflineBeforeTimeout() async throws {
        let api = CountingAPI()
        let reachability = RefreshCountingReachability()
        let repository = SessionRepository(
            api: api,
            reachability: reachability,
            unknownTimeout: .seconds(1)
        )
        let states = StateRecorder()

        let task = Task {
            for await state in repository.sessionStream(interval: .milliseconds(10)) {
                await states.append(state)
            }
        }
        try await Task.sleep(for: .milliseconds(80))
        task.cancel()

        let containsOffline = await states.containsOffline()
        let refreshCount = await reachability.refreshCount
        let apiCallCount = await api.callCount
        XCTAssertFalse(containsOffline)
        XCTAssertGreaterThanOrEqual(refreshCount, 1)
        XCTAssertEqual(apiCallCount, 0)
    }

    func testUnknownEmitsOfflineAfterInjectedTimeout() async throws {
        let repository = SessionRepository(
            api: CountingAPI(),
            reachability: RefreshCountingReachability(),
            unknownTimeout: .milliseconds(30)
        )
        let state = try await firstState(
            from: repository.sessionStream(interval: .milliseconds(5)),
            matching: { $0 == .offline },
            deadline: .seconds(1)
        )

        XCTAssertEqual(state, .offline)
    }

    private func firstState(
        from stream: AsyncStream<SessionsState>,
        matching predicate: @escaping @Sendable (SessionsState) -> Bool,
        deadline: Duration
    ) async throws -> SessionsState? {
        let result = FirstStateResult()
        let consumer = Task {
            for await state in stream where predicate(state) {
                await result.set(state)
                break
            }
        }
        try await Task.sleep(for: deadline)
        consumer.cancel()
        await consumer.value
        return await result.value
    }
}

private actor FirstStateResult {
    private(set) var value: SessionsState?

    func set(_ state: SessionsState) {
        value = state
    }
}

private actor CountingAPI: PhloxAPI {
    private(set) var callCount = 0

    func listSessions() async throws -> [Session] {
        callCount += 1
        return []
    }

    func spawn(_ request: SpawnRequest) async throws -> Session { throw PhloxError.notFound }
    func waitUntilReady(sessionID: String) async throws -> Bool { true }
    func send(_ request: SendRequest) async throws -> SendResult { SendResult(accepted: true) }
    func output(sessionID: String) async throws -> String { "" }
    func messages(sessionID: String) async throws -> [ChatMessage] { [] }
    func remove(sessionID: String) async throws {}
    func approvals() async throws -> [Approval] { [] }
    func respond(approvalID: String, decision: ApprovalDecision) async throws {}
}

private actor RefreshCountingReachability: ReachabilityMonitoring {
    private(set) var refreshCount = 0

    var current: Reachability { .unknown }

    func refresh() async {
        refreshCount += 1
    }

    nonisolated func stream() -> AsyncStream<Reachability> {
        AsyncStream { continuation in
            continuation.yield(.unknown)
            continuation.finish()
        }
    }
}

private actor StateRecorder {
    private var states: [SessionsState] = []

    func append(_ state: SessionsState) {
        states.append(state)
    }

    func containsOffline() -> Bool {
        states.contains(.offline)
    }
}
