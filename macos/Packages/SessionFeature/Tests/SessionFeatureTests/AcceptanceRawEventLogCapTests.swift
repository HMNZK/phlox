import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

// subagent-session-cpu run / task-3 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約: ChatSessionViewModel.rawEventLog は直近 500 件で頭打ちになる
// （最古から破棄・最新を保持）。全イベントを無条件に蓄積し続けるメモリ肥大
// （docs/phase0.md 欠陥3）の修正契約である。

private final class CapFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 3_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@Test @MainActor
func rawEventLogIsCappedAtFiveHundredKeepingNewest() async throws {
    let client = CapFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-raweventlog-cap-test"
    )

    for i in 0..<520 {
        client.yield(.agentMessageDelta(itemId: "item-1", "d\(i) "))
    }

    try await waitUntil { vm.rawEventLog.contains { $0.contains("\"d519 \"") } }
    #expect(vm.rawEventLog.count <= 500)
    // 最新は保持し、最古（d0〜d19）は破棄されている。
    #expect(vm.rawEventLog.contains { $0.contains("\"d519 \"") })
    #expect(!vm.rawEventLog.contains { $0.contains("\"d0 \"") })
    #expect(!vm.rawEventLog.contains { $0.contains("\"d19 \"") })
}
