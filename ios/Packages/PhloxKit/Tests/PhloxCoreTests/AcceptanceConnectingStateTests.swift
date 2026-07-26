import XCTest
@testable import PhloxCore

/// task-1 受け入れテスト（PM 著・**実装役は編集禁止**）。
///
/// 凍結する契約:
///  1. 到達性が未判定（`.unknown`）の間は `.offline` を流さない。
///  2. 未判定の間は能動的に再判定を試みる（`ReachabilityMonitoring.refresh()` を呼ぶ）。
///  3. 判定が失敗（`.unreachableHost` / `.offlineNetwork`）に確定したときだけ `.offline` を流す。
///  4. 未判定が `unknownTimeout` を超えたら `.offline` へ倒す（永久スピナー禁止・ADR 0021 の最優先規則）。
///  5. `.online` の既存挙動（API を叩いて `.loaded`）を壊さない。
///
/// 実装役が満たすべき公開面（この契約に合わせて実装すること）:
/// ```swift
/// public extension SessionRepository {
///     static var defaultUnknownTimeout: Duration { get }   // 既定 20 秒（PairingConnectGate と同値）
/// }
/// public init(api: PhloxAPI, reachability: ReachabilityMonitoring, unknownTimeout: Duration = SessionRepository.defaultUnknownTimeout)
/// ```
final class AcceptanceConnectingStateTests: XCTestCase {

    private func makeSession(_ id: String) -> Session {
        Session(
            id: id,
            name: id,
            agent: .claudeCode,
            status: .idle,
            subtitle: "",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// 契約1・2: 未判定の間は `.offline` を流さず、能動的に再判定を試みる。API も叩かない。
    func testUnknownNeverEmitsOfflineAndTriggersRefresh() async throws {
        let api = StubSessionsAPI(sessions: [makeSession("s1")])
        let reachability = MutableReachability(.unknown) // ずっと未判定のまま
        let repo = SessionRepository(
            api: api,
            reachability: reachability,
            unknownTimeout: .seconds(60) // タイムアウトは観測窓より十分先に置く
        )
        let box = StateBox()

        let task = Task {
            for await state in repo.sessionStream(interval: .milliseconds(20)) {
                await box.append(state)
            }
        }
        try await Task.sleep(for: .milliseconds(400))
        task.cancel()

        let seen = await box.seen
        XCTAssertFalse(
            seen.contains(.offline),
            "未判定（.unknown）の間は .offline を流してはならない。観測: \(seen)"
        )
        let refreshCount = await reachability.refreshCount
        XCTAssertGreaterThanOrEqual(
            refreshCount,
            1,
            "未判定の間は能動的に再判定（refresh）を試みる（NWPathMonitor のコールバック待ちで止まらない）"
        )
        let apiCalls = await api.callCount
        XCTAssertEqual(apiCalls, 0, "未判定の間はセッション一覧 API を叩かない")
    }

    /// 契約3: 再判定でホスト到達不能が確定したら `.offline` を流す。
    func testOfflineEmittedOnlyAfterHealthCheckFails() async throws {
        let api = StubSessionsAPI(sessions: [makeSession("s1")])
        let reachability = MutableReachability(.unknown, afterRefresh: .unreachableHost)
        let repo = SessionRepository(
            api: api,
            reachability: reachability,
            unknownTimeout: .seconds(60) // タイムアウトではなく「判定失敗」で倒れることを見る
        )

        let sawOffline = await Self.waitForState(
            repo: repo,
            interval: .milliseconds(20),
            deadline: .milliseconds(2000)
        ) { $0 == .offline }

        XCTAssertTrue(sawOffline, "ヘルスチェックが実際に失敗したら .offline を流す")
    }

    /// 契約3: ネットワーク自体が落ちている場合も `.offline` を流す。
    func testOfflineEmittedWhenNetworkIsDown() async throws {
        let api = StubSessionsAPI(sessions: [makeSession("s1")])
        let reachability = MutableReachability(.unknown, afterRefresh: .offlineNetwork)
        let repo = SessionRepository(
            api: api,
            reachability: reachability,
            unknownTimeout: .seconds(60)
        )

        let sawOffline = await Self.waitForState(
            repo: repo,
            interval: .milliseconds(20),
            deadline: .milliseconds(2000)
        ) { $0 == .offline }

        XCTAssertTrue(sawOffline, "ネットワーク断が確定したら .offline を流す")
    }

    /// 契約4: 未判定が解消しないまま閾値を超えたら `.offline` へ倒す（永久スピナー禁止）。
    func testUnknownTimesOutToOffline() async throws {
        let api = StubSessionsAPI(sessions: [makeSession("s1")])
        let reachability = MutableReachability(.unknown) // 永久に未判定
        let repo = SessionRepository(
            api: api,
            reachability: reachability,
            unknownTimeout: .milliseconds(150)
        )

        let sawOffline = await Self.waitForState(
            repo: repo,
            interval: .milliseconds(20),
            deadline: .milliseconds(3000)
        ) { $0 == .offline }

        XCTAssertTrue(
            sawOffline,
            "未判定が unknownTimeout を超えたら .offline へ倒す（無限スピナーは ADR 0021 で禁止）"
        )
    }

    /// 契約4: 既定のタイムアウト値が定義されており、無限ではない。
    func testDefaultUnknownTimeoutIsFinite() {
        XCTAssertTrue(
            SessionRepository.defaultUnknownTimeout > .zero,
            "既定の未判定タイムアウトが正の有限値として定義されていること"
        )
        XCTAssertLessThanOrEqual(
            SessionRepository.defaultUnknownTimeout,
            .seconds(30),
            "既定タイムアウトは 30 秒以内（PairingConnectGate の 20 秒に揃える）"
        )
    }

    /// 契約5: `.online` の既存挙動を壊さない。
    func testOnlineStillLoadsSessions() async throws {
        let api = StubSessionsAPI(sessions: [makeSession("s1")])
        let repo = SessionRepository(
            api: api,
            reachability: MutableReachability(.online),
            unknownTimeout: .seconds(60)
        )

        let sawLoaded = await Self.waitForState(
            repo: repo,
            interval: .milliseconds(20),
            deadline: .milliseconds(2000)
        ) { state in
            if case .loaded = state { return true }
            return false
        }

        XCTAssertTrue(sawLoaded, ".online では従来どおり API を叩いて .loaded を流す")
    }

    // MARK: - helpers

    /// `predicate` を満たす状態が deadline 以内に流れたら true。
    private static func waitForState(
        repo: SessionRepository,
        interval: Duration,
        deadline: Duration,
        _ predicate: @escaping @Sendable (SessionsState) -> Bool
    ) async -> Bool {
        let hit = HitBox()
        let task = Task {
            for await state in repo.sessionStream(interval: interval) {
                if predicate(state) {
                    await hit.mark()
                    break
                }
            }
        }
        let waiter = Task {
            try? await Task.sleep(for: deadline)
        }
        _ = await waiter.value
        task.cancel()
        return await hit.value
    }
}

// MARK: - stubs（受け入れテスト専用。実装役は編集しない）

/// 到達性を後から変えられるテスト用モニタ。`refresh()` の呼び出し回数を数える。
private actor MutableReachability: ReachabilityMonitoring {
    private var value: Reachability
    private let afterRefresh: Reachability?
    private(set) var refreshCount = 0

    init(_ initial: Reachability, afterRefresh: Reachability? = nil) {
        self.value = initial
        self.afterRefresh = afterRefresh
    }

    var current: Reachability { value }

    func refresh() async {
        refreshCount += 1
        if let afterRefresh {
            value = afterRefresh
        }
    }

    func stream() -> AsyncStream<Reachability> {
        let snapshot = value
        return AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }
}

/// listSessions の呼び出し回数を数えるだけの API スタブ。
private actor StubSessionsAPI: PhloxAPI {
    let sessions: [Session]
    private(set) var callCount = 0

    init(sessions: [Session]) {
        self.sessions = sessions
    }

    func listSessions() async throws -> [Session] {
        callCount += 1
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

private actor StateBox {
    private(set) var seen: [SessionsState] = []
    func append(_ state: SessionsState) { seen.append(state) }
}

private actor HitBox {
    private(set) var value = false
    func mark() { value = true }
}
