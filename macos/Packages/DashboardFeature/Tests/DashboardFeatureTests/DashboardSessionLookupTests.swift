import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import PTYKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// Dashboard の sessionNode(id:) / sessionForest(in:) が、sessionNodes を変更するすべての経路
// （spawn・復元の成功/失敗プレースホルダ・削除・並べ替え・改名・hook 駆動の status 変更）の後も
// 線形検索と同じ結果を返し続ける（Dictionary 索引・forest キャッシュの無効化漏れの回帰防止）。
//
// - sessionNode(id:) は sessionNodeIndex（Dictionary）を appendSessionNode/removeSessionNode の
//   2 ヘルパー経由でのみ更新する。sessionNodes への追加・削除サイトは
//   restoreSession 成功/失敗、restoreChatSession 成功/失敗、spawnNewSession .pty/.appServer、
//   removeSingleSession で、下記テストで各経路を踏む。swapAt（reorderSession）は
//   Dictionary の中身を変えないため索引更新不要だが、回帰確認として含める。
// - sessionForest(in:) は sessionTreeInputs(for:)（Equatable な値スナップショット）が前回と一致すれば
//   forest を再利用する「内容ベース」の無効化なので、DashboardViewModel の公開ミューテーションを
//   経由しない hook 駆動の status 変更でも無効化されることを検証する。

private func flatten(_ nodes: [SessionTreeNode]) -> [SessionID] {
    nodes.flatMap { [$0.id] + flatten($0.children) }
}

private func codexChatDescriptor(
    id: SessionID,
    workingDirectory: String,
    resumeID: String
) -> PersistedSessionDescriptor {
    PersistedSessionDescriptor(
        id: id,
        kind: .codex,
        workingDirectory: workingDirectory,
        name: "Codex Chat",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:],
        backend: .appServer,
        token: "session-lookup-test-token",
        resumeID: resumeID,
        launchContext: .interactive
    )
}

@Suite("Dashboard session lookup and forest", .serialized)
struct DashboardSessionLookupTests {

    // sessionNode(id:) は追加・改名・削除のどの変更後も「配列の線形検索」と同じ結果を返し続ける。
    @Test @MainActor
    func sessionNodeLookup_staysConsistentThroughMutations() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = ProjectID()
        let a = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let b = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let c = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID, from: a, launchContext: .orchestration)

        func assertConsistent(_ context: String) {
            for id in [a, b, c] {
                let viaLookup = dashboard.sessionNode(id: id)?.id
                let viaLinear = dashboard.sessionNodes.first { $0.id == id }?.id
                #expect(viaLookup == viaLinear, "\(context): sessionNode(id:) と線形検索が不一致 (id=\(id))")
            }
        }

        assertConsistent("spawn 直後")
        #expect(dashboard.sessionNode(id: a) != nil)
        #expect(dashboard.sessionNode(id: c) != nil, "orchestration 子も引けること")
        #expect(dashboard.sessionNode(id: SessionID()) == nil, "存在しない ID は nil")

        dashboard.renameSession(a, to: "renamed-a")
        assertConsistent("rename 後")
        #expect(dashboard.sessionNode(id: a)?.controllable.name == "renamed-a")

        await dashboard.removeSession(b)
        #expect(dashboard.sessionNode(id: b) == nil, "削除済みセッションが引ける（インデックス無効化漏れ）")
        assertConsistent("remove 後")

        let d = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        #expect(dashboard.sessionNode(id: d) != nil, "削除後の新規 spawn が引けない（インデックス無効化漏れ）")
        assertConsistent("再 spawn 後")
    }

    // sessionForest(in:) は sessionNodes の変更（追加・親子・削除・改名）を正しく反映し続ける。
    // 可視フィルタ（orchestration 子はサイドバー非表示）のセマンティクスも不変。
    @Test @MainActor
    func sessionForest_reflectsMutationsAndKeepsVisibilitySemantics() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = ProjectID()
        let parent = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let child = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID, from: parent)
        let orchestrationRoot = try await dashboard.spawnNewSession(
            kind: .claudeCode, projectID: projectID, launchContext: .orchestration
        )

        var forest = dashboard.sessionForest(in: projectID)
        var flattened = flatten(forest)
        #expect(flattened.contains(parent))
        #expect(flattened.contains(child), "子セッションが forest に現れない")
        #expect(!forest.map(\.id).contains(orchestrationRoot), "orchestration ルートがサイドバー forest に露出（可視フィルタ変化）")
        let parentNode = try #require(forest.first { $0.id == parent })
        #expect(parentNode.children.map(\.id).contains(child), "親子構造が forest に反映されていない")

        // 変更1: 改名が forest の name に反映される。
        dashboard.renameSession(parent, to: "renamed-parent")
        forest = dashboard.sessionForest(in: projectID)
        #expect(forest.first { $0.id == parent }?.name == "renamed-parent", "rename が forest に反映されない（キャッシュ無効化漏れ）")

        // 変更2: 子の削除が forest から消える。
        await dashboard.removeSession(child)
        forest = dashboard.sessionForest(in: projectID)
        flattened = flatten(forest)
        #expect(!flattened.contains(child), "削除した子が forest に残存（キャッシュ無効化漏れ）")

        // 変更3: 新規 spawn が forest に現れる。
        let e = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        forest = dashboard.sessionForest(in: projectID)
        #expect(flatten(forest).contains(e), "新規 spawn が forest に現れない（キャッシュ無効化漏れ）")

        // 別プロジェクトの forest は影響を受けない（プロジェクト絞り込み不変）。
        let otherProject = ProjectID()
        #expect(dashboard.sessionForest(in: otherProject).isEmpty)
    }

    // MARK: - sessionNodeIndex 同期: spawn 経路

    @Test @MainActor
    func sessionNodeIndex_syncsOnAppServerSpawn() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let id = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)

        #expect(dashboard.sessionNode(id: id)?.appServer != nil, "spawnNewSession(.appServer) 直後に索引から引けない")
    }

    // MARK: - sessionNodeIndex 同期: restoreSession (.pty) 経路

    @Test @MainActor
    func sessionNodeIndex_syncsOnPTYRestoreSuccess() async throws {
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
        let sessionID = SessionID()
        let descriptor = makePersistedSessionDescriptor(
            id: sessionID,
            kind: .claudeCode,
            workingDirectory: workspaceURL.path
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: InMemorySessionStore([descriptor]),
            workspaceDirectory: workspaceURL
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        #expect(dashboard.sessionNode(id: sessionID)?.pty != nil, "restoreSession 成功後に索引から引けない")
    }

    // restoreSession の catch 分岐（makeRestoreErrorSession によるプレースホルダ append）を踏む。
    @Test @MainActor
    func sessionNodeIndex_syncsOnPTYRestoreFailurePlaceholder() async throws {
        let descriptor = makeCustomAgentDescriptor()
        let catalog = AgentCatalog(customDescriptors: [descriptor])
        let sessionID = SessionID()
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

        let sessionStore = InMemorySessionStore([
            PersistedSessionDescriptor(
                id: sessionID,
                agentRef: descriptor.ref,
                workingDirectory: workspaceURL.path,
                name: "Broken Restore",
                projectID: nil,
                startedAt: Date(),
                command: "/opt/homebrew/bin/aider",
                args: ["--model", "sonnet"],
                env: [:],
                token: "token-\(sessionID.rawValue.uuidString)"
            )
        ])
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: AsyncStream<(SessionID, HookEvent)>.makeStream().stream,
            sessions: sessionStore,
            workspaceDirectory: workspaceURL,
            customAgentBinaryPaths: [:],
            agentCatalog: catalog
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let node = dashboard.sessionNode(id: sessionID)
        #expect(node?.pty != nil, "restoreSession 失敗プレースホルダが索引から引けない")
        if case .error = node?.status {} else {
            Issue.record("プレースホルダの status が .error でない: \(String(describing: node?.status))")
        }
    }

    // MARK: - sessionNodeIndex 同期: restoreChatSession (.appServer) 経路

    @Test @MainActor
    func sessionNodeIndex_syncsOnChatRestoreSuccess() async throws {
        let transport = ScriptedAppServerTransport()
        let sessionID = SessionID()
        let descriptor = codexChatDescriptor(
            id: sessionID,
            workingDirectory: "/tmp/session-lookup-restore-ok",
            resumeID: "thread-white-restore-ok"
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: InMemorySessionStore([descriptor]),
            agentBinaryPaths: [.codex: "/bin/echo"],
            appServerClientFactory: { _, _, _, _, handler in
                CodexStructuredAgentClient(
                    client: CodexAppServerClient(transport: transport, serverRequestHandler: handler)
                )
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        try await waitUntil { transport.capturedParams(for: "thread/resume").count == 1 }

        #expect(dashboard.sessionNode(id: sessionID)?.appServer != nil, "restoreChatSession 成功後に索引から引けない")
    }

    // 明示要求（task-3 契約）: restoreChatSession のプレースホルダ append（catch 分岐）を必ず踏む。
    @Test @MainActor
    func sessionNodeIndex_syncsOnChatRestoreFailurePlaceholder() async throws {
        let failingChatID = SessionID()
        let failingChat = codexChatDescriptor(
            id: failingChatID,
            workingDirectory: "/tmp/session-lookup-restore-fail",
            resumeID: "thread-white-restore-fail"
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            // codex の agentBinaryPaths を空にし、prepareSessionLaunch を throw させて
            // restoreChatSession の catch（プレースホルダ append）分岐を踏む。
            sessions: InMemorySessionStore([failingChat])
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let node = dashboard.sessionNode(id: failingChatID)
        let chat = try #require(node?.appServer, "chat 復元失敗プレースホルダが索引から引けない")
        guard case .failed = chat.restoreState else {
            Issue.record("プレースホルダの restoreState が .failed でない: \(chat.restoreState)")
            return
        }
    }

    // MARK: - sessionNodeIndex 同期: removeSession 経路

    // removeSession は部分木を deepest-first でカスケード削除する。親・子の両方が索引から消えること。
    @Test @MainActor
    func sessionNodeIndex_removesEntireSubtreeOnCascadeRemoval() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = ProjectID()
        let parentID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let childID = try await dashboard.spawnNewSession(
            kind: .claudeCode, projectID: projectID, from: parentID, launchContext: .orchestration
        )
        #expect(dashboard.sessionNode(id: parentID) != nil)
        #expect(dashboard.sessionNode(id: childID) != nil)

        await dashboard.removeSession(parentID)

        #expect(dashboard.sessionNode(id: parentID) == nil, "カスケード削除後も親が索引に残存")
        #expect(dashboard.sessionNode(id: childID) == nil, "カスケード削除後も子が索引に残存（無効化漏れ）")
    }

    // MARK: - sessionNodeIndex 同期: reorderSession (swapAt) 経路

    // swapAt は sessionNodes の「並び」のみを変え Dictionary の中身は変わらないため、
    // ヘルパーを経由しない唯一のミューテーションサイトである。回帰として、
    // reorder 後も両方の ID が正しく索引から引けることを確認する。
    @Test @MainActor
    func sessionNodeIndex_staysConsistentAfterReorder() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let a = try await dashboard.spawnNewSession(kind: .claudeCode)
        let b = try await dashboard.spawnNewSession(kind: .claudeCode)

        dashboard.reorderSession(a, with: b)

        #expect(dashboard.sessionNode(id: a)?.id == a)
        #expect(dashboard.sessionNode(id: b)?.id == b)
        #expect(dashboard.sessionNodes.map(\.id) == [b, a], "swapAt 後の並びが反映されていない")
    }

    // MARK: - sessionForestCache: DashboardViewModel のミューテーションメソッドを経由しない無効化

    // sessionForest(in:) は sessionTreeInputs(for:) の値スナップショット比較で無効化するため、
    // renameSession のような DashboardViewModel メソッド呼び出しを介さない「hook 駆動の内部 status
    // 変更のみ」でも次回呼び出しで新しい status を反映できることを検証する
    // （レビュー観点: ステータス変更のキャッシュ無効化漏れ）。
    @Test @MainActor
    func sessionForest_reflectsStatusChangeDrivenPurelyByHookEvent() async throws {
        let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = ProjectID()
        let id = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

        let firstForest = dashboard.sessionForest(in: projectID)
        let firstStatus = try #require(firstForest.first { $0.id == id }?.status)

        // DashboardViewModel の公開ミューテーションメソッドは一切呼ばず、hook イベントのみで
        // status を反転させる（.stop は常に .idle へ遷移する: AgentDomain/StatusReducer.swift）。
        hookContinuation.yield((id, .stop(turnId: nil)))
        try await waitUntil { dashboard.sessionNode(id: id)?.status.isIdle == true }

        let secondForest = dashboard.sessionForest(in: projectID)
        let secondStatus = try #require(secondForest.first { $0.id == id }?.status)

        #expect(secondStatus != firstStatus, "hook 駆動の status 変更が sessionForest キャッシュに反映されない（無効化漏れ）")
        #expect(secondStatus.isIdle, "status 変更後の forest ノードが .idle になっていない")
    }
}

private extension SessionStatus {
    var isIdle: Bool {
        if case .idle = self { true } else { false }
    }
}
