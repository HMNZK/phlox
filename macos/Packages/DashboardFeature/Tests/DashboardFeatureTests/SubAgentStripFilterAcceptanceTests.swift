import Testing
import Foundation
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（完了サブエージェントのストリップ除外）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// サブエージェントの処理が完了したらストリップから消す。ただし完了後も本文内のインライン
/// マーカー（subAgents に残る）から閲覧できるよう、`subAgents` 自体からは消さない
/// （ストリップ表示用に別途フィルタした一覧を提供する）。実行中・失敗は残す。
@Suite("SubAgent strip filter acceptance")
@MainActor
struct SubAgentStripFilterAcceptanceTests {

    @Test
    func completedSubAgentIsExcludedFromStripButKeptInSubAgents() async throws {
        let client = EventYieldingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        // A は実行中のまま、B は完了させる。
        client.yield(.subAgentStarted(toolUseId: "toolu_A", subagentType: "Explore", description: "running"))
        client.yield(.subAgentStarted(toolUseId: "toolu_B", subagentType: "Explore", description: "done"))
        client.yield(.subAgentCompleted(toolUseId: "toolu_B", status: "completed", summary: "", outputFile: nil))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_B" && $0.status == .completed }
        }

        // ストリップ用一覧: 完了した B は除外、実行中の A は残る。
        let stripIds = vm.stripSubAgents.map(\.id)
        #expect(stripIds.contains("toolu_A"), "running sub-agent must stay in the strip")
        #expect(!stripIds.contains("toolu_B"), "completed sub-agent must be removed from the strip")

        // subAgents 本体には B が残る（マーカー/ドロワーからの閲覧を保つ）。
        #expect(vm.subAgents.contains { $0.id == "toolu_B" },
                "completed sub-agent must remain in subAgents for marker/drawer access")
    }
}
