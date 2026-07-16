import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// task-6 受け入れテスト（PM 著・実装役は編集禁止 / loopflow acceptance_tests）
//
// 契約: turnInterrupt は client.interrupt() が失敗しても状態を必ず .idle に復帰させ、
// 直後の再送信（sendText）が新しいターンとして開始できる。

private struct AcceptanceInterruptFailure: Error {}

private final class ThrowingInterruptClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var turnTexts: [String] = []

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        let text = input.compactMap { item in
            if case .text(let value) = item { value } else { nil }
        }.joined()
        lock.withLock { turnTexts.append(text) }
    }

    func resume(sessionRef: String) async throws {}

    func interrupt() async throws {
        throw AcceptanceInterruptFailure()
    }

    func close() async {
        continuation.finish()
    }

    func recordedTurnTexts() -> [String] {
        lock.withLock { turnTexts }
    }
}

@Test @MainActor
func turnInterrupt_recoversToIdleEvenWhenClientInterruptFails_andResendStartsNewTurn() async throws {
    let client = ThrowingInterruptClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    try await vm.sendText("first", submit: true)
    #expect(vm.status == .running)

    _ = try? await vm.turnInterrupt()

    // 契約1: client.interrupt() が throw しても running に固着しない。
    #expect(vm.status == .idle, "中止失敗時に status が復帰していない: \(vm.status)")

    // 契約2: 中止直後の再送信が新しいターンとして client に届く。
    try await vm.sendText("retry", submit: true)
    #expect(client.recordedTurnTexts() == ["first", "retry"])
    #expect(vm.status == .running)
}
