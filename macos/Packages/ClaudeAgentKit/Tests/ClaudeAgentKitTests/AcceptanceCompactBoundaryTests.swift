// 契約の正本: tasks/task-2.md — compaction（会話履歴圧縮）境界イベントの正規化。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 契約: Claude Code stream-json の system/compact_boundary を
// NormalizedChatEvent.compactionBoundary(trigger:preTokens:) へ正規化する。
//   - compact_metadata.trigger（"auto"|"manual"）と compact_metadata.pre_tokens を透過する
//   - metadata が欠けていても silent drop せず nil で yield する（安全側）
// 実測形式（Claude Code stream-json）:
//   {"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":155000},...}
// 実装時は実 CLI ログでキー名を照合し、差異があれば PM に報告する（アサーションの書き換えは不可）。

import Foundation
import Testing
import StructuredChatKit
@testable import ClaudeAgentKit

private final class CompactMockTransport: LineDelimitedTransport, @unchecked Sendable {
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

@Test func compactBoundaryIsNormalizedWithMetadata() async throws {
    let mock = CompactMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    mock.receive(
        #"{"type":"system","subtype":"compact_boundary","compact_metadata":{"trigger":"manual","pre_tokens":155000},"uuid":"u1","session_id":"s1"}"#
    )
    // 未実装で compact_boundary が drop された場合にテストがハングせず即失敗するよう、
    // 直後に必ず yield される result を流して次イベントを固定する（先頭イベントのみ検証）。
    mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    let first = await iterator.next()
    #expect(first == .compactionBoundary(trigger: "manual", preTokens: 155_000))
    await client.close()
}

@Test func compactBoundaryWithoutMetadataStillYields() async throws {
    let mock = CompactMockTransport()
    let client = ClaudeChatClient(environment: [:], transportFactory: { _, _, _, _ in mock })
    await client.start()
    var iterator = client.events.makeAsyncIterator()

    mock.receive(#"{"type":"system","subtype":"compact_boundary","uuid":"u2","session_id":"s1"}"#)
    mock.receive(#"{"type":"result","subtype":"success","is_error":false}"#)

    let first = await iterator.next()
    #expect(first == .compactionBoundary(trigger: nil, preTokens: nil))
    await client.close()
}
