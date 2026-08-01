import Testing
import Foundation
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（サブエージェントタブを閉じる）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 閉じる操作は「タブ列（ストリップ）から取り除く」だけで、`subAgents` 本体と本文の
/// インラインマーカーは残す（完了済みサブエージェントと同じ扱い）。閉じた id は sticky で、
/// 以後の更新イベントでストリップへ復活しない。
@Suite("SubAgent dismiss acceptance")
@MainActor
struct SubAgentDismissAcceptanceTests {

    private func startedViewModel() async throws -> (ChatSessionViewModel, EventYieldingStructuredClient) {
        let client = EventYieldingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        return (vm, client)
    }

    @Test
    func dismissedSubAgentLeavesStripButStaysInSubAgents() async throws {
        let (vm, client) = try await startedViewModel()
        client.yield(.subAgentStarted(toolUseId: "toolu_keep", subagentType: "Explore", description: "keep"))
        client.yield(.subAgentStarted(toolUseId: "toolu_drop", subagentType: "persona-reviewer", description: "drop"))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.stripSubAgents.count == 2
        }

        vm.dismissSubAgent("toolu_drop")

        let stripIds = vm.stripSubAgents.map(\.id)
        #expect(!stripIds.contains("toolu_drop"), "dismissed sub-agent must leave the strip")
        #expect(stripIds.contains("toolu_keep"), "other sub-agents must stay in the strip")
        #expect(vm.subAgents.contains { $0.id == "toolu_drop" },
                "dismissed sub-agent must remain in subAgents for marker/drawer access")
    }

    @Test
    func dismissingSelectedSubAgentReturnsSelectionToMain() async throws {
        let (vm, client) = try await startedViewModel()
        client.yield(.subAgentStarted(toolUseId: "toolu_sel", subagentType: "Explore", description: "selected"))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.stripSubAgents.contains { $0.id == "toolu_sel" }
        }
        vm.selectSubAgent("toolu_sel")

        vm.dismissSubAgent("toolu_sel")

        #expect(vm.selectedSubAgentId == nil, "dismissing the selected sub-agent must return to the main chat")
    }

    @Test
    func dismissingUnselectedSubAgentKeepsCurrentSelection() async throws {
        let (vm, client) = try await startedViewModel()
        client.yield(.subAgentStarted(toolUseId: "toolu_sel", subagentType: "Explore", description: "selected"))
        client.yield(.subAgentStarted(toolUseId: "toolu_other", subagentType: "Explore", description: "other"))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.stripSubAgents.count == 2
        }
        vm.selectSubAgent("toolu_sel")

        vm.dismissSubAgent("toolu_other")

        #expect(vm.selectedSubAgentId == "toolu_sel", "dismissing another sub-agent must not change the selection")
    }

    @Test
    func dismissedSubAgentDoesNotReappearAfterFurtherEvents() async throws {
        let (vm, client) = try await startedViewModel()
        client.yield(.subAgentStarted(toolUseId: "toolu_drop", subagentType: "persona-reviewer", description: "drop"))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.stripSubAgents.contains { $0.id == "toolu_drop" }
        }
        vm.dismissSubAgent("toolu_drop")

        // 後着イベント（失敗確定など）で同じ id が更新されても、ストリップには戻らない。
        client.yield(.subAgentCompleted(toolUseId: "toolu_drop", status: "failed", summary: "boom", outputFile: nil))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_drop" && $0.status == .failed }
        }

        #expect(!vm.stripSubAgents.contains { $0.id == "toolu_drop" },
                "a dismissed sub-agent must stay out of the strip after later events")
    }
}
