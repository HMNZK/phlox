import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
@testable import DashboardFeature
@testable import SessionFeature

/// MC-3b: Codex 構造化承認ブリッジ。
/// appServer セッションの pendingApprovals を中立型 ControlApproval に写像し、
/// 応答を ChatApprovalBroker 経由で実際の構造化応答に橋渡しすることを検証する。
@MainActor
@Suite struct ControlApprovalBridgeTests {

    /// broker が解決した JSON-RPC レスポンス（{"id":N,"result":{...}}）を外向き送信から捕捉する transport。
    /// 「承認応答が no-op でなく実際に broker→server へ届く」ことを実証するために使う。
    private final class CapturingTransport: AppServerTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: AsyncStream<Data>.Continuation?
        private var responses: [[String: Any]] = []

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
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
            else { return }
            if let method = object["method"] as? String {
                // クライアント発のリクエストにはダミー結果で応答（initialize / thread/start 等）。
                if let id = object["id"] {
                    let result = stubResult(for: method)
                    receiveObject(["jsonrpc": "2.0", "id": id, "result": result])
                }
            } else if object["result"] != nil || object["error"] != nil {
                // server request への応答（broker が生成した構造化応答）を捕捉。
                lock.withLock { responses.append(object) }
            }
        }

        func receive(_ json: String) {
            continuation?.yield(Data(json.utf8))
        }

        func receiveObject(_ object: [String: Any]) {
            let data = try! JSONSerialization.data(withJSONObject: object)
            continuation?.yield(data)
        }

        func close() async { continuation?.finish() }

        func capturedResponses() -> [[String: Any]] {
            lock.withLock { responses }
        }

        private func stubResult(for method: String) -> Any {
            switch method {
            case "initialize":
                return [
                    "codexHome": "/tmp/codex",
                    "platformFamily": "mac",
                    "platformOs": "macos",
                    "userAgent": "codex-test/1",
                ]
            case "thread/start", "thread/resume":
                return [
                    "thread": ["id": "thread-1", "status": ["type": "idle"]],
                    "approvalPolicy": "never",
                    "approvalsReviewer": "user",
                    "sandbox": ["type": "workspaceWrite"],
                    "model": "gpt-5-codex",
                    "reasoningEffort": "medium",
                ]
            case "thread/read":
                return ["thread": ["id": "thread-1", "status": ["type": "idle"], "turns": []]]
            case "model/list":
                return ["data": [], "nextCursor": NSNull()]
            case "permissionProfile/list":
                return ["data": [], "nextCursor": NSNull()]
            case "collaborationMode/list":
                return ["data": []]
            default:
                return [:]
            }
        }
    }

    private func makeStartedSession(
        agentRef: AgentRef = .builtin(.codex)
    ) async throws -> (vm: ChatSessionViewModel, transport: CapturingTransport, broker: ChatApprovalBroker) {
        let transport = CapturingTransport()
        let broker = ChatApprovalBroker()
        let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: agentRef,
            client: CodexStructuredAgentClient(client: client),
            approvalBroker: broker,
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        return (vm, transport, broker)
    }

    private func driveCommandApproval(
        _ transport: CapturingTransport,
        id: Int,
        reason: String,
        threadId: String = "thread-1"
    ) {
        transport.receive("""
        {"jsonrpc":"2.0","id":\(id),"method":"item/commandExecution/requestApproval","params":{"threadId":"\(threadId)","turnId":"turn-1","itemId":"cmd-\(id)","startedAtMs":1,"command":"pwd","cwd":"/tmp","reason":"\(reason)"}}
        """)
    }

    // MARK: - 列挙

    @Test func listControlApprovals_mapsPendingApprovalsFromAppServerSessions() async throws {
        let (vm, transport, _) = try await makeStartedSession()
        driveCommandApproval(transport, id: 99, reason: "run pwd")
        try await waitUntil { vm.pendingApprovals.count == 1 }

        let approvals = DashboardViewModel.controlApprovals(from: [vm])

        #expect(approvals.count == 1)
        let approval = try #require(approvals.first)
        #expect(approval.id == vm.pendingApprovals[0].id)
        #expect(approval.sessionID == vm.id)
        #expect(approval.kind == "codex")
        #expect(approval.prompt == "run pwd")
    }

    @Test func listControlApprovals_flattensMultipleSessions() async throws {
        let (vm1, t1, _) = try await makeStartedSession()
        let (vm2, t2, _) = try await makeStartedSession()
        driveCommandApproval(t1, id: 1, reason: "first")
        driveCommandApproval(t2, id: 2, reason: "second")
        try await waitUntil { vm1.pendingApprovals.count == 1 && vm2.pendingApprovals.count == 1 }

        let approvals = DashboardViewModel.controlApprovals(from: [vm1, vm2])

        #expect(approvals.count == 2)
        #expect(Set(approvals.map(\.sessionID)) == Set([vm1.id, vm2.id]))
        #expect(Set(approvals.map(\.prompt)) == Set(["first", "second"]))
    }

    @Test func listControlApprovals_returnsEmptyWhenNoPendingApprovals() async throws {
        let (vm, _, _) = try await makeStartedSession()
        let approvals = DashboardViewModel.controlApprovals(from: [vm])
        #expect(approvals.isEmpty)
    }

    // MARK: - 応答（broker への実到達 = no-op でないこと）

    @Test func respondToControlApproval_deliversStructuredDecisionToBroker() async throws {
        let (vm, transport, _) = try await makeStartedSession()
        driveCommandApproval(transport, id: 99, reason: "run pwd")
        try await waitUntil { vm.pendingApprovals.count == 1 }
        let approvalID = vm.pendingApprovals[0].id

        let found = await DashboardViewModel.respondToControlApproval(
            in: [vm],
            id: approvalID,
            decision: .accept
        )

        #expect(found == true)
        try await waitUntil { vm.pendingApprovals.isEmpty }

        // no-op 検証: broker が解決した構造化応答が transport の外向き送信に現れる。
        // command 種別は {"decision": "accept"} を返す（ChatApprovalBroker.respond）。
        try await waitUntil {
            transport.capturedResponses().contains { response in
                (response["result"] as? [String: Any])?["decision"] as? String == "accept"
            }
        }
        let decisionResponses = transport.capturedResponses().compactMap {
            ($0["result"] as? [String: Any])?["decision"] as? String
        }
        #expect(decisionResponses.contains("accept"))
    }

    @Test(arguments: [
        CodexAppServerKit.ApprovalDecision.accept,
        .decline,
        .cancel,
    ])
    func respondToControlApproval_relaysEachDecisionRawValue(decision: CodexAppServerKit.ApprovalDecision) async throws {
        let (vm, transport, _) = try await makeStartedSession()
        driveCommandApproval(transport, id: 99, reason: "run pwd")
        try await waitUntil { vm.pendingApprovals.count == 1 }
        let approvalID = vm.pendingApprovals[0].id

        let found = await DashboardViewModel.respondToControlApproval(in: [vm], id: approvalID, decision: decision)
        #expect(found == true)

        try await waitUntil {
            transport.capturedResponses().contains { response in
                (response["result"] as? [String: Any])?["decision"] as? String == decision.rawValue
            }
        }
    }

    @Test func respondToControlApproval_unknownIDReturnsFalse() async throws {
        let (vm, transport, _) = try await makeStartedSession()
        driveCommandApproval(transport, id: 99, reason: "run pwd")
        try await waitUntil { vm.pendingApprovals.count == 1 }

        let found = await DashboardViewModel.respondToControlApproval(
            in: [vm],
            id: UUID(), // 存在しない id
            decision: .accept
        )

        #expect(found == false)
        // 既存の保留承認は影響を受けない。
        #expect(vm.pendingApprovals.count == 1)
    }

    @Test func respondToControlApproval_emptySessionsReturnsFalse() async {
        let found = await DashboardViewModel.respondToControlApproval(
            in: [],
            id: UUID(),
            decision: .accept
        )
        #expect(found == false)
    }
}
