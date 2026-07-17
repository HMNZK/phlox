// PM 裁定の証拠テスト（task-1 stage2c MUST の独立機序）:
// turnStart 応答待ち中にプロセスが死ぬ（= client.turnStart が throw する）ケースは、
// Kit の合成終端イベントに依存せず、VM の sendText catch（A3 契約）が status を .idle に
// 戻して終端化する。停止ボタンの running 固着・interrupt 空振りは生じない。

import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private struct ProcessDiedError: Error {}

/// turnStart が常に失敗する（EOF/プロセス死相当）クライアント。
private final class TurnStartThrowingClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        throw ProcessDiedError()
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        continuation.finish()
    }
}

@Suite("PM: turnStart 失敗時の終端化（task-1 裁定証拠）")
@MainActor
struct PMTurnStartFailureTerminalizationTests {
    @Test func turnStart応答待ち中のプロセス死は実行中表示を残さない() async throws {
        let client = TurnStartThrowingClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        await #expect(throws: ProcessDiedError.self) {
            try await vm.sendText("hello", submit: true)
        }
        #expect(!vm.showsProcessingIndicator)
        #expect(vm.status == .idle)
    }
}
