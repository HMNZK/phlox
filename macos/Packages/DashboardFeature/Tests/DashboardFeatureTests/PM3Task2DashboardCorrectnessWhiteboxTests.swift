import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import PTYKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-2 白箱テスト（実装役 著述）。
// 受け入れテスト（PM3Task2DashboardRestoreSpawnAcceptanceTests）が凍結する外部契約に対し、
// 内部分岐・資源解放の網羅（token / workspace / chatVM の throw 位置別解放、復元ループの継続、
// removeProject の部分木カスケード）を符号化する。契約: tasks/task-2.md。

private struct PM3Task2WhiteboxFactoryError: Error {}

/// factory / transport から捕捉したトークンを @Sendable 境界越しに読むための小箱。
private final class PM3Task2TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func set(_ newValue: String?) { lock.withLock { value = newValue } }
    func get() -> String? { lock.withLock { value } }
}

/// initialize は成功し thread/start で JSON-RPC error を返すトランスポート（startNew throw 経路用）。
private final class PM3Task2WhiteboxFailingThreadStartTransport: AppServerTransport, @unchecked Sendable {
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
                "message": "pm3task2-whitebox: scripted thread/start failure",
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
private func pm3Task2WhiteboxCodexChatDescriptor(
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
        token: "pm3task2-white-token",
        resumeID: resumeID,
        launchContext: launchContext
    )
}

@Suite(.serialized)
struct PM3Task2DashboardCorrectnessWhiteboxTests {

    // A1 回帰: interactive の chat 復元は launchContext 由来の on-request / workspace-write を渡す。
    // 実装が never へハードコードされていない（= descriptor.launchContext を尊重する）ことを保証する。
    @Test @MainActor
    func restore_interactiveDescriptor_passesOnRequestWorkspaceWriteToThreadResume() async throws {
        let transport = ScriptedAppServerTransport()
        let sessionID = SessionID()
        let descriptor = pm3Task2WhiteboxCodexChatDescriptor(
            id: sessionID,
            workingDirectory: "/tmp/pm3task2-white-a1",
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
        #expect(approval.contains("on-request"), "interactive 復元の approvalPolicy が on-request でない: \(approval)")
        #expect(sandbox.contains("workspace-write"), "interactive 復元の sandbox が workspace-write でない: \(sandbox)")
    }

    // A2a 網羅: makeChatSessionViewModel（factory）throw 時、登録済みトークンが tokenStore から除去される。
    // 受け入れは workspace / nodes / 永続化を検査するが token は検査しないため、ここで token の解放漏れを潰す。
    @Test @MainActor
    func spawnAppServer_factoryThrows_removesRegisteredToken() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
        let tokenBox = PM3Task2TokenBox()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/bin/echo"],
            appServerClientFactory: { _, _, _, env, _ in
                tokenBox.set(env["PHLOX_TOKEN"])
                throw PM3Task2WhiteboxFactoryError()
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        await #expect(throws: PM3Task2WhiteboxFactoryError.self) {
            try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
        }

        let captured = try #require(tokenBox.get(), "factory が PHLOX_TOKEN を受け取っていない")
        let stillRegistered = await environment.tokenStore.session(forToken: captured)
        #expect(stillRegistered == nil, "factory throw 後も token が tokenStore に残存している")
    }

    // A2b 網羅: startNew（thread/start）throw 時、chatVM.terminate() が client.close をトランスポートまで
    // 届かせ、かつ登録済みトークンが除去される。生成後 throw の解放（terminate + token + workspace）を検査する。
    @Test @MainActor
    func spawnAppServer_startNewThrows_terminatesAndRemovesToken() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
        let transport = PM3Task2WhiteboxFailingThreadStartTransport()
        let tokenBox = PM3Task2TokenBox()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/bin/echo"],
            appServerClientFactory: { _, _, _, env, handler in
                tokenBox.set(env["PHLOX_TOKEN"])
                return CodexStructuredAgentClient(
                    client: CodexAppServerClient(transport: transport, serverRequestHandler: handler)
                )
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        await #expect(throws: (any Error).self) {
            try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
        }

        try await waitUntil { transport.wasClosed() }
        let captured = try #require(tokenBox.get(), "factory が PHLOX_TOKEN を受け取っていない")
        let stillRegistered = await environment.tokenStore.session(forToken: captured)
        #expect(stillRegistered == nil, "startNew throw 後も token が tokenStore に残存している")
        let leftover = (try? FileManager.default.contentsOfDirectory(atPath: workspaceRoot.path)) ?? []
        #expect(leftover.isEmpty, "startNew throw 後に所有ワークスペースが残存: \(leftover)")
    }

    // A4 ループ継続: 復元に失敗する chat descriptor の後ろにある正常な pty descriptor も復元される。
    // catch が throw を外へ漏らさず、失敗は可視プレースホルダ（.failed）として残ることを保証する。
    @Test @MainActor
    func restore_chatFailureDoesNotAbortRemainingSessions() async throws {
        let failingChatID = SessionID()
        let succeedingPTYID = SessionID()
        // codex は agentBinaryPaths 空で prepareSessionLaunch が throw する（factory は呼ばれない）。
        let failingChat = pm3Task2WhiteboxCodexChatDescriptor(
            id: failingChatID,
            workingDirectory: "/tmp/pm3task2-white-a4-chat",
            resumeID: "thread-white-a4",
            launchContext: .orchestration
        )
        // claudeCode は claudeBinaryPath 由来で解決でき、pty で正常復元される。
        let succeedingPTY = makePersistedSessionDescriptor(
            id: succeedingPTYID,
            kind: .claudeCode,
            workingDirectory: "/tmp/pm3task2-white-a4-pty",
            launchContext: .interactive
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: InMemorySessionStore([failingChat, succeedingPTY]),
            appServerClientFactory: { _, _, _, _, _ in
                Issue.record("A4: 復元準備が throw する経路で client factory が呼ばれてはならない")
                throw PM3Task2WhiteboxFactoryError()
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let chatNode = dashboard.sessionNodes.first { $0.id == failingChatID }
        let chat = try #require(chatNode?.appServer, "復元失敗 chat が可視プレースホルダとして現れていない")
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

    // S2 部分木: 可視の親配下にある不可視 orchestration 子も removeProject でカスケード除去される。
    // 受け入れは独立2ルートを検査するが、こちらは親子（部分木）カスケードを検査する。
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
