// 契約の正本: tasks/task-3.md（tool-call-collapse-threshold run）— iOS セッション詳細の
// 表示窓を「ブロック単位」で数える。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 【契約変更の記録】旧契約では窓は「生の ChatMessage 件数」を数えており、折りたたまれて画面上は
// 1行にしかならない連続ツール実行が、1件につき1枠を消費していた。その結果ツールコールが増えるだけで
// 直前のメッセージが隠れ域へ押し出された（ユーザー報告の症状）。
// 本契約では窓は **トップレベルに描画されるブロック数** を数える。連続ツール実行のまとまりは
// 中に何件入っていても1枠。macOS 側（task-1）と同じ契約。
// （decision-log.md / docs/phase0.md SC2・SC3 参照）
//
// 凍結 API:
//   public struct SessionDetailTranscriptBlockSlice: Equatable, Sendable {
//       public let blocks: [SessionDetailVisibleBlock]
//       public let hiddenBlockCount: Int
//   }
//   public enum SessionDetailToolCallGrouping {
//       public static func blockCount(of messages: [ChatMessage]) -> Int
//       public static func visibleSlice(from messages: [ChatMessage], blockLimit: Int) -> SessionDetailTranscriptBlockSlice
//   }
//
// 契約:
//   - visibleSlice は末尾 min(blockCount, blockLimit) ブロックを順序どおり返す
//   - hiddenBlockCount == max(0, blockCount - blockLimit)（**ブロック単位**。message 単位ではない）
//   - 部分ブロックは生じない（窓境界は必ずブロック境界。旧契約のグループ途中切りは廃止）
//   - 可視ブロックの id は全 transcript 上のブロック id（グループなら先頭 message.id）と一致する
//   - blockLimit <= 0 なら blocks は空・hiddenBlockCount == blockCount
//   - SessionDetailTranscriptSlice の visibleMessages と visibleBlocks は常に同じ範囲を指す
//   - TranscriptWindow（iOS 版）の API と既定値（defaultLimit 50 / expandStep 50）は変更しない

import Foundation
import Testing
import PhloxCore
@testable import Features

private func cmd(_ id: String) -> ChatMessage {
    .command(id: id, command: "cmd \(id)", output: "output \(id)")
}

private func agent(_ id: String) -> ChatMessage {
    .agent(id: id, text: "text \(id)")
}

private func cmds(_ prefix: String, _ count: Int) -> [ChatMessage] {
    (0..<count).map { cmd("\(prefix)\($0)") }
}

private func agents(_ prefix: String, _ count: Int) -> [ChatMessage] {
    (0..<count).map { agent("\(prefix)\($0)") }
}

private func flatten(_ slice: SessionDetailTranscriptBlockSlice) -> [ChatMessage] {
    slice.blocks.flatMap { visible -> [ChatMessage] in
        switch visible.content {
        case .single(let message): [message]
        case .commandGroup(_, let items): items
        }
    }
}

@Suite("Acceptance: iOS 表示窓をブロック単位で数える")
struct AcceptanceIOSBlockWindowTests {
    // === 本命: ツールコール件数が可視メッセージを左右しない（SC2） ===

    @Test func 直前のメッセージ10件はツール実行が1000件並んでも全て可視に残る() {
        let messages = agents("m", 10)
        let all = messages + cmds("c", 1000)

        let slice = SessionDetailToolCallGrouping.visibleSlice(from: all, blockLimit: 50)
        let visibleIDs = Set(slice.blocks.map(\.id))

        for message in messages {
            #expect(visibleIDs.contains(message.id), "メッセージ \(message.id) が隠れ域へ押し出された")
        }
        #expect(slice.blocks.count == 11)   // 10 single + 1 commandGroup
        #expect(slice.hiddenBlockCount == 0)
    }

    @Test func ツール実行が何件でも可視ブロックの構成は変わらない() {
        let messages = agents("m", 10)
        let few = SessionDetailToolCallGrouping.visibleSlice(from: messages + cmds("c", 2), blockLimit: 50)
        let many = SessionDetailToolCallGrouping.visibleSlice(from: messages + cmds("c", 5000), blockLimit: 50)

        #expect(few.blocks.map(\.id) == many.blocks.map(\.id))
        #expect(few.hiddenBlockCount == many.hiddenBlockCount)
    }

    // === レイアウトコストの有界性（SC3）: 列挙した代表入力表で判定する ===

    @Test func 可視ブロック数は常にblockLimit以下() {
        let limits = [16, 50]
        let leadingCounts = [0, 1, 25, 60]
        let commandRunLengths = [0, 1, 2, 49, 50, 999]
        let trailingCounts = [0, 1, 25, 60]

        for limit in limits {
            for leading in leadingCounts {
                for run in commandRunLengths {
                    for trailing in trailingCounts {
                        let messages = agents("l", leading) + cmds("c", run) + agents("t", trailing)
                        let slice = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: limit)
                        let total = SessionDetailToolCallGrouping.blockCount(of: messages)

                        #expect(
                            slice.blocks.count <= limit,
                            "limit=\(limit) leading=\(leading) run=\(run) trailing=\(trailing)"
                        )
                        #expect(slice.blocks.count == min(total, limit))
                        #expect(slice.hiddenBlockCount == max(0, total - limit))
                    }
                }
            }
        }
    }

    @Test func 交互に並ぶ入力でもブロック数と可視数が一致する() {
        var messages: [ChatMessage] = []
        for index in 0..<1000 {
            messages.append(agent("a\(index)"))
            messages.append(cmd("c\(index)"))
        }

        #expect(SessionDetailToolCallGrouping.blockCount(of: messages) == 2000)
        let slice = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 50)
        #expect(slice.blocks.count == 50)
        #expect(slice.hiddenBlockCount == 1950)
        #expect(slice.blocks.last?.id == "c999")
    }

    // === 窓の境界とスライスの性質 ===

    @Test func 窓は末尾のブロックを順序どおり返す() {
        let messages = agents("m", 5) + cmds("c", 3) + agents("n", 4)
        #expect(SessionDetailToolCallGrouping.blockCount(of: messages) == 10)

        let slice = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 3)
        #expect(slice.blocks.map(\.id) == ["n1", "n2", "n3"])
        #expect(slice.hiddenBlockCount == 7)
    }

    @Test func 窓境界がグループにかかっても部分ブロックにならない() {
        let messages = agents("m", 3) + cmds("c", 100)
        let slice = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 1)

        #expect(slice.blocks.count == 1)
        #expect(slice.hiddenBlockCount == 3)
        guard case .commandGroup(let id, let grouped) = slice.blocks[0].content else {
            Issue.record("expected commandGroup, got \(slice.blocks[0].content)")
            return
        }
        #expect(id == "c0")
        #expect(grouped.count == 100)   // グループは途中で切られず全件を保持する
        #expect(slice.blocks[0].id == "c0")
    }

    @Test func 空入力とblockLimit0の扱い() {
        let empty = SessionDetailToolCallGrouping.visibleSlice(from: [], blockLimit: 50)
        #expect(empty.blocks.isEmpty)
        #expect(empty.hiddenBlockCount == 0)

        let messages = agents("m", 3)
        for limit in [0, -5] {
            let slice = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: limit)
            #expect(slice.blocks.isEmpty, "limit=\(limit)")
            #expect(slice.hiddenBlockCount == 3, "limit=\(limit)")
        }
    }

    @Test func 可視部分の平坦化は元のmessage列の末尾と一致する() {
        let messages = agents("m", 5) + cmds("c", 3) + agents("n", 4)
        let slice = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 5)
        #expect(flatten(slice) == Array(messages.suffix(7)))
    }

    // === identity の安定 ===

    @Test func 窓を広げても可視ブロックのidは変わらない() {
        let messages = agents("m", 30) + cmds("c", 40) + agents("n", 30)
        let before = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 50)
        let after = SessionDetailToolCallGrouping.visibleSlice(from: messages, blockLimit: 100)

        let beforeIDs = before.blocks.map(\.id)
        let afterTail = Array(after.blocks.map(\.id).suffix(beforeIDs.count))
        #expect(beforeIDs == afterTail)
    }

    @Test func ストリーミングでグループが伸びても可視ブロックのidは変わらない() {
        let base = agents("m", 3) + cmds("c", 10)
        let grown = agents("m", 3) + cmds("c", 11)

        let before = SessionDetailToolCallGrouping.visibleSlice(from: base, blockLimit: 50)
        let after = SessionDetailToolCallGrouping.visibleSlice(from: grown, blockLimit: 50)
        #expect(before.blocks.map(\.id) == after.blocks.map(\.id))
    }

    // === View 側スライスの整合（可視ブロックと可視メッセージがずれない） ===

    @Test func 可視メッセージと可視ブロックは常に同じ範囲を指す() {
        let cases: [[ChatMessage]] = [
            agents("m", 60) + cmds("c", 500),                       // 隠れ域あり・末尾がグループ
            agents("m", 60) + cmds("c", 500) + agents("n", 5),      // 隠れ域あり・末尾が single
            agents("m", 3) + cmds("c", 1000),                       // 隠れ域なし・巨大グループ
            cmds("c", 1000),                                        // 全部グループ
            [],                                                     // 空
        ]

        for messages in cases {
            let slice = SessionDetailTranscriptSlice(messages: messages, window: TranscriptWindow())
            let flattened = slice.visibleBlocks.flatMap { visible -> [ChatMessage] in
                switch visible.content {
                case .single(let message): [message]
                case .commandGroup(_, let items): items
                }
            }
            #expect(Array(slice.visibleMessages) == flattened, "件数=\(messages.count)")
            #expect(slice.visibleBlocks.count <= TranscriptWindow.defaultLimit, "件数=\(messages.count)")
        }
    }

    @Test func 隠れているブロックがあるときだけ展開アンカーが立つ() {
        let hidden = SessionDetailTranscriptSlice(
            messages: agents("m", 60) + cmds("c", 500),
            window: TranscriptWindow()
        )
        #expect(hidden.hiddenCount > 0)
        #expect(hidden.expansionAnchorID == hidden.visibleBlocks.first?.id)

        let allVisible = SessionDetailTranscriptSlice(
            messages: agents("m", 3) + cmds("c", 1000),
            window: TranscriptWindow()
        )
        #expect(allVisible.hiddenCount == 0)
        #expect(allVisible.expansionAnchorID == nil)
    }

    @Test func 隠れ件数はブロック単位で数える() {
        // 60 メッセージ + 500 コマンド = 61 ブロック。窓 50 なので 11 ブロックが隠れる。
        let messages = agents("m", 60) + cmds("c", 500)
        let slice = SessionDetailTranscriptSlice(messages: messages, window: TranscriptWindow())
        #expect(slice.hiddenCount == 11)   // message 単位なら 510 になる
    }
}
