import Testing
import Foundation
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-3（バグ3コア）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// サブエージェント（Agent/Task ツール由来）の出力がメイン transcript に入らず、
/// サブエージェント別 transcript へ隔離され、完了後も subAgents に残り、
/// メインには `.subAgentMarker` が1つ置かれることを、VM の公開状態で検証する。
/// EventYieldingStructuredClient に、ClaudeChatClient が実データで放出すべき
/// 新イベント（subAgentStarted/Activity/Output/Completed）を注入して駆動する。
@Suite("SubAgent routing acceptance")
@MainActor
struct SubAgentRoutingAcceptanceTests {

    private static let subToolUseId = "toolu_01QCyoxs2rMLaBJYg3FRGfFo"

    private func makeVM(_ client: EventYieldingStructuredClient) -> ChatSessionViewModel {
        ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
    }

    private func drive(_ client: EventYieldingStructuredClient) {
        client.yield(.subAgentStarted(
            toolUseId: Self.subToolUseId,
            subagentType: "general-purpose",
            description: "Output three lines"
        ))
        client.yield(.subAgentActivity(
            toolUseId: Self.subToolUseId,
            kind: .prompt,
            itemId: nil,
            text: "Output three short lines: LINE-A, then LINE-B, then LINE-C."
        ))
        client.yield(.subAgentOutput(toolUseId: Self.subToolUseId, text: "LINE-A\nLINE-B\nLINE-C"))
        client.yield(.subAgentCompleted(
            toolUseId: Self.subToolUseId,
            status: "completed",
            summary: "LINE-A\nLINE-B\nLINE-C",
            outputFile: nil
        ))
        client.yield(.agentMessageDelta(itemId: "parent-done", "DONE"))
        client.yield(.turnCompleted(nativeSessionId: nil))
    }

    @Test
    func subAgentOutputIsIsolatedFromMainTranscript() async throws {
        let client = EventYieldingStructuredClient()
        let vm = makeVM(client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        drive(client)

        // 全イベント処理完了を待つ（サブエージェント完了 かつ 親 DONE がメインに反映）。
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == Self.subToolUseId && $0.status == .completed }
            && vm.transcript.contains { $0.plainText.contains("DONE") }
        }

        // (a) サブエージェント出力はメイン transcript に一切出ない。
        #expect(!vm.transcript.contains { $0.plainText.contains("LINE-A") })
        #expect(!vm.transcript.contains { $0.plainText.contains("LINE-B") })
        #expect(!vm.transcript.contains { $0.plainText.contains("LINE-C") })
        // 親の発言はメインに残る。
        #expect(vm.transcript.contains { $0.plainText.contains("DONE") })
    }

    @Test
    func mainTranscriptHasCompactSubAgentMarker() async throws {
        let client = EventYieldingStructuredClient()
        let vm = makeVM(client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        drive(client)
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == Self.subToolUseId && $0.status == .completed }
        }

        // メイン transcript に該当サブエージェントのマーカーが1つある。
        let markers = vm.transcript.filter {
            if case .subAgentMarker(let id, _, _, _) = $0 { return id == Self.subToolUseId }
            return false
        }
        #expect(markers.count == 1)
    }

    @Test
    func subAgentPersistsAfterCompletion() async throws {
        let client = EventYieldingStructuredClient()
        let vm = makeVM(client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        drive(client)
        // 完了イベント処理まで待つ（存在だけでなく completed 遷移を待つ）。
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == Self.subToolUseId && $0.status == .completed }
        }

        // 完了後も subAgents に残る（消えない＝上の待機が成立する時点で存在）。ラベル情報を保持。
        let ref = try #require(vm.subAgents.first { $0.id == Self.subToolUseId })
        #expect(ref.status == .completed)
        #expect(ref.subagentType == "general-purpose")
        #expect(ref.description == "Output three lines")
    }

    @Test
    func subAgentTranscriptContainsOutputViaFallback() async throws {
        let client = EventYieldingStructuredClient()
        let vm = makeVM(client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        drive(client)
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == Self.subToolUseId && $0.status == .completed }
        }

        // outputFile が nil のためフォールバック（プロンプト＋出力＋サマリ）で出力を含む。
        let sub = vm.subAgentTranscript(for: Self.subToolUseId)
        #expect(!sub.isEmpty)
        #expect(sub.contains { $0.plainText.contains("LINE-A") })
    }
}
