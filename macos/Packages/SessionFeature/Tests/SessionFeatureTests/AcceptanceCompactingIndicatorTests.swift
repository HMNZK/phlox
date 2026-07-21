// 契約の正本: tasks/task-2.md — compaction（会話履歴圧縮）中インジケーターの状態機械。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 契約（ChatSessionViewModel.isCompacting）:
//   - "/compact" を submit 送信すると isCompacting == true（圧縮の待ち時間をアニメーション表示する根拠状態）
//   - 引数付き "/compact 要約方針..." も同様に true
//   - .compactionBoundary 受信で false へ戻る
//   - .turnCompleted / .turnInterrupted / .error でも false へ戻る（取りこぼしフェイルセーフ）
//   - 通常テキストの送信では true にならない

import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class CompactingFakeClient: StructuredAgentClient, @unchecked Sendable {
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
    timeoutNanoseconds: UInt64 = 1_500_000_000,
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

@MainActor
private func makeViewModel() -> (ChatSessionViewModel, CompactingFakeClient) {
    let client = CompactingFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-compacting-test"
    )
    return (vm, client)
}

@Suite("Acceptance: compacting インジケーター（task-2）")
struct AcceptanceCompactingIndicatorTests {
    @Test @MainActor
    func compactコマンド送信でisCompactingが立つ() async throws {
        let (vm, _) = makeViewModel()
        #expect(vm.isCompacting == false)

        try await vm.sendText("/compact", submit: true)

        #expect(vm.isCompacting)
    }

    @Test @MainActor
    func 引数付きcompactコマンドでも立つ() async throws {
        let (vm, _) = makeViewModel()

        try await vm.sendText("/compact 直近の設計判断を残して", submit: true)

        #expect(vm.isCompacting)
    }

    @Test @MainActor
    func compactionBoundary受信で解除される() async throws {
        let (vm, client) = makeViewModel()
        try await vm.sendText("/compact", submit: true)
        #expect(vm.isCompacting)

        client.yield(.compactionBoundary(trigger: "manual", preTokens: 100_000))
        try await waitUntil { vm.isCompacting == false }

        #expect(vm.isCompacting == false)
    }

    @Test @MainActor
    func turnCompletedでもフェイルセーフ解除される() async throws {
        let (vm, client) = makeViewModel()
        try await vm.sendText("/compact", submit: true)
        #expect(vm.isCompacting)

        client.yield(.turnCompleted(nativeSessionId: nil))
        try await waitUntil { vm.isCompacting == false }

        #expect(vm.isCompacting == false)
    }

    @Test @MainActor
    func turnInterruptedでもフェイルセーフ解除される() async throws {
        let (vm, client) = makeViewModel()
        try await vm.sendText("/compact", submit: true)
        #expect(vm.isCompacting)

        client.yield(.turnInterrupted(nativeSessionId: nil))
        try await waitUntil { vm.isCompacting == false }

        #expect(vm.isCompacting == false)
    }

    @Test @MainActor
    func 通常テキスト送信では立たない() async throws {
        let (vm, _) = makeViewModel()

        try await vm.sendText("compact について教えて", submit: true)

        #expect(vm.isCompacting == false)
    }
}
