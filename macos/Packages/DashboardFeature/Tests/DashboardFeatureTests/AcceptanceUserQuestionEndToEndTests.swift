import Foundation
import Testing
import AgentDomain
import StructuredChatKit
import ClaudeAgentKit
@testable import SessionFeature

// task-2 受け入れテスト（PM 著・凍結）。契約: tasks/task-2.md（統合）。
// 実 ClaudeChatClient（task-1 実装）とモック transport を VM に配線し、
// 「can_use_tool 受信 → カード表示 → 回答 → stdin へ control_response」を実副作用で検証する。
// アサーションの変更は禁止。テストハーネスの欠陥を発見した場合は PM に報告し、
// 承認を得たうえでハーネス部分に限り修理してよい。

// MARK: - ハーネス

private final class E2EMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func start() throws {}

    func send(_ data: Data) async throws {
        lock.withLock { sent.append(data) }
    }

    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func stderrTail() async -> String? { nil }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }

    func sentStrings() -> [String] {
        lock.withLock { sent.map { String(data: $0, encoding: .utf8) ?? "" } }
    }
}

private func e2eWaitUntil(
    _ condition: @escaping @MainActor () -> Bool,
    timeoutMs: Int = 3000
) async throws {
    for _ in 0..<(timeoutMs / 10) {
        if await condition() { return }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    let final = await condition()
    #expect(final, "e2eWaitUntil timed out")
}

// MARK: - 受け入れ条件（統合）

@Test @MainActor
func askUserQuestionFlowsFromTransportToCardToControlResponse() async throws {
    let transport = E2EMockTransport()
    // environment: [:] — Phlox 配下実行時の PHLOX_SESSION_ID 漏れを遮断する（決定論）。
    let client = ClaudeChatClient(environment: [:]) { _, _, _, _ in transport }
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    transport.receive("""
    {"type":"control_request","request_id":"req-e2e","request":{"subtype":"can_use_tool",\
    "tool_name":"AskUserQuestion","input":{"questions":[{"question":"どの環境?",\
    "header":"Env","options":[{"label":"staging"},{"label":"prod","description":"本番"}],\
    "multiSelect":false}]},"tool_use_id":"toolu_e2e"}}
    """)

    // 1) 質問カードが pending で transcript に現れる。
    try await e2eWaitUntil {
        vm.transcript.contains { item in
            if case let .userQuestion(_, requestId, questions, _, state, _) = item {
                return requestId == "req-e2e"
                    && state == .pending
                    && questions.first?.question == "どの環境?"
                    && questions.first?.options.count == 2
            }
            return false
        }
    }

    // 2) 回答すると stdin へ allow の control_response が書かれる。
    let accepted = await vm.respondToUserQuestion(requestId: "req-e2e", answers: ["どの環境?": ["prod"]])
    #expect(accepted)

    try await e2eWaitUntil {
        transport.sentStrings().contains { $0.contains("control_response") }
    }
    let responseLine = try #require(
        transport.sentStrings().first { $0.contains("control_response") }
    )
    let obj = try #require(
        try JSONSerialization.jsonObject(with: Data(responseLine.utf8)) as? [String: Any]
    )
    let envelope = try #require(obj["response"] as? [String: Any])
    #expect(envelope["request_id"] as? String == "req-e2e")
    let inner = try #require(envelope["response"] as? [String: Any])
    #expect(inner["behavior"] as? String == "allow")
    let updatedInput = try #require(inner["updatedInput"] as? [String: Any])
    let answers = try #require(updatedInput["answers"] as? [String: Any])
    #expect(answers["どの環境?"] as? String == "prod")

    // 3) カードは answered へ遷移し、二重回答は拒否される。
    try await e2eWaitUntil {
        vm.transcript.contains { item in
            if case let .userQuestion(_, requestId, _, cardAnswers, state, _) = item {
                return requestId == "req-e2e"
                    && state == .answered
                    && cardAnswers == ["どの環境?": ["prod"]]
            }
            return false
        }
    }
    let second = await vm.respondToUserQuestion(requestId: "req-e2e", answers: ["どの環境?": ["staging"]])
    #expect(!second)
    #expect(transport.sentStrings().filter { $0.contains("control_response") }.count == 1)
}
