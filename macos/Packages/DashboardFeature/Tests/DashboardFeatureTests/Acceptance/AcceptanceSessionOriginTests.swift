import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-2 の受け入れテスト（不変・実装役は編集禁止）。
///
/// 契約: Control API 経由の spawn において、
/// **`from`（要求元）と「セッションツリーの親」を分離する**。
/// 親リンクは**実在するセッションにしか張らない**。
///
/// 背景（`docs/phase0.md` §2）: iPhone アプリからの spawn は、モバイルトークンに紐づく
/// 「実在しないセッション ID」を親として書き込むため、生成された瞬間に孤児になり、
/// `.orchestration` として全サーフェスから除外され、UI から到達できなくなっていた。
struct AcceptanceSessionOriginTests {

    private static let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - 純粋関数（App ターゲット外に切り出された分類ロジック）

    /// 要求元が実在するセッションなら、従来どおり内部サブセッション扱い。
    @Test func origin_existingRequester_isOrchestrationChild() {
        let requester = SessionID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let origin = SessionOriginPolicy.origin(requester: requester, requesterIsExistingSession: true)

        #expect(origin.launchContext == .orchestration)
        #expect(origin.parentSessionID == requester)
    }

    /// 要求元が実在しないセッション ID（＝モバイルトークンの合成 requester）なら、
    /// リモートのユーザーが起動したセッションであり、**親リンクは張らない**。
    @Test func origin_nonExistingRequester_isRemoteUserRoot() {
        let requester = SessionID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let origin = SessionOriginPolicy.origin(requester: requester, requesterIsExistingSession: false)

        #expect(origin.launchContext == .remoteUser)
        #expect(origin.parentSessionID == nil)
    }

    /// 要求元が特定できない場合も、孤児を作らない（親リンクを張らない）。
    @Test func origin_nilRequester_isRemoteUserRoot() {
        let origin = SessionOriginPolicy.origin(requester: nil, requesterIsExistingSession: false)

        #expect(origin.launchContext == .remoteUser)
        #expect(origin.parentSessionID == nil)
    }

    // MARK: - 区分ごとのポリシー

    /// `.remoteUser` は「ユーザーが起動したセッション」なので UI に出る。
    @Test func remoteUser_isVisibleLikeInteractive() {
        #expect(DashboardViewModel.isVisibleInGrid(launchContext: .remoteUser))
        #expect(DashboardViewModel.isVisibleInGrid(launchContext: .interactive))
        #expect(!DashboardViewModel.isVisibleInGrid(launchContext: .orchestration))
    }

    /// `.remoteUser` はユーザー本人の起動なので、CLI 内部サブセッション向けの
    /// 緩いポリシー（承認しない・フルアクセス）を継承してはならない。
    @Test func remoteUser_usesInteractiveApprovalAndSandboxPolicies() {
        #expect(
            SessionSpawnService.appServerApprovalPolicy(for: .remoteUser)
                == SessionSpawnService.appServerApprovalPolicy(for: .interactive)
        )
        #expect(
            SessionSpawnService.appServerSandboxPolicy(for: .remoteUser)
                == SessionSpawnService.appServerSandboxPolicy(for: .interactive)
        )
        #expect(
            SessionSpawnService.appServerApprovalPolicy(for: .remoteUser)
                != SessionSpawnService.appServerApprovalPolicy(for: .orchestration)
        )
        #expect(
            SessionSpawnService.appServerSandboxPolicy(for: .remoteUser)
                != SessionSpawnService.appServerSandboxPolicy(for: .orchestration)
        )
    }

    /// 永続化の往復で `.remoteUser` が保たれる。
    @Test func remoteUser_survivesPersistenceRoundTrip() throws {
        let descriptor = PersistedSessionDescriptor(
            id: SessionID(rawValue: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!),
            kind: .claudeCode,
            workingDirectory: "/tmp/remote-user",
            name: "Remote",
            projectID: nil,
            startedAt: Self.fixedNow,
            command: "claude",
            args: [],
            env: [:],
            launchContext: .remoteUser
        )
        let data = try JSONEncoder().encode(descriptor)
        let decoded = try JSONDecoder().decode(PersistedSessionDescriptor.self, from: data)

        #expect(decoded.launchContext == .remoteUser)
        #expect(decoded.parentSessionID == nil)
    }

    // MARK: - spawn 経路（DashboardViewModel）

    @MainActor
    private func makeDashboard(
        ptyManager: MockPTYManager
    ) -> DashboardViewModel {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
        return DashboardViewModel(
            environment: environment,
            rateLimitNow: { Self.fixedNow }
        )
    }

    /// 実在しない要求元からの Control API spawn は、
    /// 親を持たない `.remoteUser` セッションとして着地し、**グリッドに出る**。
    @Test @MainActor
    func controlAPISpawn_fromNonExistingRequester_landsVisibleWithoutParent() async throws {
        let ptyManager = MockPTYManager()
        let dashboard = makeDashboard(ptyManager: ptyManager)
        await dashboard.start()

        let phantomRequester = SessionID(
            rawValue: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        )
        let newID = try await dashboard.spawnNewSessionFromControlAPI(
            ref: .builtin(.claudeCode),
            requester: phantomRequester,
            backend: .pty,
            workingDirectory: nil,
            projectID: nil
        )

        let node = try #require(dashboard.sessionNode(id: newID))
        #expect(node.launchContext == .remoteUser)
        #expect(node.controllable.parentSessionID == nil)

        // 到達可能であること: トップレベルグリッドに現れる。
        #expect(dashboard.gridVisibleSessionNodes.contains { $0.id == newID })
    }

    /// 非退行: 実在する要求元からの Control API spawn は従来どおり
    /// 内部サブセッション（`.orchestration` かつ親リンクあり）として着地し、
    /// トップレベルグリッドには出ない（ADR 0027 の除外規則を維持）。
    @Test @MainActor
    func controlAPISpawn_fromExistingRequester_staysOrchestrationChild() async throws {
        let ptyManager = MockPTYManager()
        let dashboard = makeDashboard(ptyManager: ptyManager)
        await dashboard.start()

        let parentID = try await dashboard.spawnNewSession(kind: .claudeCode)
        let childID = try await dashboard.spawnNewSessionFromControlAPI(
            ref: .builtin(.claudeCode),
            requester: parentID,
            backend: .pty,
            workingDirectory: nil,
            projectID: nil
        )

        let child = try #require(dashboard.sessionNode(id: childID))
        #expect(child.launchContext == .orchestration)
        #expect(child.controllable.parentSessionID == parentID)
        #expect(!dashboard.gridVisibleSessionNodes.contains { $0.id == childID })
    }

    /// **回帰ガード（最重要）**: 親リンクを張らなくなっても、
    /// Control API spawn のレート制限は要求元ごとに従来どおり効く。
    ///
    /// `spawnNewSession` は `if let from { checkAPISpawnLimits(...) }` の形なので、
    /// 素朴に「親を nil にする」実装をすると上限検査ごと消える。
    @Test @MainActor
    func controlAPISpawn_fromNonExistingRequester_stillRateLimited() async throws {
        let ptyManager = MockPTYManager()
        let dashboard = makeDashboard(ptyManager: ptyManager)
        await dashboard.start()

        let phantomRequester = SessionID(
            rawValue: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        )

        // 固定時計なので全て同一ウィンドウに入る。上限（5/秒）までは通る。
        for _ in 0..<DashboardViewModel.maxAPISpawnCountPerSecond {
            _ = try await dashboard.spawnNewSessionFromControlAPI(
                ref: .builtin(.claudeCode),
                requester: phantomRequester,
                backend: .pty,
                workingDirectory: nil,
                projectID: nil
            )
        }

        await #expect(throws: AgentSpawnError.spawnRateLimited) {
            _ = try await dashboard.spawnNewSessionFromControlAPI(
                ref: .builtin(.claudeCode),
                requester: phantomRequester,
                backend: .pty,
                workingDirectory: nil,
                projectID: nil
            )
        }
    }
}
