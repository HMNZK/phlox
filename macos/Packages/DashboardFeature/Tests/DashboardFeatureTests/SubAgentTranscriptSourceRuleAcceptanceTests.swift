import Testing
import Foundation
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// 受け入れテスト（不変）。
///
/// 契約: サブエージェント transcript のソース選択は **2 通り** に整理する。
/// 1. 永続ファイル（parsed）が読めれば parsed。
/// 2. 読めなければライブ。
///
/// 例外は ADR 0025 の reasoning 優先のみ（暗号化されず live にだけ推論本文が残る個体で
/// reasoning を失わないため）。`SubAgentReasoningPreferenceAcceptanceTests` が別途凍結している。
///
/// 旧規則にあった「項目数の多い方を採る」件数タイブレークは廃止する。ライブは各ツールを
/// tool_use と tool_result の2件に水増ししていたため件数比較が信用できず、ADR 0106 で
/// `.completed` の特例を足して塞いだが、これは対症療法だった。ライブ側を
/// 「1 ツールコール = 1 セル」に直した以上、件数で権威を決める必要がなくなる。
@Suite("SubAgent transcript source rule acceptance")
@MainActor
struct SubAgentTranscriptSourceRuleAcceptanceTests {

    private func makeParsedFile() throws -> URL {
        let parsedJSONL = [
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_a","name":"Bash","input":{"command":"ls"}}]}}"#,
            #"{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_a","content":[{"type":"text","text":"OUT-A"}]}]}}"#,
            #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"PERSISTED-NARRATION-XYZ"}]}}"#,
        ].joined(separator: "\n")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-source-rule-\(UUID().uuidString).jsonl")
        try parsedJSONL.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeViewModel() async throws -> (ChatSessionViewModel, EventYieldingStructuredClient) {
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
    func failedSubAgentAlsoPrefersPersistedTranscript() async throws {
        let url = try makeParsedFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let (vm, client) = try await makeViewModel()

        // ライブは項目数だけ多い（prompt + tool 5 件 = 6 > parsed の 2 件）。
        // 旧「件数の多い方」規則ならライブが勝ち、永続側のナレーションが欠落する。
        client.yield(.subAgentStarted(toolUseId: "toolu_F", subagentType: "Explore", description: "failed source rule"))
        client.yield(.subAgentActivity(toolUseId: "toolu_F", kind: .prompt, itemId: nil, text: "PROMPT"))
        for index in 0..<5 {
            client.yield(.subAgentActivity(toolUseId: "toolu_F", kind: .tool, itemId: nil, text: "live tool \(index)"))
        }
        client.yield(.subAgentCompleted(toolUseId: "toolu_F", status: "failed", summary: "", outputFile: url.path))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_F" && $0.status == .failed }
        }

        let transcript = vm.subAgentTranscript(for: "toolu_F")
        #expect(transcript.contains {
            if case .agentMessage(_, let text, _) = $0 { return text.contains("PERSISTED-NARRATION-XYZ") }
            return false
        }, "failed でも永続ファイルが読めるなら parsed を採ること（件数タイブレークで live に負けない）")
    }

    @Test
    func runningSubAgentWithoutPersistedFileFallsBackToLive() async throws {
        let (vm, client) = try await makeViewModel()

        client.yield(.subAgentStarted(toolUseId: "toolu_R", subagentType: "Explore", description: "running fallback"))
        client.yield(.subAgentActivity(toolUseId: "toolu_R", kind: .tool, itemId: "toolu_x", text: "Bash running"))
        client.yield(.subAgentActivity(toolUseId: "toolu_R", kind: .toolResult, itemId: "toolu_x", text: "LIVE-OUT"))

        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgentTranscript(for: "toolu_R").contains {
                if case .commandExecution(_, _, let output, _) = $0 { return output.contains("LIVE-OUT") }
                return false
            }
        }

        let transcript = vm.subAgentTranscript(for: "toolu_R")
        let commandCount = transcript.reduce(into: 0) { acc, item in
            if case .commandExecution = item { acc += 1 }
        }
        #expect(commandCount == 1, "永続ファイルが無い実行中はライブを使い、かつ 1 ツール = 1 セル。実際=\(commandCount)")
    }
}
