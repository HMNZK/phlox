import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-3 の受け入れテスト（不変・実装役は編集禁止）。
///
/// 契約: **「あるクライアントへ通知する対象 ⊆ そのクライアントから到達して解消できる対象」**。
///
/// 到達可能性の正本は `SessionReachability` ただ1つとし、ユーザーへの4つの出口
/// （Dock バッジ件数・通知バナー・完了音・APNs）が、**それぞれの届け先の**到達可能性で抑止される。
///
/// | 出口 | 届け先 | ゲート |
/// |---|---|---|
/// | Dock バッジ件数 | macOS | `.desktop` |
/// | 通知バナー | macOS | `.desktop` |
/// | 完了音 | macOS | `.desktop` |
/// | APNs | iPhone | `.mobile`（モバイル一覧は無フィルタ＝現状は常に到達可能） |
///
/// 背景（`docs/phase0.md` §1）: 既読化（`markCompletionSeen`）は macOS の「選択中セッション」でしか
/// 発火しないため、どの macOS サーフェスにも現れないセッションが通知だけ出すと、
/// ユーザーには永久に解消できない要対応が積み上がる。
/// 一方で iPhone は全セッションを一覧・オープンできるので、APNs を macOS 基準で塞ぐのは
/// 過剰抑止（＝通知が黙って落ちる回帰）になる。だからクライアントごとに判定する。
///
/// **検証範囲の限界（正直に明記する）**: バナーと完了音は `SessionCompletionNotifier` が
/// `Bundle.main.bundleURL.pathExtension == "app"` で早期 return するため、テストバンドルからは
/// 観測できない。したがって本テストが直接観測するのは「バッジ件数」「APNs」「ゲートの判定」であり、
/// バナー・完了音については **「同一チャネルの出口が単一のゲートの内側にあること」を実装契約として
/// 要求し、レビューで構造的に確認する**（`tasks/task-3.md` のレビュー観点）。
struct AcceptanceNotificationReachabilityTests {

    // MARK: - 1. 到達可能性の正本（純粋述語）

    /// macOS の到達可能 ＝ 3つの表示サーフェスのいずれかに現れること。
    /// 現在のサーフェス規則（ADR 0027）では、
    /// 「トップレベルグリッドに出る（`.orchestration` 以外）」か
    /// 「ワークスペース絞り込みグリッドに出る（`projectID` を持つ）」かの論理和になる。
    @Test func reachability_desktopTruthTable() {
        // ユーザーが起動したセッションは、ワークスペース未設定でもトップレベルグリッドに出る。
        #expect(SessionReachability.isReachable(from: .desktop, launchContext: .interactive, projectID: nil))
        #expect(SessionReachability.isReachable(from: .desktop, launchContext: .remoteUser, projectID: nil))

        // CLI 内部のサブセッションでも、ワークスペース配下ならその絞り込みグリッドから到達できる。
        #expect(SessionReachability.isReachable(from: .desktop, launchContext: .orchestration, projectID: ProjectID()))

        // どの macOS サーフェスにも現れない唯一の組み合わせ。今回のバグの本体。
        #expect(!SessionReachability.isReachable(from: .desktop, launchContext: .orchestration, projectID: nil))
    }

    /// iPhone アプリの一覧（`controlSessionSummaries`）は `launchContext` で絞り込まず
    /// 全セッションを返すため、**モバイルからは全てが到達可能**。
    /// ここを macOS 基準にすると、iPhone から開けるセッションの push が消える（過剰抑止）。
    @Test func reachability_mobileReachesEverySession() {
        #expect(SessionReachability.isReachable(from: .mobile, launchContext: .interactive, projectID: nil))
        #expect(SessionReachability.isReachable(from: .mobile, launchContext: .remoteUser, projectID: nil))
        #expect(SessionReachability.isReachable(from: .mobile, launchContext: .orchestration, projectID: ProjectID()))
        #expect(SessionReachability.isReachable(from: .mobile, launchContext: .orchestration, projectID: nil))
    }

    /// 述語が、実際の表示サーフェスの和集合と一致する。
    /// サーフェス側の規則が将来変わったとき、述語だけが取り残されるのを防ぐ回帰ガード。
    @Test @MainActor
    func reachability_matchesActualSurfaces() async throws {
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let dashboard = makeDashboard(workspaceDirectory: workspaceURL)
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))

        let inWorkspaceVisible = try await dashboard.spawnNewSession(
            kind: .claudeCode, projectID: projectID, launchContext: .interactive
        )
        let inWorkspaceOrchestration = try await dashboard.spawnNewSession(
            kind: .claudeCode, projectID: projectID, launchContext: .orchestration
        )
        let rootlessVisible = try await dashboard.spawnNewSession(
            kind: .claudeCode, launchContext: .interactive
        )
        let rootlessRemoteUser = try await dashboard.spawnNewSession(
            kind: .claudeCode, launchContext: .remoteUser
        )
        let rootlessOrchestration = try await dashboard.spawnNewSession(
            kind: .claudeCode, launchContext: .orchestration
        )

        // 実サーフェスの和集合を、テスト側で独立に計算する（実装の述語を使わない）。
        var surfaceIDs = Set(dashboard.gridVisibleSessionNodes.map(\.id))
        for project in dashboard.projects {
            surfaceIDs.formUnion(dashboard.gridSessionNodes(in: project.id).map(\.id))
            surfaceIDs.formUnion(flattenSessionTreeIDs(dashboard.sessionForest(in: project.id)))
        }

        #expect(surfaceIDs.contains(inWorkspaceVisible))
        #expect(surfaceIDs.contains(inWorkspaceOrchestration))
        #expect(surfaceIDs.contains(rootlessVisible))
        #expect(surfaceIDs.contains(rootlessRemoteUser))
        #expect(!surfaceIDs.contains(rootlessOrchestration))

        // 述語と実サーフェスが全セッションで一致する。
        for node in dashboard.sessionNodes {
            #expect(
                SessionReachability.isReachable(
                    from: .desktop,
                    launchContext: node.launchContext,
                    projectID: node.projectID
                ) == surfaceIDs.contains(node.id),
                "到達可能性の述語が実サーフェスと食い違う: \(node.id)"
            )
            #expect(dashboard.isReachableFromUI(node.id, from: .desktop) == surfaceIDs.contains(node.id))

            // モバイル一覧は無フィルタ（全 sessionNodes を返す）＝全て到達可能。
            #expect(dashboard.isReachableFromUI(node.id, from: .mobile))
        }
    }

    /// ハザード2（spawn 途中の判定タイミング）: 未登録セッションは「到達可能」に倒す。
    /// ここを fail-closed にすると、登録前に完了した通知が黙って落ちる（症状の出ない回帰）。
    @Test @MainActor
    func reachability_unregisteredSessionFailsOpen() async throws {
        let dashboard = makeDashboard()
        await dashboard.start()

        #expect(dashboard.isReachableFromUI(SessionID(), from: .desktop))
        #expect(dashboard.isReachableFromUI(SessionID(), from: .mobile))
    }

    // MARK: - 2. Dock バッジ件数

    /// 到達不能なセッションがラッチしても、Dock バッジは増えない。
    /// 到達可能なセッションだけが数えられる。
    @Test @MainActor
    func badgeCount_excludesUnreachableSession() async throws {
        let dashboard = makeDashboard()
        await dashboard.start()

        var observedCounts: [Int] = []
        dashboard.unseenCompletionCountDidChange = { observedCounts.append($0) }

        let unreachableID = try await dashboard.spawnNewSession(
            kind: .claudeCode, launchContext: .orchestration
        )
        let reachableID = try await dashboard.spawnNewSession(
            kind: .claudeCode, launchContext: .interactive
        )
        let unreachable = try #require(dashboard.sessionNode(id: unreachableID)?.pty)
        let reachable = try #require(dashboard.sessionNode(id: reachableID)?.pty)

        #expect(dashboard.unseenCompletionCount == 0)

        unreachable.hasUnseenCompletion = true
        #expect(dashboard.unseenCompletionCount == 0)

        reachable.hasUnseenCompletion = true
        #expect(dashboard.unseenCompletionCount == 1)

        reachable.markCompletionSeen()
        #expect(dashboard.unseenCompletionCount == 0)

        // 値が変わったときだけ発火する既存契約を保つ（到達不能側の 0→0 は発火しない）。
        #expect(observedCounts == [1, 0])
    }

    /// 非退行（過剰抑止の防止）: ワークスペース配下の `.orchestration` 子は
    /// 絞り込みグリッドから到達できるので、従来どおりバッジに数える。
    @Test @MainActor
    func badgeCount_countsOrchestrationChildInsideWorkspace() async throws {
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let dashboard = makeDashboard(workspaceDirectory: workspaceURL)
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))

        let parentID = try await dashboard.spawnNewSession(
            kind: .claudeCode, projectID: projectID, launchContext: .interactive
        )
        let childID = try await dashboard.spawnNewSession(
            kind: .claudeCode, from: parentID, launchContext: .orchestration
        )
        let child = try #require(dashboard.sessionNode(id: childID)?.pty)

        child.hasUnseenCompletion = true
        #expect(dashboard.unseenCompletionCount == 1)
    }

    // MARK: - 3. 通知ゲートの注入

    /// ダッシュボードが登録した全セッションにゲートが入り、
    /// **チャネルごとに**正しい判定を返す。
    /// macOS から到達できないセッションでも、iPhone からは到達できるので remote は通す。
    @Test @MainActor
    func notificationGate_isWiredForEverySessionAndReflectsReachabilityPerChannel() async throws {
        let dashboard = makeDashboard()
        await dashboard.start()

        let unreachableID = try await dashboard.spawnNewSession(
            kind: .claudeCode, launchContext: .orchestration
        )
        let reachableID = try await dashboard.spawnNewSession(
            kind: .claudeCode, launchContext: .interactive
        )

        for node in dashboard.sessionNodes {
            #expect(node.controllable.userNotificationGate != nil, "ゲート未注入のセッションがある: \(node.id)")
        }

        let unreachableGate = try #require(dashboard.sessionNode(id: unreachableID)?.controllable.userNotificationGate)
        let reachableGate = try #require(dashboard.sessionNode(id: reachableID)?.controllable.userNotificationGate)

        // macOS の画面から辿れない → バナー・音は出さない。
        #expect(unreachableGate(.local) == false)
        // iPhone からは一覧に出て開ける → push は出す（過剰抑止をしない）。
        #expect(unreachableGate(.remote) == true)

        #expect(reachableGate(.local) == true)
        #expect(reachableGate(.remote) == true)
    }

    // MARK: - 4. 実際の通知経路（PTY 完了 / Chat 承認待ち）

    /// **過剰抑止の回帰ガード（最重要）**: PTY セッションのターン完了で、
    /// macOS の画面から辿れないセッションでも **APNs は出る**。
    /// iPhone はそのセッションを一覧に出して開けるので、push は行動可能な通知である。
    /// ここを macOS 基準で塞ぐと「iPhone から開けるのに通知が来ない」＝
    /// 症状の出ない通知欠落を作る。
    ///
    /// 同時に、macOS 側の蓄積面（Dock バッジ）は **数えない**ことを確認する
    /// （バッジは macOS でしか既読化できないため、辿れないセッションを数えると永久に消えない）。
    @Test @MainActor
    func pushNotification_firesEvenWhenDesktopUnreachable_whileBadgeDoesNotCount() async throws {
        let ptyManager = MockPTYManager()
        let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let spy = SpyRemoteSessionNotifier()

        let unreachableID = try await dashboard.spawnNewSession(
            kind: .claudeCode, launchContext: .orchestration
        )
        let reachableID = try await dashboard.spawnNewSession(
            kind: .claudeCode, launchContext: .interactive
        )
        let unreachable = try #require(dashboard.sessionNode(id: unreachableID)?.pty)
        let reachable = try #require(dashboard.sessionNode(id: reachableID)?.pty)
        unreachable.remoteSessionNotifier = spy
        reachable.remoteSessionNotifier = spy

        hookContinuation.yield((unreachableID, .userPromptSubmit(turnId: nil)))
        try await waitUntil { unreachable.status == .running }
        hookContinuation.yield((unreachableID, .stop(turnId: nil)))
        try await waitUntil { unreachable.hasUnseenCompletion }

        // ADR 0111 非退行: ラッチと赤表示の導出は変えない。
        let unreachableNode = try #require(dashboard.sessionNode(id: unreachableID))
        #expect(dashboard.requiresAttention(for: unreachableNode))

        // iPhone は到達できる → push は出す。
        #expect(spy.sessionCompletedIDs == [unreachableID.description])
        // macOS からは辿れない → Dock バッジには数えない。
        #expect(dashboard.unseenCompletionCount == 0)

        hookContinuation.yield((reachableID, .userPromptSubmit(turnId: nil)))
        try await waitUntil { reachable.status == .running }
        hookContinuation.yield((reachableID, .stop(turnId: nil)))
        try await waitUntil { reachable.hasUnseenCompletion }

        #expect(spy.sessionCompletedIDs == [unreachableID.description, reachableID.description])
        #expect(dashboard.unseenCompletionCount == 1)
    }

    /// Chat（app-server）セッションの承認待ちでも、チャネル別の判定が同じように効く。
    /// 完了とは別系統の出口（`notifyAwaitingInput` / `approvalPending`）を取りこぼさないための回帰ガード。
    @Test @MainActor
    func chatApprovalPending_pushFiresWhileBadgeRespectsDesktopReachability() async throws {
        let ptyManager = MockPTYManager()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: ptyManager,
            hookStream: hookStream,
            agentBinaryPaths: [.codex: "/usr/local/bin/codex"],
            appServerClientFactory: { _, _, _, _, _ in EventYieldingStructuredClient() }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let spy = SpyRemoteSessionNotifier()

        let unreachableID = try await dashboard.spawnNewSession(
            kind: .codex, backend: .appServer, launchContext: .orchestration
        )
        let reachableID = try await dashboard.spawnNewSession(
            kind: .codex, backend: .appServer, launchContext: .interactive
        )
        let unreachable = try #require(dashboard.sessionNode(id: unreachableID)?.appServer)
        let reachable = try #require(dashboard.sessionNode(id: reachableID)?.appServer)
        unreachable.remoteSessionNotifier = spy
        reachable.remoteSessionNotifier = spy

        unreachable.enterAwaitingApproval(prompt: "Approve?")
        // iPhone からは到達できる → push は出す。
        #expect(spy.approvalPendingIDs == [unreachableID.description])
        // 要対応状態そのものは立つ（ADR 0111 非退行）。
        #expect(unreachable.hasUnseenCompletion)
        // macOS からは辿れない → Dock バッジには載らない。
        #expect(dashboard.unseenCompletionCount == 0)

        reachable.enterAwaitingApproval(prompt: "Approve?")
        #expect(spy.approvalPendingIDs == [unreachableID.description, reachableID.description])
        #expect(dashboard.unseenCompletionCount == 1)
    }

    /// ゲート未注入（SessionFeature 単体利用・プレビュー）では既定で通知する。
    /// 既存挙動を壊さないことの保証。
    @Test @MainActor
    func notification_firesWhenGateIsNotInjected() async throws {
        let spy = SpyRemoteSessionNotifier()
        let sessionID = SessionID()
        let chat = ChatSessionViewModel(
            id: sessionID,
            agentRef: .builtin(.codex),
            client: EventYieldingStructuredClient(),
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-notification-reachability"
        )
        chat.remoteSessionNotifier = spy

        #expect(chat.userNotificationGate == nil)

        chat.enterAwaitingApproval(prompt: "Approve?")

        #expect(spy.approvalPendingIDs == [sessionID.description])
    }

    // MARK: - Helpers

    @MainActor
    private func makeDashboard(
        workspaceDirectory: URL = URL(fileURLWithPath: "/tmp/agent-dashboard-test-workspace")
    ) -> DashboardViewModel {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceDirectory
        )
        return DashboardViewModel(environment: environment)
    }

    private func flattenSessionTreeIDs(_ nodes: [SessionTreeNode]) -> [SessionID] {
        nodes.flatMap { [$0.id] + flattenSessionTreeIDs($0.children) }
    }
}

/// APNs 出口の観測用スパイ。
private final class SpyRemoteSessionNotifier: RemoteSessionNotifier, @unchecked Sendable {
    private let lock = NSLock()
    private var completed: [String] = []
    private var pending: [String] = []

    var sessionCompletedIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return completed
    }

    var approvalPendingIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return pending
    }

    func sessionCompleted(sessionId: String, sessionName: String) {
        lock.lock(); defer { lock.unlock() }
        completed.append(sessionId)
    }

    func approvalPending(sessionId: String, sessionName: String) {
        lock.lock(); defer { lock.unlock() }
        pending.append(sessionId)
    }
}
