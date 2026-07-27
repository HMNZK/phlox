import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-3 の受け入れテスト（不変・実装役は編集禁止）。
///
/// 契約: **「ユーザーへ通知する対象 ⊆ ユーザーが UI から到達して解消できる対象」**。
///
/// 到達可能性の正本は `SessionReachability` ただ1つとし、
/// ユーザーへの4つの出口（Dock バッジ件数・通知バナー・完了音・APNs）すべてが同じ述語を通る。
///
/// 背景（`docs/phase0.md` §1）: 既読化（`markCompletionSeen`）は「選択中セッション」でしか
/// 発火しないため、どのサーフェスにも現れないセッションが通知だけ出すと、
/// ユーザーには永久に解消できない要対応が積み上がる。
///
/// **検証範囲の限界（正直に明記する）**: バナーと完了音は `SessionCompletionNotifier` が
/// `Bundle.main.bundleURL.pathExtension == "app"` で早期 return するため、テストバンドルからは
/// 観測できない。したがって本テストが直接観測するのは「バッジ件数」「APNs」「ゲートの判定」であり、
/// バナー・完了音については **「4出口が単一のゲートの内側にあること」を実装契約として要求し、
/// レビューで構造的に確認する**（`tasks/task-3.md` のレビュー観点）。
struct AcceptanceNotificationReachabilityTests {

    // MARK: - 1. 到達可能性の正本（純粋述語）

    /// 到達可能 ＝ 3つの表示サーフェスのいずれかに現れること。
    /// 現在のサーフェス規則（ADR 0027）では、
    /// 「トップレベルグリッドに出る（`.orchestration` 以外）」か
    /// 「ワークスペース絞り込みグリッドに出る（`projectID` を持つ）」かの論理和になる。
    @Test func reachability_truthTable() {
        // ユーザーが起動したセッションは、ワークスペース未設定でもトップレベルグリッドに出る。
        #expect(SessionReachability.isReachable(launchContext: .interactive, projectID: nil))
        #expect(SessionReachability.isReachable(launchContext: .remoteUser, projectID: nil))

        // CLI 内部のサブセッションでも、ワークスペース配下ならその絞り込みグリッドから到達できる。
        #expect(SessionReachability.isReachable(launchContext: .orchestration, projectID: ProjectID()))

        // どのサーフェスにも現れない唯一の組み合わせ。今回のバグの本体。
        #expect(!SessionReachability.isReachable(launchContext: .orchestration, projectID: nil))
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
                    launchContext: node.launchContext,
                    projectID: node.projectID
                ) == surfaceIDs.contains(node.id),
                "到達可能性の述語が実サーフェスと食い違う: \(node.id)"
            )
            #expect(dashboard.isReachableFromUI(node.id) == surfaceIDs.contains(node.id))
        }
    }

    /// ハザード2（spawn 途中の判定タイミング）: 未登録セッションは「到達可能」に倒す。
    /// ここを fail-closed にすると、登録前に完了した通知が黙って落ちる（症状の出ない回帰）。
    @Test @MainActor
    func reachability_unregisteredSessionFailsOpen() async throws {
        let dashboard = makeDashboard()
        await dashboard.start()

        #expect(dashboard.isReachableFromUI(SessionID()))
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
    /// 到達不能なセッションでだけ「通知しない」を返す。
    @Test @MainActor
    func notificationGate_isWiredForEverySessionAndReflectsReachability() async throws {
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

        #expect(unreachableGate() == false)
        #expect(reachableGate() == true)
    }

    // MARK: - 4. 実際の通知経路（PTY 完了 / Chat 承認待ち）

    /// PTY セッションのターン完了で、到達不能なセッションの APNs 通知が出ない。
    /// 到達可能なセッションは従来どおり1回出る。
    ///
    /// 「出ない」の観測を偽陽性にしないため、**到達不能側のラッチ成立を先に待つ**。
    /// ラッチは通知と同じ関数の中で通知より先に立つので、
    /// ラッチ済み ⇒ その完了経路は通知判定まで到達済み、と言える。
    @Test @MainActor
    func remoteNotification_suppressedForUnreachablePTYCompletion() async throws {
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

        // ADR 0111 非退行: 通知は抑止しても、ラッチと赤表示の導出は変えない。
        let unreachableNode = try #require(dashboard.sessionNode(id: unreachableID))
        #expect(dashboard.requiresAttention(for: unreachableNode))

        #expect(spy.sessionCompletedIDs.isEmpty)

        hookContinuation.yield((reachableID, .userPromptSubmit(turnId: nil)))
        try await waitUntil { reachable.status == .running }
        hookContinuation.yield((reachableID, .stop(turnId: nil)))
        try await waitUntil { reachable.hasUnseenCompletion }

        #expect(spy.sessionCompletedIDs == [reachableID.description])
    }

    /// Chat（app-server）セッションの承認待ちでも、同じ述語で抑止される。
    /// 完了とは別系統の出口（`notifyAwaitingInput` / `approvalPending`）を塞ぎ忘れないための回帰ガード。
    @Test @MainActor
    func remoteNotification_suppressedForUnreachableChatApprovalPending() async throws {
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
        #expect(spy.approvalPendingIDs.isEmpty)
        // 抑止しても要対応状態そのものは立つ（ADR 0111 非退行）。
        #expect(unreachable.hasUnseenCompletion)

        reachable.enterAwaitingApproval(prompt: "Approve?")
        #expect(spy.approvalPendingIDs == [reachableID.description])

        // 到達不能側はバッジにも載らない。
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
