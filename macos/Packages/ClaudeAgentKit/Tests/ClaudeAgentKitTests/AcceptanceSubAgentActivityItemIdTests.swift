import Testing
import Foundation
import StructuredChatKit
@testable import ClaudeAgentKit

// subagent-session-cpu run / task-1 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約: ClaudeChatClient は parent_tool_use_id 付き assistant content（サブエージェントの
// text/thinking）を `subAgentActivity` に隔離する際、メイン経路（handleAssistantContent の
// "\(messageId):\(type)"）と同じ粒度の識別子を `itemId` として運ぶ:
// - 同一 message id・同一 content 種別の断片 → 同一の非 nil itemId
// - 別 message id → 別 itemId
// - text と thinking（種別が異なる）→ 別 itemId
// itemId の具体的な文字列形式は凍結しない（等価性の意味論のみ凍結）。

// MARK: - 最小 transport（他ファイルの private 版は不可視のため自前定義）

private final class ItemIdMockLineTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { captured = $0 }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}
    func close() async { continuation?.finish() }
    func stderrTail() async -> String? { nil }

    func receive(_ line: String) { continuation?.yield(Data(line.utf8)) }
}

@Suite("SubAgent activity itemId acceptance")
struct AcceptanceSubAgentActivityItemIdTests {

    private static let subToolUseId = "toolu_SA_ITEMID"

    private static let lines: [String] = [
        #"{"type":"system","subtype":"init","session_id":"S1","tools":["Task","Bash","Agent"]}"#,
        #"{"type":"assistant","message":{"id":"m1","role":"assistant","content":[{"type":"tool_use","id":"toolu_SA_ITEMID","name":"Agent","input":{"subagent_type":"general-purpose","description":"stream probe","prompt":"stream words","run_in_background":false}}]},"parent_tool_use_id":null,"session_id":"S1"}"#,
        #"{"type":"system","subtype":"task_started","task_id":"t1","tool_use_id":"toolu_SA_ITEMID","task_type":"local_agent","subagent_type":"general-purpose","description":"stream probe"}"#,
        #"{"type":"assistant","message":{"id":"mS1","role":"assistant","content":[{"type":"text","text":"Hel"}]},"parent_tool_use_id":"toolu_SA_ITEMID","session_id":"S1"}"#,
        #"{"type":"assistant","message":{"id":"mS1","role":"assistant","content":[{"type":"text","text":"lo"}]},"parent_tool_use_id":"toolu_SA_ITEMID","session_id":"S1"}"#,
        #"{"type":"assistant","message":{"id":"mS1","role":"assistant","content":[{"type":"thinking","thinking":"pondering"}]},"parent_tool_use_id":"toolu_SA_ITEMID","session_id":"S1"}"#,
        #"{"type":"assistant","message":{"id":"mS2","role":"assistant","content":[{"type":"text","text":"Bye"}]},"parent_tool_use_id":"toolu_SA_ITEMID","session_id":"S1"}"#,
    ]

    private struct Activity: Equatable {
        let kind: SubAgentActivityKind
        let itemId: String?
        let text: String
    }

    @Test
    func subAgentTextAndThinkingFragmentsCarryStableItemIdPerMessageAndType() async throws {
        let mock = ItemIdMockLineTransport()
        let client = ClaudeChatClient(transportFactory: { _, _, _, _ in mock })
        await client.start()

        var iterator = client.events.makeAsyncIterator()
        for line in Self.lines { mock.receive(line) }
        await mock.close()

        var activities: [Activity] = []
        for _ in 0..<100 {
            guard let event = await iterator.next() else { break }
            // 収集対象は text/thinking 由来の活動のみ（tool_use の prompt 入力から出る
            // .prompt 活動は本契約の対象外なので除外する。ハーネス修理 2026-07-11・PM 承認済み）。
            if case .subAgentActivity(let toolUseId, let kind, let itemId, let text) = event,
               toolUseId == Self.subToolUseId,
               kind == .message || kind == .reasoning {
                activities.append(Activity(kind: kind, itemId: itemId, text: text))
            }
            if activities.count == 4 { break }
        }

        try #require(activities.count == 4)

        // 断片テキストはそのまま運ばれる（結合はモデル層の責務）。
        #expect(activities[0] == Activity(kind: .message, itemId: activities[0].itemId, text: "Hel"))
        #expect(activities[1] == Activity(kind: .message, itemId: activities[1].itemId, text: "lo"))
        #expect(activities[2].kind == .reasoning)
        #expect(activities[2].text == "pondering")
        #expect(activities[3] == Activity(kind: .message, itemId: activities[3].itemId, text: "Bye"))

        // 同一 message×同一種別 → 同一の非 nil itemId。
        let helId = try #require(activities[0].itemId)
        #expect(activities[1].itemId == helId)

        // 種別が違えば別 itemId、message が違えば別 itemId。
        let thinkingId = try #require(activities[2].itemId)
        #expect(thinkingId != helId)
        let byeId = try #require(activities[3].itemId)
        #expect(byeId != helId)
        #expect(byeId != thinkingId)
    }
}
