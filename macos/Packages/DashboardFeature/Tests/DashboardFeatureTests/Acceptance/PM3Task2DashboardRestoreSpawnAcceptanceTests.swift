import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

// PM3 task-2 受け入れテスト（PM 著述・実装役は編集禁止）。
// 契約: tasks/task-2.md — A1 復元 policy / A2 spawn 後始末 / A4 復元失敗の可視化 / S2 removeProject。

/// initialize は成功し thread/start で JSON-RPC error を返すトランスポート（A2b 用）。
/// close() が呼ばれたか（= chatVM.terminate() まで到達したか）を記録する。
private final class PM3Task2FailingThreadStartTransport: AppServerTransport, @unchecked Sendable {
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
                "message": "pm3task2: scripted thread/start failure",
            ]]
        }
        let payload = try! JSONSerialization.data(withJSONObject: response)
        lock.withLock { _ = 0 }
        continuation?.yield(payload)
    }

    func close() async {
        lock.withLock { closedFlag = true }
        continuation?.finish()
    }

    func wasClosed() -> Bool { lock.withLock { closedFlag } }
}

private struct PM3Task2FactoryError: Error {}

@MainActor
private func pm3Task2OrchestrationDescriptor(
    id: SessionID,
    workingDirectory: String,
    resumeID: String
) -> PersistedSessionDescriptor {
    PersistedSessionDescriptor(
        id: id,
        kind: .codex,
        workingDirectory: workingDirectory,
        name: "Codex Orchestration",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:],
        backend: .appServer,
        token: "pm3task2-token",
        resumeID: resumeID,
        launchContext: .orchestration
    )
}

@Suite(.serialized)
struct PM3Task2DashboardRestoreSpawnAcceptanceTests {

    // A1: orchestration の chat 復元は launchContext の policy（never / danger-full-access）を
    // thread/resume に渡す。descriptor.launchContext を無視して .interactive（on-request /
    // workspace-write）で復元してはならない。
    @Test @MainActor
    func restore_orchestrationDescriptor_passesLaunchContextPolicyToThreadResume() async throws {
        let transport = ScriptedAppServerTransport()
        let sessionID = SessionID()
        let descriptor = pm3Task2OrchestrationDescriptor(
            id: sessionID,
            workingDirectory: "/tmp/pm3task2-a1",
            resumeID: "thread-1"
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

    // A2a: appServer spawn でクライアント生成（makeChatSessionViewModel）が throw したら、
    // エラーは rethrow され、所有ワークスペースは残らず、sessionNodes にノードが増えず、
    // セッションは永続化されない。
    @Test @MainActor
    func spawnAppServer_factoryThrows_cleansUpAndRethrows() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        let sessionStore = InMemorySessionStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: sessionStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/bin/echo"],
            appServerClientFactory: { _, _, _, _, _ in throw PM3Task2FactoryError() }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()
        let nodesBefore = dashboard.sessionNodes.count

        await #expect(throws: PM3Task2FactoryError.self) {
            try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
        }

        #expect(dashboard.sessionNodes.count == nodesBefore, "throw したのに sessionNodes にノードが残っている")
        let leftover = (try? FileManager.default.contentsOfDirectory(atPath: workspaceRoot.path)) ?? []
        #expect(leftover.isEmpty, "throw 後に所有ワークスペースが残存: \(leftover)")
        #expect(await sessionStore.load().isEmpty, "throw したセッションが永続化されている")
    }

    // A2b: chatVM 生成後に startNew（thread/start）が throw したら、rethrow に加えて
    // chatVM が terminate され（クライアント close がトランスポートまで届く）、後始末が走る。
    @Test @MainActor
    func spawnAppServer_startNewThrows_terminatesChatVMAndCleansUp() async throws {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }
        let transport = PM3Task2FailingThreadStartTransport()
        let sessionStore = InMemorySessionStore()
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: sessionStore,
            workspaceDirectory: workspaceRoot,
            agentBinaryPaths: [.codex: "/bin/echo"],
            appServerClientFactory: { _, _, _, _, handler in
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
        let leftover = (try? FileManager.default.contentsOfDirectory(atPath: workspaceRoot.path)) ?? []
        #expect(leftover.isEmpty, "throw 後に所有ワークスペースが残存: \(leftover)")
        #expect(await sessionStore.load().isEmpty, "throw したセッションが永続化されている")
    }

    // A4: chat 復元の準備段階（ここでは binary 不在で prepareSessionLaunch）が throw しても
    // セッションは silent に消えず、復元失敗が分かる可視プレースホルダが sessionNodes に載る。
    @Test @MainActor
    func restore_chatPreparationFailure_appendsVisibleFailedPlaceholder() async throws {
        let sessionID = SessionID()
        let descriptor = pm3Task2OrchestrationDescriptor(
            id: sessionID,
            workingDirectory: "/tmp/pm3task2-a4",
            resumeID: "thread-a4"
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        // .codex の binary を解決させない（agentBinaryPaths 空）→ prepareSessionLaunch が throw する。
        let environment = makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: InMemorySessionStore([descriptor]),
            appServerClientFactory: { _, _, _, _, _ in
                Issue.record("復元準備が throw する経路で client factory が呼ばれてはならない")
                throw PM3Task2FactoryError()
            }
        )
        let dashboard = DashboardViewModel(environment: environment)
        await dashboard.start()

        let node = dashboard.sessionNodes.first { $0.id == sessionID }
        let chat = try #require(node?.appServer, "復元失敗セッションが sessionNodes に現れていない（silent drop）")
        guard case .failed = chat.restoreState else {
            Issue.record("プレースホルダの restoreState が .failed でない: \(chat.restoreState)")
            return
        }
    }

    // S2: removeProject はサイドバー不可視（orchestration launchContext）のセッションも含めて
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
}
