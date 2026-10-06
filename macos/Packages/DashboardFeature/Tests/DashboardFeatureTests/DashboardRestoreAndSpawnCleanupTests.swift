import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import PTYKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// Dashboard のチャットセッション復元・spawn 失敗時の後始末・removeProject の部分木カスケード。
// - 復元: 現在のフルアクセス設定を thread/resume に渡す／復元準備が失敗しても silent に消えず、後続の復元も続く。
// - spawn 失敗（クライアント生成 / thread/start の throw）: エラーを rethrow し、token・所有ワークスペース・
//   ノード・永続化・chatVM（terminate）を残さない。
// - removeProject: サイドバー不可視（orchestration）のセッションも部分木ごと除去する。

private struct SpawnFactoryError: Error {}

/// factory / transport から捕捉したトークンを @Sendable 境界越しに読むための小箱。
private final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func set(_ newValue: String?) { lock.withLock { value = newValue } }
    func get() -> String? { lock.withLock { value } }
}

/// initialize は成功し thread/start で JSON-RPC error を返すトランスポート（startNew throw 経路用）。
/// close() が呼ばれたか（= chatVM.terminate() まで到達したか）を記録する。
private final class FailingThreadStartTransport: AppServerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var closedFlag = false
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        self.receivedLines = AsyncStream { captured = $0 }
        self.continuation = captured
    }

    func send(_ data: Data) async throws {
        let line: Data
        if let newline = data.firstIndex(of: 0x0A) {
            line = Data(data[..<newline])
        } else {
            line = data
        }
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              let method = object["method"] as? String,
              let id = object["id"]
        else { return }
        let response: [String: Any]
        if method == "initialize" {
            response = ["jsonrpc": "2.0", "id": id, "result": [
                "codexHome": "/tmp/codex",
                "platformFamily": "mac",
                "platformOs": "macos",
                "userAgent": "codex-test/1",
            ]]
        } else {
            response = ["jsonrpc": "2.0", "id": id, "error": [
                "code": -32000,
                "message": "scripted thread/start failure",
            ]]
        }
        continuation?.yield(try! JSONSerialization.data(withJSONObject: response))
    }

    func close() async {
        lock.withLock { closedFlag = true }
        continuation?.finish()
    }

    func wasClosed() -> Bool { lock.withLock { closedFlag } }
}

@MainActor
private func codexChatDescriptor(
    id: SessionID,
    workingDirectory: String,
    resumeID: String,
    launchContext: SessionLaunchContext
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
        token: "restore-spawn-test-token",
        resumeID: resumeID,
        launchContext: launchContext
    )
}

@Suite("Dashboard restore and spawn cleanup", .serialized)
struct DashboardRestoreAndSpawnCleanupTests {

    // 復元: orchestration の chat 復元は現在のフルアクセス設定を thread/resume に渡す。
    // 設定未保存時の既定 ON では never / danger-full-access になる。
    @Test @MainActor
    func restore_orchestrationDescriptor_passesCurrentFullAccessPolicyToThreadResume() async throws {
        let transport = ScriptedAppServerTransport()
        let sessionID = SessionID()
        let descriptor = codexChatDescriptor(
            id: sessionID,
            workingDirectory: "/tmp/restore-orchestration",
            resumeID: "thread-1",
            launchContext: .orchestration
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: InMemorySessionStore([descriptor]),
            agentBinaryPaths: [.codex: "/bin/echo"],
            appServerClientFactory: { _, _, _, _, handler in
                let client = CodexAppServerClient(transport: transport, serverRequestHandler: handler)
                return CodexStructuredAgentClient(client: client)
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        try await waitUntil { transport.capturedParams(for: "thread/resume").count == 1 }
        let params = try #require(transport.capturedParams(for: "thread/resume").first)

        let approval = String(describing: params["approvalPolicy"] ?? "nil")
        let sandbox = String(describing: params["sandbox"] ?? "nil")
        #expect(approval.contains("never"), "orchestration 復元の approvalPolicy が never でない: \(approval)")
        #expect(
            sandbox.contains("danger") || sandbox.contains("full"),
            "orchestration 復元の sandbox が danger-full-access でない: \(sandbox)"
        )
    }

    // 復元: interactive の chat 復元は現在のフルアクセス設定を渡す。
    // 実装がポリシーを固定値へハードコードしていないことを保証する。
    @Test @MainActor
    func restore_interactiveDescriptor_passesCurrentFullAccessPolicyToThreadResume() async throws {
        let transport = ScriptedAppServerTransport()
        let sessionID = SessionID()
        let descriptor = codexChatDescriptor(
            id: sessionID,
            workingDirectory: "/tmp/restore-interactive",
            resumeID: "thread-white-1",
            launchContext: .interactive
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
        let params = try #require(transport.capturedParams(for: "thread/resume").first)
        let approval = String(describing: params["approvalPolicy"] ?? "nil")
        let sandbox = String(describing: params["sandbox"] ?? "nil")
        // interactive のポリシーは設定「フルアクセス」に従う。
        // このテストの意図は「復元経路が interactive のポリシーをそのまま渡す」ことなので、
        // 固定値ではなく現行の interactive ポリシーと突き合わせる。
        let expectedApproval = String(describing: SessionSpawnService.appServerApprovalPolicy(for: .interactive))
        let expectedSandbox = String(describing: SessionSpawnService.appServerSandboxPolicy(for: .interactive))
        #expect(expectedApproval.contains(approval), "interactive 復元の approvalPolicy が interactive ポリシーと不一致: \(approval) vs \(expectedApproval)")
        #expect(expectedSandbox.contains(sandbox), "interactive 復元の sandbox が interactive ポリシーと不一致: \(sandbox) vs \(expectedSandbox)")
    }

    // spawn 失敗: appServer spawn でクライアント生成（makeChatSessionViewModel）が throw したら、
    // エラーは rethrow され、登録済みトークン・所有ワークスペース・ノード・永続化が残らない。
    @Test @MainActor
    func spawnAppServer_factoryThrows_cleansUpAndRethrows() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
        let tokenBox = TokenBox()
        let sessionStore = InMemorySessionStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: sessionStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/bin/echo"],
            appServerClientFactory: { _, _, _, env, _ in
                tokenBox.set(env["PHLOX_TOKEN"])
                throw SpawnFactoryError()
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()
        let nodesBefore = dashboard.sessionNodes.count

        await #expect(throws: SpawnFactoryError.self) {
            try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
        }

        #expect(dashboard.sessionNodes.count == nodesBefore, "throw したのに sessionNodes にノードが残っている")
        let leftover = (try? FileManager.default.contentsOfDirectory(atPath: workspaceRoot.path)) ?? []
        #expect(leftover.isEmpty, "throw 後に所有ワークスペースが残存: \(leftover)")
        #expect(await sessionStore.load().isEmpty, "throw したセッションが永続化されている")
        let captured = try #require(tokenBox.get(), "factory が PHLOX_TOKEN を受け取っていない")
        let stillRegistered = await environment.tokenStore.session(forToken: captured)
        #expect(stillRegistered == nil, "factory throw 後も token が tokenStore に残存している")
    }

    // spawn 失敗: chatVM 生成後に startNew（thread/start）が throw したら、rethrow に加えて
    // chatVM が terminate され（クライアント close がトランスポートまで届く）、
    // 登録済みトークン・所有ワークスペース・ノード・永続化が残らない。
    @Test @MainActor
    func spawnAppServer_startNewThrows_terminatesChatVMAndCleansUp() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
        let transport = FailingThreadStartTransport()
        let tokenBox = TokenBox()
        let sessionStore = InMemorySessionStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: sessionStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/bin/echo"],
            appServerClientFactory: { _, _, _, env, handler in
                tokenBox.set(env["PHLOX_TOKEN"])
                let client = CodexAppServerClient(transport: transport, serverRequestHandler: handler)
                return CodexStructuredAgentClient(client: client)
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()
        let nodesBefore = dashboard.sessionNodes.count

        await #expect(throws: (any Error).self) {
            try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
        }

        #expect(dashboard.sessionNodes.count == nodesBefore, "throw したのに sessionNodes にノードが残っている")
        try await waitUntil { transport.wasClosed() }
        let captured = try #require(tokenBox.get(), "factory が PHLOX_TOKEN を受け取っていない")
        let stillRegistered = await environment.tokenStore.session(forToken: captured)
        #expect(stillRegistered == nil, "startNew throw 後も token が tokenStore に残存している")
        let leftover = (try? FileManager.default.contentsOfDirectory(atPath: workspaceRoot.path)) ?? []
        #expect(leftover.isEmpty, "throw 後に所有ワークスペースが残存: \(leftover)")
        #expect(await sessionStore.load().isEmpty, "throw したセッションが永続化されている")
    }

    // 復元失敗: chat 復元の準備段階（ここでは binary 不在で prepareSessionLaunch）が throw しても
    // セッションは silent に消えず、復元失敗が分かる可視プレースホルダが載り、
    // 後ろにある正常な pty descriptor の復元は続く（ループが中断しない）。
    @Test @MainActor
    func restore_chatFailureDoesNotAbortRemainingSessions() async throws {
        let failingChatID = SessionID()
        let succeedingPTYID = SessionID()
        // codex は agentBinaryPaths 空で prepareSessionLaunch が throw する（factory は呼ばれない）。
        let failingChat = codexChatDescriptor(
            id: failingChatID,
            workingDirectory: "/tmp/restore-failing-chat",
            resumeID: "thread-white-a4",
            launchContext: .orchestration
        )
        // claudeCode は claudeBinaryPath 由来で解決でき、pty で正常復元される。
        let succeedingPTY = makePersistedSessionDescriptor(
            id: succeedingPTYID,
            kind: .claudeCode,
            workingDirectory: "/tmp/restore-succeeding-pty",
            launchContext: .interactive
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: InMemorySessionStore([failingChat, succeedingPTY]),
            appServerClientFactory: { _, _, _, _, _ in
                Issue.record("復元準備が throw する経路で client factory が呼ばれてはならない")
                throw SpawnFactoryError()
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let chatNode = dashboard.sessionNodes.first { $0.id == failingChatID }
        let chat = try #require(chatNode?.appServer, "復元失敗 chat が可視プレースホルダとして現れていない（silent drop）")
        guard case .failed = chat.restoreState else {
            Issue.record("プレースホルダの restoreState が .failed でない: \(chat.restoreState)")
            return
        }
        guard case .error = chat.status else {
            Issue.record("プレースホルダの status が .error でない: \(chat.status)")
            return
        }
        // 後続 pty 復元がループ中断されず続いていること。
        let ptyNode = dashboard.sessionNodes.first { $0.id == succeedingPTYID }
        #expect(ptyNode?.pty != nil, "chat 復元失敗の後ろにある pty セッションが復元されていない（ループ中断）")
    }

    // removeProject: サイドバー不可視（orchestration launchContext）のセッションも含めて
    // プロジェクト配下の全セッションを除去する。
    @Test @MainActor
    func removeProject_removesInvisibleOrchestrationSessions() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = ProjectID()
        let visibleID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )
        let invisibleID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .orchestration
        )
        #expect(dashboard.sessionNodes.contains { $0.id == visibleID })
        #expect(dashboard.sessionNodes.contains { $0.id == invisibleID })

        await dashboard.removeProject(projectID)

        let remaining = dashboard.sessionNodes.filter { $0.projectID == projectID }.map(\.id)
        #expect(remaining.isEmpty, "removeProject 後もプロジェクト配下のセッションが残存: \(remaining)")
    }

    // removeProject の部分木: 可視の親配下にある不可視 orchestration 子も removeProject でカスケード除去される。
    @Test @MainActor
    func removeProject_cascadesToInvisibleOrchestrationChild() async throws {
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let projectID = ProjectID()
        let parentID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )
        let orchestrationChildID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            from: parentID,
            launchContext: .orchestration
        )
        #expect(dashboard.sessionNodes.contains { $0.id == parentID })
        #expect(dashboard.sessionNodes.contains { $0.id == orchestrationChildID })

        await dashboard.removeProject(projectID)

        #expect(!dashboard.sessionNodes.contains { $0.id == parentID }, "親セッションが残存")
        #expect(
            !dashboard.sessionNodes.contains { $0.id == orchestrationChildID },
            "不可視 orchestration 子が removeProject 後も残存"
        )
    }
}
