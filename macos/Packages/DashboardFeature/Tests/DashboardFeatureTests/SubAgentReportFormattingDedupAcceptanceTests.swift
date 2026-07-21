import Testing
import Foundation
import AgentDomain
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-1（サブエージェント最終レポートの二重表示・整形差バグ）受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 完了したサブエージェントには必ずレポート系チャネル（`-output`/`-summary`）のアイテムが1つ存在する。
/// 現行 dedup（`ChatSubAgentModel.appendSubAgentTranscriptItem`）は「片方がレポート系 id かつ trim 後の
/// 本文が**完全一致**」のときしか重複を落とさないため、inline 最終テキストとレポート系が **同一レポートだが
/// 整形（空白・改行・連結時の区切り）だけ異なる** 場合に二重表示される（症状: 完了後に最終レポートが2回）。
///
/// 本スイートは次を固定する:
/// 1. 整形（改行↔空白）のみ異なる同一レポートは1回だけ表示（`newlineVsSpace`）。
/// 2. inline が複数断片を区切り無しで連結した結果、レポート系と空白位置だけ違う場合も1回（`missingSeparator`）。
/// 3. 本文が実質（非空白）で異なるレポートは、過剰 dedup せず両方残す（`genuinelyDifferent`）。
///
/// 併せて ADR 0025 §7（レポート系が絡まない inline 同士の正当な同一本文は両方残す）を回帰させないこと。
/// これは既存 `SubAgentOutputDedupAcceptanceTests.distinctInlineMessagesWithIdenticalTextAreBothKept` が固定する。
@Suite("SubAgent report formatting dedup acceptance")
@MainActor
struct SubAgentReportFormattingDedupAcceptanceTests {

    private func makeViewModel(_ client: EventYieldingStructuredClient) async throws -> ChatSessionViewModel {
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        return vm
    }

    private func reportMessageCount(_ vm: ChatSessionViewModel, id: String, marker: String) -> Int {
        vm.subAgentTranscript(for: id).filter { item in
            if case .agentMessage(_, let text, _) = item {
                return text.contains(marker)
            }
            return false
        }.count
    }

    /// inline は段落間に改行、summary は同一レポートを空白区切りで運ぶ（整形のみ差）。1回だけ表示されること。
    @Test
    func newlineVsSpaceFormattingSameReportIsShownOnce() async throws {
        let client = EventYieldingStructuredClient()
        let vm = try await makeViewModel(client)

        let marker = "根本原因はレースコンディションである"
        let inline = "調査結果\n\n\(marker)。\n詳細: itemId が毎回変わるため。"
        let summary = "調査結果 \(marker)。 詳細: itemId が毎回変わるため。"

        client.yield(.subAgentStarted(toolUseId: "toolu_NL", subagentType: "Explore", description: "newline vs space"))
        client.yield(.subAgentActivity(toolUseId: "toolu_NL", kind: .message, itemId: "msg-final", text: inline))
        client.yield(.subAgentCompleted(toolUseId: "toolu_NL", status: "completed", summary: summary, outputFile: nil))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_NL" && $0.status == .completed }
        }

        let n = reportMessageCount(vm, id: "toolu_NL", marker: marker)
        #expect(n == 1, "same report differing only in newline/space formatting must appear once, got \(n)")
    }

    /// inline が2断片を区切り無しで連結（"…である。対策は…"）、summary は区切りスペースあり（"…である。 対策は…"）。
    /// 空白位置だけの差でも1回だけ表示されること（trim だけでは落ちない＝空白非依存の比較が要る）。
    @Test
    func missingSeparatorInInlineSameReportIsShownOnce() async throws {
        let client = EventYieldingStructuredClient()
        let vm = try await makeViewModel(client)

        let part1 = "根本原因は競合状態である。"
        let part2 = "対策はitemIdの安定化。"
        let marker = "対策はitemIdの安定化"

        client.yield(.subAgentStarted(toolUseId: "toolu_SEP", subagentType: "Explore", description: "missing separator"))
        // 同一 itemId の2断片 → appendMergeableSubAgentActivity が existingText + text で区切り無し連結
        client.yield(.subAgentActivity(toolUseId: "toolu_SEP", kind: .message, itemId: "msg-s", text: part1))
        client.yield(.subAgentActivity(toolUseId: "toolu_SEP", kind: .message, itemId: "msg-s", text: part2))
        // summary は区切りスペースあり
        client.yield(.subAgentCompleted(toolUseId: "toolu_SEP", status: "completed", summary: part1 + " " + part2, outputFile: nil))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_SEP" && $0.status == .completed }
        }

        let n = reportMessageCount(vm, id: "toolu_SEP", marker: marker)
        #expect(n == 1, "same report differing only in a separator space must appear once, got \(n)")
    }

    /// 過剰 dedup ガード: inline とレポート系の本文が実質（非空白）で異なるなら、両方残す（黙って落とさない）。
    @Test
    func genuinelyDifferentInlineAndSummaryAreBothKept() async throws {
        let client = EventYieldingStructuredClient()
        let vm = try await makeViewModel(client)

        let inline = "詳細レポート: モジュールAに競合状態が3件ある。"
        let summary = "要約: 調査を完了した。"

        client.yield(.subAgentStarted(toolUseId: "toolu_DIF", subagentType: "Explore", description: "genuinely different"))
        client.yield(.subAgentActivity(toolUseId: "toolu_DIF", kind: .message, itemId: "msg-d", text: inline))
        client.yield(.subAgentCompleted(toolUseId: "toolu_DIF", status: "completed", summary: summary, outputFile: nil))
        try await waitUntil(timeoutNanoseconds: 5_000_000_000) {
            vm.subAgents.contains { $0.id == "toolu_DIF" && $0.status == .completed }
        }

        let inlineCount = reportMessageCount(vm, id: "toolu_DIF", marker: "モジュールAに競合状態が3件ある")
        let summaryCount = reportMessageCount(vm, id: "toolu_DIF", marker: "調査を完了した")
        #expect(inlineCount == 1, "distinct inline report must be kept, got \(inlineCount)")
        #expect(summaryCount == 1, "distinct summary must be kept, got \(summaryCount)")
    }
}
