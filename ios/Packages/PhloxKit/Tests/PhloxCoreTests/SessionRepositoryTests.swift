import XCTest
@testable import PhloxCore

// E3-5 検証。ポーリング駆動・オフライン停止・キャンセル終了を検証する。
final class SessionRepositoryTests: XCTestCase {

    private func makeSession(_ id: String) -> Session {
        Session(id: id, name: id, agent: .claudeCode, status: .idle, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0))
    }

    func testPollsRepeatedlyWhenOnline() async {
        let api = CountingAPI(sessions: [makeSession("s1")])
        let repo = SessionRepository(api: api, reachability: StubReachability(.online))

        var loadedCount = 0
        let stream = repo.sessionStream(interval: .milliseconds(20))
        for await state in stream {
            if case .loaded = state {
                loadedCount += 1
                if loadedCount >= 3 { break }
            }
        }
        XCTAssertGreaterThanOrEqual(loadedCount, 3, "online ではポーリングで繰り返し emit する")
        let calls = await api.callCount
        XCTAssertGreaterThanOrEqual(calls, 3)
    }

    func testOfflineEmitsOfflineAndDoesNotCallAPI() async {
        let api = CountingAPI(sessions: [makeSession("s1")])
        let repo = SessionRepository(api: api, reachability: StubReachability(.offlineNetwork))

        var sawOffline = false
        let stream = repo.sessionStream(interval: .milliseconds(20))
        for await state in stream {
            if state == .offline {
                sawOffline = true
                break
            }
        }
        XCTAssertTrue(sawOffline, "offline では .offline を流す")
        let calls = await api.callCount
        XCTAssertEqual(calls, 0, "offline ではポーリング（API 呼び出し）を停止する")
    }

    func testEmptyWhenNoSessions() async {
        let api = CountingAPI(sessions: [])
        let repo = SessionRepository(api: api, reachability: StubReachability(.online))

        var sawEmpty = false
        for await state in repo.sessionStream(interval: .milliseconds(20)) {
            if state == .empty { sawEmpty = true; break }
        }
        XCTAssertTrue(sawEmpty)
    }

    func testErrorStateOnAPIFailure() async {
        let api = CountingAPI(sessions: [], error: .unauthorized)
        let repo = SessionRepository(api: api, reachability: StubReachability(.online))

        var captured: PhloxError?
        for await state in repo.sessionStream(interval: .milliseconds(20)) {
            if case .error(let e) = state { captured = e; break }
        }
        XCTAssertEqual(captured, .unauthorized)
    }

    func testStreamTerminatesOnCancellation() async {
        let api = CountingAPI(sessions: [makeSession("s1")])
        let repo = SessionRepository(api: api, reachability: StubReachability(.online))

        let finished = expectation(description: "stream finished after cancel")
        let task = Task {
            for await _ in repo.sessionStream(interval: .milliseconds(20)) {
                // 1 つ受けたら離脱（タスクキャンセルで onTermination 発火）。
                break
            }
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 2.0)
        task.cancel()
    }
}

/// 呼び出し回数を数えるテスト用 PhloxAPI。listSessions のみ意味を持つ。
private actor CountingAPI: PhloxAPI {
    let sessions: [Session]
    let error: PhloxError?
    private(set) var callCount = 0

    init(sessions: [Session], error: PhloxError? = nil) {
        self.sessions = sessions
        self.error = error
    }

    func listSessions() async throws -> [Session] {
        callCount += 1
        if let error { throw error }
        return sessions
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
