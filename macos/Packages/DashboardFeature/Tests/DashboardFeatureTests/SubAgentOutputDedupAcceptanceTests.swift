import Testing
import Foundation
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（サブエージェント出力の重複表示）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 非同期サブエージェントの完了時、同一の最終レポートが複数経路（完了 tool_result 由来の
/// `.subAgentOutput` と `.subAgentCompleted` の summary、あるいは inline 最終テキストと summary）で
/// サブエージェント transcript に入り、同じ本文が2回表示されることがある。サブエージェント
/// transcript は同一本文の agentMessage を二重に持たない（＝重複表示しない）ことを固定する。
@Suite("SubAgent output dedup acceptance")
@MainActor
struct SubAgentOutputDedupAcceptanceTests {

    private static let report = "loopflow 調査結果\n概要: これはサブエージェントの最終レポート本文である。"

    @Test
    func identicalReportFromOutputAndSummaryIsShownOnce() async throws {
        let client = EventYieldingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        // 完了レポートが .subAgentOutput と .subAgentCompleted(summary) の両方で同一本文として届く。
        client.yield(.subAgentStarted(toolUseId: "toolu_D", subagentType: "Explore", description: "dup test"))
        client.yield(.subAgentOutput(toolUseId: "toolu_D", text: Self.report))
        client.yield(.subAgentCompleted(toolUseId: "toolu_D", status: "completed", summary: Self.report, outputFile: nil))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_D" && $0.status == .completed }
        }

        let transcript = vm.subAgentTranscript(for: "toolu_D")
        let reportCount = transcript.filter { item in
            if case .agentMessage(_, let text, _) = item {
                return text.contains("これはサブエージェントの最終レポート本文である")
            }
            return false
        }.count
        #expect(reportCount == 1, "identical report must appear exactly once, got \(reportCount)")
    }

    /// 実測ケース: 同一レポートが inline 最終テキスト（.subAgentActivity(.message)）と完了出力
    /// （.subAgentOutput=-output）の両方で届いても1回だけ表示される（-output が inline と同一本文なら落とす）。
    @Test
    func identicalReportFromInlineMessageAndOutputIsShownOnce() async throws {
        let client = EventYieldingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.yield(.subAgentStarted(toolUseId: "toolu_IM", subagentType: "Explore", description: "inline+output"))
        client.yield(.subAgentActivity(toolUseId: "toolu_IM", kind: .message, itemId: nil, text: Self.report))
        client.yield(.subAgentOutput(toolUseId: "toolu_IM", text: Self.report))
        client.yield(.subAgentCompleted(toolUseId: "toolu_IM", status: "completed", summary: "", outputFile: nil))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_IM" && $0.status == .completed }
        }

        let n = vm.subAgentTranscript(for: "toolu_IM").filter { item in
            if case .agentMessage(_, let text, _) = item {
                return text.contains("これはサブエージェントの最終レポート本文である")
            }
            return false
        }.count
        #expect(n == 1, "identical report from inline message and output must appear once, got \(n)")
    }

    /// dedup はレポート系2チャネル間に限定し、サブエージェントが inline で正当に同一本文の
    /// メッセージを複数回出すケース（.subAgentActivity(.message)）は両方残す（黙って落とさない）。
    @Test
    func distinctInlineMessagesWithIdenticalTextAreBothKept() async throws {
        let client = EventYieldingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.yield(.subAgentStarted(toolUseId: "toolu_M", subagentType: "Explore", description: "repeat"))
        client.yield(.subAgentActivity(toolUseId: "toolu_M", kind: .message, itemId: nil, text: "了解しました"))
        client.yield(.subAgentActivity(toolUseId: "toolu_M", kind: .message, itemId: nil, text: "了解しました"))
        // 完了を最後に流し、その到達で「先行2メッセージが両方処理済み」を保証してから数える
        // （メッセージ本文の存在だけを待つと1件目で早期に返り2件目未処理のまま数えてしまう）。
        client.yield(.subAgentCompleted(toolUseId: "toolu_M", status: "completed", summary: "DONE-MARKER", outputFile: nil))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_M" && $0.status == .completed }
        }
        let n = vm.subAgentTranscript(for: "toolu_M").filter {
            if case .agentMessage(_, let t, _) = $0 { return t == "了解しました" }
            return false
        }.count
        #expect(n == 2, "distinct inline messages with identical text must both be kept, got \(n)")
    }
}
