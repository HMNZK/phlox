import Foundation
import Testing
@testable import SessionFeature

// フェーズ1で PM が凍結した受け入れテスト（task-1 契約）。
// 実装役はこのファイルのアサーションを変更してはならない。
// テストハーネスの欠陥を発見した場合のみ、PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約する公開 API:
//   struct InputHistoryEntry: Identifiable, Equatable, Sendable { let id: String; let text: String; init(id:text:) }
//   enum InputHistoryPolicy {
//     static func entries(from transcript: [ChatItem]) -> [InputHistoryEntry]
//     static func scrubberTicks(from entries: [InputHistoryEntry], cap: Int) -> [InputHistoryEntry]
//   }
@Suite("InputHistoryPolicy acceptance (task-1)")
struct InputHistoryPolicyAcceptanceTests {

    private func ts(_ n: Double) -> Date { Date(timeIntervalSince1970: n) }

    // entries: transcript から .userMessage だけを、transcript の並び順（古い→新しい）のまま抽出する。
    @Test
    func entriesExtractsOnlyUserMessagesPreservingTranscriptOrder() {
        let transcript: [ChatItem] = [
            .userMessage(id: "u1", text: "first prompt", timestamp: ts(1)),
            .agentMessage(id: "a1", text: "answer 1", timestamp: ts(2)),
            .reasoning(id: "r1", text: "thinking", timestamp: ts(3)),
            .userMessage(id: "u2", text: "second prompt", timestamp: ts(4)),
            .commandExecution(id: "c1", command: "ls", output: "out", timestamp: ts(5)),
            .userMessage(id: "u3", text: "third prompt", timestamp: ts(6)),
            .error(id: "e1", message: "boom", timestamp: ts(7)),
        ]

        let entries = InputHistoryPolicy.entries(from: transcript)

        #expect(entries.map(\.id) == ["u1", "u2", "u3"])
        #expect(entries.map(\.text) == ["first prompt", "second prompt", "third prompt"])
    }

    // ユーザー入力が1件も無ければ空。
    @Test
    func entriesEmptyWhenNoUserMessages() {
        let transcript: [ChatItem] = [
            .agentMessage(id: "a1", text: "hi", timestamp: ts(1)),
            .reasoning(id: "r1", text: "hmm", timestamp: ts(2)),
        ]
        #expect(InputHistoryPolicy.entries(from: transcript).isEmpty)
    }

    // 空 transcript は空。
    @Test
    func entriesEmptyForEmptyTranscript() {
        #expect(InputHistoryPolicy.entries(from: []).isEmpty)
    }

    // entry.id は元 .userMessage の id と一致する（＝トランスクリプトへのジャンプ先として有効）。
    @Test
    func entryIdMatchesSourceUserMessageIdForJumpTargeting() {
        let transcript: [ChatItem] = [
            .userMessage(id: "msg-42", text: "jump here", timestamp: ts(1)),
        ]
        let entry = InputHistoryPolicy.entries(from: transcript).first
        #expect(entry?.id == "msg-42")
        #expect(entry?.text == "jump here")
    }

    // scrubberTicks: 件数が cap 以下なら全件を並び順のまま返す。
    @Test
    func scrubberTicksReturnsAllWhenWithinCap() {
        let entries = [
            InputHistoryEntry(id: "u1", text: "a"),
            InputHistoryEntry(id: "u2", text: "b"),
            InputHistoryEntry(id: "u3", text: "c"),
        ]
        let ticks = InputHistoryPolicy.scrubberTicks(from: entries, cap: 5)
        #expect(ticks.map(\.id) == ["u1", "u2", "u3"])
    }

    // scrubberTicks: cap 超過なら末尾（最新）cap 件を並び順のまま返す（最後の要素＝現在位置）。
    @Test
    func scrubberTicksKeepsMostRecentWhenExceedingCapPreservingOrder() {
        let entries = (1...10).map { InputHistoryEntry(id: "u\($0)", text: "t\($0)") }
        let ticks = InputHistoryPolicy.scrubberTicks(from: entries, cap: 3)
        #expect(ticks.map(\.id) == ["u8", "u9", "u10"])
    }

    // scrubberTicks: cap が 0 以下なら空。
    @Test
    func scrubberTicksEmptyWhenCapNonPositive() {
        let entries = [InputHistoryEntry(id: "u1", text: "a")]
        #expect(InputHistoryPolicy.scrubberTicks(from: entries, cap: 0).isEmpty)
    }
}
