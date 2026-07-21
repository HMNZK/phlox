// 契約の正本: tasks/task-3.md — サブエージェントタブからのフォローアップ送信。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 背景: Claude Code CLI には実行中サブエージェントへの直接入力経路が無いため、
// フォローアップは「メインセッションへの通常ターン」として送り、プロンプトで対象
// サブエージェントを参照させる（SendMessage 相当の継続をメインの Claude に依頼する）。
//
// 契約（ChatSessionViewModel.sendSubAgentFollowUp(subAgent:text:)）:
//   - idle 時: client.turnStart がちょうど1回呼ばれ、入力テキストに「ユーザーの本文」と
//     「対象サブエージェントの description」と「対象サブエージェントの id」がすべて含まれる
//   - transcript にユーザーメッセージ（本文を含む）が追加される
//   - 送信後 status は .running になる
//   - 空文字・空白のみの本文は送信しない（turnStart 0 回・transcript 追加なし）

import Foundation
import os
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class CapturingFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let state = OSAllocatedUnfairLock(initialState: [[ChatInput]]())

    var turnStartInputs: [[ChatInput]] {
        state.withLock { $0 }
    }

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        state.withLock { $0.append(input) }
    }

    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

private func joinedText(_ inputs: [[ChatInput]]) -> String {
    inputs.flatMap { $0 }.compactMap { input -> String? in
        if case .text(let text) = input { return text }
        return nil
    }.joined(separator: "\n")
}

@MainActor
private func makeViewModel() -> (ChatSessionViewModel, CapturingFakeClient) {
    let client = CapturingFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-subagent-followup-test"
    )
    return (vm, client)
}

private func subAgent() -> SubAgentRef {
    SubAgentRef(
        id: "toolu_01FOLLOWUP",
        subagentType: "general-purpose",
        description: "認証モジュールの調査",
        status: .completed,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@Suite("Acceptance: サブエージェント・フォローアップ送信（task-3）")
struct AcceptanceSubAgentFollowUpTests {
    @Test @MainActor
    func 本文と対象サブエージェント参照を含めてターンを開始する() async throws {
        let (vm, client) = makeViewModel()

        try await vm.sendSubAgentFollowUp(subAgent: subAgent(), text: "その結果を表にまとめて")

        #expect(client.turnStartInputs.count == 1)
        let sent = joinedText(client.turnStartInputs)
        #expect(sent.contains("その結果を表にまとめて"))
        #expect(sent.contains("認証モジュールの調査"))
        #expect(sent.contains("toolu_01FOLLOWUP"))
    }

    @Test @MainActor
    func transcriptにユーザーメッセージが追加されrunningになる() async throws {
        let (vm, client) = makeViewModel()

        try await vm.sendSubAgentFollowUp(subAgent: subAgent(), text: "その結果を表にまとめて")

        _ = client
        let hasUserMessage = vm.transcript.contains { item in
            if case .userMessage(_, let text, _, _) = item {
                return text.contains("その結果を表にまとめて")
            }
            return false
        }
        #expect(hasUserMessage)
        #expect(vm.status == .running)
    }

    @Test @MainActor
    func 空白のみの本文は送信しない() async throws {
        let (vm, client) = makeViewModel()

        try await vm.sendSubAgentFollowUp(subAgent: subAgent(), text: "   \n  ")

        #expect(client.turnStartInputs.isEmpty)
        let hasUserMessage = vm.transcript.contains { item in
            if case .userMessage = item { return true }
            return false
        }
        #expect(hasUserMessage == false)
    }
}
