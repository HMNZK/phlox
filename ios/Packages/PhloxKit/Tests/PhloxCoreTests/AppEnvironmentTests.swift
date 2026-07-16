import XCTest
@testable import PhloxCore

// E1-2 検証。Composition Root（AppEnvironment）と DI シーム（6 プロトコル）の配線を検証する。
//
// `AppEnvironment.stub` がインメモリ実装で 6 依存すべてを配線していること、各スタブが
// 期待どおり動作する（空 init でない）ことを確認する。live（App ターゲット）は別ターゲットの
// ため本テストでは扱わず、live/stub の同一プロトコル準拠はコンパイル時に保証される。
final class AppEnvironmentTests: XCTestCase {

    func testStubWiresAllSixDependencies() async {
        let env = AppEnvironment.stub()
        // 6 依存はプロトコル型の非 Optional `let` のため型レベルで配線が保証される。
        // ここでは各スタブの基本動作で「実体が配線済み」であることを確認する。
        let allowed = try? await env.authenticator.authenticate(reason: "test")
        XCTAssertEqual(allowed, true)
        let reachable = await env.reachability.current
        XCTAssertEqual(reachable, .online)
    }

    func testStubTokenStoreRoundTrips() async throws {
        let env = AppEnvironment.stub()
        let initial = try await env.tokenStore.load()
        XCTAssertNil(initial)

        try await env.tokenStore.save("secret-token")
        let loaded = try await env.tokenStore.load()
        XCTAssertEqual(loaded, "secret-token")

        try await env.tokenStore.delete()
        let afterDelete = try await env.tokenStore.load()
        XCTAssertNil(afterDelete)
    }

    func testStubAPIClientReturnsSeededSessionsAndApprovals() async throws {
        let session = Session(
            id: "s1", name: "Rose", agent: .claudeCode,
            status: .running, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0)
        )
        let approval = Approval(id: "a1", sessionID: "s1", kind: .claudeCode, prompt: "approve?")
        let env = AppEnvironment.stub(sessions: [session], approvals: [approval])

        let sessions = try await env.apiClient.listSessions()
        XCTAssertEqual(sessions, [session])

        let approvals = try await env.apiClient.approvals()
        XCTAssertEqual(approvals, [approval])
    }

    func testStubAPIClientSpawnReturnsSessionForRequestedAgent() async throws {
        let env = AppEnvironment.stub()
        let spawned = try await env.apiClient.spawn(SpawnRequest(agent: .codex, workspace: "my-project"))
        XCTAssertEqual(spawned.agent, .codex)
        XCTAssertEqual(spawned.status, .starting)
        XCTAssertEqual(spawned.subtitle, "my-project")
    }

    func testStubSessionRepositoryYieldsSnapshotOnce() async {
        let session = Session(
            id: "s2", name: "Tulip", agent: .cursor,
            status: .idle, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0)
        )
        let env = AppEnvironment.stub(sessions: [session])

        var received: [SessionsState] = []
        for await state in env.sessionRepository.sessionStream(interval: .seconds(1)) {
            received.append(state)
        }
        XCTAssertEqual(received, [.loaded([session])])
    }

    func testStubAuditLogRecordsAndReturnsNewestFirst() async {
        let env = AppEnvironment.stub()
        let empty = await env.auditLog.recentEntries(limit: 10)
        XCTAssertTrue(empty.isEmpty)

        await env.auditLog.record(.approve(approvalID: "a1", decision: .accept))
        await env.auditLog.record(.remove(sessionID: "s1", cascadeCount: 2))

        let entries = await env.auditLog.recentEntries(limit: 10)
        XCTAssertEqual(entries.map(\.operation), ["remove", "approve"])
    }

    func testStubAuthenticatorCanDeny() async throws {
        // スタブは allows パラメータで拒否も表現でき、起動ゲートの失敗系 Preview に使える。
        let denying = StubAuthenticator(allows: false)
        let result = try await denying.authenticate(reason: "test")
        XCTAssertFalse(result)
    }
}
