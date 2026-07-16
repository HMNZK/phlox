import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

@Suite("SubAgent routing white box")
@MainActor
struct SubAgentRoutingWhiteBoxTests {
    @Test
    func transcriptUsesOutputFileWhenReadable() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-subagent-\(UUID().uuidString).jsonl")
        try """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"from-file-prompt"}]}}
        {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"from-file-output"}]}}
        """.write(to: outputURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let client = EventYieldingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        client.yield(.subAgentStarted(toolUseId: "toolu_file", subagentType: "general-purpose", description: "File backed"))
        client.yield(.subAgentOutput(toolUseId: "toolu_file", text: "fallback-output"))
        client.yield(.subAgentCompleted(
            toolUseId: "toolu_file",
            status: "completed",
            summary: "fallback-summary",
            outputFile: outputURL.path
        ))

        _ = await waitUntil(timeoutNanoseconds: 2_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_file" && $0.status == .completed }
        }

        let transcript = vm.subAgentTranscript(for: "toolu_file")
        #expect(transcript.contains { $0.plainText.contains("from-file-output") })
        #expect(!transcript.contains { $0.plainText.contains("fallback-output") })
    }

    @Test
    func selectSubAgentStoresSelectedId() {
        let client = EventYieldingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )

        vm.selectSubAgent("toolu_selected")
        #expect(vm.selectedSubAgentId == "toolu_selected")
        vm.selectSubAgent(nil)
        #expect(vm.selectedSubAgentId == nil)
    }
}
