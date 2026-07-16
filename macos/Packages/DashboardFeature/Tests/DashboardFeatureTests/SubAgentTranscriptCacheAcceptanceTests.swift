import Testing
import Foundation
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-4（バグ3 UI）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// `subAgentTranscript(for:)` は同期ファイル読取りを含むため、ドロワー/タイルが描画のたびに
/// 呼んでも実ファイル読取りが繰り返されないよう（outputFile をキーに）キャッシュされること。
/// 検証: 一時 output_file を書き、1回目取得後にファイルを削除しても2回目が同一結果を返す
/// （キャッシュ済み＝再読み込みしていない）。キャッシュが無ければ2回目はフォールバックへ落ち失敗する。
@Suite("SubAgent transcript cache acceptance")
@MainActor
struct SubAgentTranscriptCacheAcceptanceTests {

    @Test
    func subAgentTranscriptCachesFileRead() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("subagent-cache-\(UUID().uuidString).jsonl")
        let jsonl = #"{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"CACHED-LINE"}]}}"#
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
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

        client.yield(.subAgentStarted(toolUseId: "toolu_C", subagentType: "general-purpose", description: "cache test"))
        client.yield(.subAgentCompleted(toolUseId: "toolu_C", status: "completed", summary: "s", outputFile: url.path))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_C" && $0.status == .completed }
        }

        // 1回目: ファイルから読む。
        let first = vm.subAgentTranscript(for: "toolu_C")
        #expect(first.contains { $0.plainText.contains("CACHED-LINE") })

        // ファイルを削除してから2回目: キャッシュ済みなら同一結果（再読み込みしない）。
        try FileManager.default.removeItem(at: url)
        let second = vm.subAgentTranscript(for: "toolu_C")
        #expect(second.contains { $0.plainText.contains("CACHED-LINE") })
        #expect(second.count == first.count)
    }
}
