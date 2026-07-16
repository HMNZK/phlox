import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import PTYKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-3 白箱テスト（実装役 著述）。
// 受け入れテスト（PM3Task3SidebarIndexAcceptanceTests）が凍結する外部契約（sessionNode(id:) /
// sessionForest(in:) の返り値セマンティクス）に対し、内部実装（sessionNodeIndex Dictionary /
// sessionForestCache）が「sessionNodes を変更するすべての経路」で正しく同期・無効化されることを
// 網羅する。契約: tasks/task-3.md。
//
// 設計メモ:
// - sessionNode(id:) は sessionNodeIndex（Dictionary）を appendSessionNode/removeSessionNode の
//   2 ヘルパー経由でのみ更新する。DashboardViewModel.swift 内の sessionNodes への追加・削除サイトは
//   全 7 箇所（restoreSession 成功/失敗、restoreChatSession 成功/失敗、spawnNewSession .pty/.appServer、
//   removeSingleSession）あり、下記テストで各経路を最低 1 回踏む。swapAt（reorderSession）は
//   Dictionary の中身を変えないため index 更新不要だが、回帰確認として含める。
// - sessionForest(in:) は sessionTreeInputs(for:)（Equatable な値スナップショット）を毎回計算し、
//   前回キャッシュした入力と一致すれば forest を再利用する「内容ベース」の無効化なので、個別の
//   ミューテーション経路を逐一 invalidate する必要がない。この設計の正しさを裏付けるため、
//   DashboardViewModel の一切のミューテーションメソッドを経由しない「hook 駆動の status 変更のみ」
//   でもキャッシュが正しく無効化されることを検証する（レビュー観点: ステータス変更の無効化漏れ）。

private func pm3Task3WhiteboxCodexChatDescriptor(
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
        token: "pm3task3-white-token",
        resumeID: resumeID,
        launchContext: .interactive
    )
}

@Suite(.serialized)
struct PM3Task3SidebarWhiteboxTests {

    // MARK: - sessionNodeIndex 同期: spawn 経路

    @Test @MainActor
    func sessionNodeIndex_syncsOnPTYSpawn() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let id = try await dashboard.spawnNewSession(kind: .claudeCode)

        #expect(dashboard.sessionNode(id: id)?.id == id, "spawnNewSession(.pty) 直後に索引から引けない")
    }

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
        let descriptor = pm3Task3WhiteboxCodexChatDescriptor(
            id: sessionID,
            workingDirectory: "/tmp/pm3task3-white-restore-ok",
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
        let failingChat = pm3Task3WhiteboxCodexChatDescriptor(
            id: failingChatID,
            workingDirectory: "/tmp/pm3task3-white-restore-fail",
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

    @Test @MainActor
    func sessionNodeIndex_removesOnSingleRemoval() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(pty: MockPTYManager(), hookStream: hookStream)
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let id = try await dashboard.spawnNewSession(kind: .claudeCode)
        #expect(dashboard.sessionNode(id: id) != nil)

        await dashboard.removeSession(id)

        #expect(dashboard.sessionNode(id: id) == nil, "removeSession 後も索引に残存している")
    }

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
