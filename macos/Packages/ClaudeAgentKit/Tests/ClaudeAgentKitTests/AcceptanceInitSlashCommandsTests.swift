// task-2 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-2.md
// 目的: Claude Code stream-json の system/init が運ぶ slash_commands を
//       NormalizedChatEvent.availableCommandsUpdated へ正規化する。
//
// 実測形式（claude CLI 2.1.220。Phlox と同じ引数で起動して捕捉した init イベント）:
//   {"type":"system","subtype":"init","session_id":"...","slash_commands":["compact","clear",...],
//    "tools":[...],"model":"...","permissionMode":"...", ...}
//   - slash_commands は先頭 "/" を含まない素の名前の配列（104 件observed）
//   - init は「最初のユーザーメッセージ送信後」に届く（無送信では届かない）

import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class InitMockTransport: LineDelimitedTransport, @unchecked Sendable {
    private var continuation: AsyncStream<Data>.Continuation?
    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func start() throws {}
    func send(_ data: Data) async throws {}
    func interrupt() async {}

    func close() async {
        continuation?.finish()
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }
}

/// init の直後に必ず流す番兵。init から availableCommandsUpdated が出ない場合でも
/// テストがハングせず「次のイベント」で判定できるようにする。
private let sentinelLine =
    #"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":1},"uuid":"sentinel","session_id":"s1"}"#

private let sentinelEvent = NormalizedChatEvent.compactionBoundary(trigger: "manual", preTokens: 1)

@Suite("Acceptance: init の slash_commands 正規化（task-2）")
struct AcceptanceInitSlashCommandsTests {

    @Test("init の slash_commands を availableCommandsUpdated として順序を保って yield する")
    func initSlashCommandsAreNormalized() async throws {
        let mock = InitMockTransport()
        let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        mock.receive(
            #"{"type":"system","subtype":"init","session_id":"s1","slash_commands":["compact","clear","config","agentic-loop"],"model":"claude-opus-5","permissionMode":"default"}"#
        )
        mock.receive(sentinelLine)

        let first = await iterator.next()
        #expect(first == .availableCommandsUpdated(commands: ["compact", "clear", "config", "agentic-loop"]))
        await client.close()
    }

    @Test("slash_commands を持たない init では availableCommandsUpdated を出さない")
    func initWithoutSlashCommandsYieldsNothing() async throws {
        let mock = InitMockTransport()
        let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        mock.receive(#"{"type":"system","subtype":"init","session_id":"s1","model":"claude-opus-5"}"#)
        mock.receive(sentinelLine)

        let first = await iterator.next()
        #expect(first == sentinelEvent, "一覧が無い init では静的フォールバックを維持するため何も yield しないこと")
        await client.close()
    }

    @Test("slash_commands が空配列の init では availableCommandsUpdated を出さない")
    func initWithEmptySlashCommandsYieldsNothing() async throws {
        let mock = InitMockTransport()
        let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        mock.receive(#"{"type":"system","subtype":"init","session_id":"s1","slash_commands":[]}"#)
        mock.receive(sentinelLine)

        let first = await iterator.next()
        #expect(first == sentinelEvent, "空一覧で補完候補を全消しせず、静的フォールバックを維持すること")
        await client.close()
    }

    @Test("slash_commands を運ぶ init でも session_id の取り込みを止めない")
    func initStillCapturesSessionId() async throws {
        let mock = InitMockTransport()
        let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
        await client.start()
        var iterator = client.events.makeAsyncIterator()

        mock.receive(
            #"{"type":"system","subtype":"init","session_id":"session-abc","slash_commands":["compact"]}"#
        )
        mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

        let first = await iterator.next()
        #expect(first == .availableCommandsUpdated(commands: ["compact"]))

        // result で turn が閉じるとき、init で取り込んだ session_id が nativeSessionId として返る。
        let second = await iterator.next()
        #expect(second == .turnCompleted(nativeSessionId: "session-abc"))
        await client.close()
    }
}
