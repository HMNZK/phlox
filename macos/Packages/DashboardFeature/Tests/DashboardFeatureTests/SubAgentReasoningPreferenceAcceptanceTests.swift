import Testing
import Foundation
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（Bug B）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// reasoning(thinking) は output_file 側で空（署名のみ＝暗号化）になり落ちることがある一方、
/// stdout stream 由来のライブが thinking テキストを保持することがある。`subAgentTranscript(for:)`
/// が「項目数の多い方」を機械的に選ぶと、項目数の多い parsed（reasoning 無し）が選ばれてしまい
/// 「サブエージェント出力に Reasoning が出ない」退行を招く。片方だけが reasoning を持つときは
/// reasoning を失わない側を優先することを固定する。
@Suite("SubAgent reasoning preference acceptance")
@MainActor
struct SubAgentReasoningPreferenceAcceptanceTests {

    @Test
    func prefersLiveWhenOnlyLiveHasReasoning() async throws {
        // parsed（output_file）: reasoning 無し・項目数 3（tool×2 マージ + text）。
        let parsedJSONL = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a","name":"Bash","input":{"command":"ls"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_a","content":[{"type":"text","text":"OUT-A"}]}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_b","name":"Bash","input":{"command":"pwd"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_b","content":[{"type":"text","text":"OUT-B"}]}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"PARSED-FINAL"}]}}"#,
        ].joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-reasoning-\(UUID().uuidString).jsonl")
        try parsedJSONL.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let client = EventYieldingStructuredClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

        // ライブ: prompt + reasoning（thinking テキスト有り）。summary は空にして live を薄く保つ。
        client.yield(.subAgentStarted(toolUseId: "toolu_R", subagentType: "Explore", description: "reasoning test"))
        client.yield(.subAgentActivity(toolUseId: "toolu_R", kind: .prompt, itemId: nil, text: "PROMPT"))
        client.yield(.subAgentActivity(toolUseId: "toolu_R", kind: .reasoning, itemId: nil, text: "LIVE-REASONING-TEXT"))
        client.yield(.subAgentCompleted(toolUseId: "toolu_R", status: "completed", summary: "", outputFile: url.path))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_R" && $0.status == .completed }
        }

        let transcript = vm.subAgentTranscript(for: "toolu_R")
        // reasoning を持つライブが選ばれ、reasoning が表示に残る。
        #expect(transcript.contains {
            if case .reasoning(_, let text, _) = $0 { return text.contains("LIVE-REASONING-TEXT") }
            return false
        }, "reasoning present only in live must be preserved, not dropped for the larger parsed transcript")
    }
}
