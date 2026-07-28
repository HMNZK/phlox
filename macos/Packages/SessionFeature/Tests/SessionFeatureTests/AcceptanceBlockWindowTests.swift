// 契約の正本: tasks/task-1.md（tool-call-collapse-threshold run）— transcript の表示窓を「ブロック単位」で数える。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 【契約変更の記録】旧契約では窓は「生の ChatItem 件数」を数えており、折りたたまれて画面上は
// 1行にしかならない連続ツール実行が、1件につき1枠を消費していた。その結果ツールコールが増えるだけで
// 直前のメッセージが隠れ域へ押し出された（ユーザー報告の症状）。
// 本契約では窓は **トップレベルに描画されるブロック数** を数える。連続ツール実行のまとまりは
// 中に何件入っていても1枠。これによりツールコール件数と可視メッセージ数が無関係になる。
// （decision-log.md / docs/phase0.md SC2・SC3・SC6 参照）
//
// 凍結 API:
//   struct ChatTranscriptSlice: Equatable {
//       let blocks: [ChatTranscriptVisibleBlock]
//       let hiddenBlockCount: Int
//   }
//   enum ChatTranscriptGrouping {
//       static func blockCount(of items: [ChatItem]) -> Int
//       static func blockIndex(ofItemWithID itemID: String, in items: [ChatItem]) -> Int?
//       static func visibleSlice(from items: [ChatItem], blockLimit: Int) -> ChatTranscriptSlice
//   }
//
// 契約:
//   - visibleSlice は末尾 min(blockCount, blockLimit) ブロックを順序どおり返す
//   - hiddenBlockCount == max(0, blockCount - blockLimit)（**ブロック単位**。item 単位ではない）
//   - 部分ブロックは生じない（窓境界は必ずブロック境界。旧契約のグループ途中切りは廃止）
//   - 可視ブロックの id は全 transcript 上のブロック id（グループなら先頭 item.id）と一致する
//   - blockLimit <= 0 なら blocks は空・hiddenBlockCount == blockCount
//   - TranscriptWindow の API と既定値（single=50 / gridTile=16 / expandStep=50）は変更しない

import Foundation
import Testing
@testable import SessionFeature

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func cmd(_ id: String) -> ChatItem {
    .commandExecution(id: id, command: "cmd \(id)", output: "output \(id)", timestamp: t0)
}

private func agent(_ id: String) -> ChatItem {
    .agentMessage(id: id, text: "text \(id)", timestamp: t0)
}

private func cmds(_ prefix: String, _ count: Int) -> [ChatItem] {
    (0..<count).map { cmd("\(prefix)\($0)") }
}

private func agents(_ prefix: String, _ count: Int) -> [ChatItem] {
    (0..<count).map { agent("\(prefix)\($0)") }
}

private func flatten(_ slice: ChatTranscriptSlice) -> [ChatItem] {
    slice.blocks.flatMap { visible -> [ChatItem] in
        switch visible.content {
        case .single(let item): [item]
        case .commandGroup(_, let items): items
        }
    }
}

@Suite("Acceptance: 表示窓をブロック単位で数える")
struct AcceptanceBlockWindowTests {
    // === 本命: ツールコール件数が可視メッセージを左右しない（SC2） ===

    @Test func 直前のメッセージ10件はツール実行が1000件並んでも全て可視に残る() {
        let messages = agents("m", 10)
        let items = messages + cmds("c", 1000)

        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 50)
        let visibleIDs = Set(slice.blocks.map(\.id))

        for message in messages {
            #expect(visibleIDs.contains(message.id), "メッセージ \(message.id) が隠れ域へ押し出された")
        }
        // 全体は 10 個の single + 1 個の commandGroup = 11 ブロック（窓 50 以下なので何も隠れない）
        #expect(slice.blocks.count == 11)
        #expect(slice.hiddenBlockCount == 0)
    }

    @Test func ツール実行が何件でも可視ブロックの構成は変わらない() {
        let messages = agents("m", 10)
        let few = ChatTranscriptGrouping.visibleSlice(from: messages + cmds("c", 2), blockLimit: 50)
        let many = ChatTranscriptGrouping.visibleSlice(from: messages + cmds("c", 5000), blockLimit: 50)

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
                        let items = agents("l", leading) + cmds("c", run) + agents("t", trailing)
                        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: limit)
                        let total = ChatTranscriptGrouping.blockCount(of: items)

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
        // agent, cmd, agent, cmd ... を 2000 件（= 1000 single + 1000 group = 2000 ブロック）
        var items: [ChatItem] = []
        for index in 0..<1000 {
            items.append(agent("a\(index)"))
            items.append(cmd("c\(index)"))
        }

        #expect(ChatTranscriptGrouping.blockCount(of: items) == 2000)
        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 50)
        #expect(slice.blocks.count == 50)
        #expect(slice.hiddenBlockCount == 1950)
        #expect(slice.blocks.last?.id == "c999")
    }

    // === 窓の境界とスライスの性質 ===

    @Test func 窓は末尾のブロックを順序どおり返す() {
        let items = agents("m", 5) + cmds("c", 3) + agents("n", 4)
        // ブロック: m0..m4 (5) + [c0,c1,c2] (1) + n0..n3 (4) = 10 ブロック
        #expect(ChatTranscriptGrouping.blockCount(of: items) == 10)

        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 3)
        #expect(slice.blocks.map(\.id) == ["n1", "n2", "n3"])
        #expect(slice.hiddenBlockCount == 7)
    }

    @Test func 窓境界がグループにかかっても部分ブロックにならない() {
        let items = agents("m", 3) + cmds("c", 100)
        // ブロック: m0,m1,m2 (3) + [c0...c99] (1) = 4 ブロック
        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 1)

        #expect(slice.blocks.count == 1)
        #expect(slice.hiddenBlockCount == 3)
        guard case .commandGroup(let id, let grouped) = slice.blocks[0].content else {
            Issue.record("expected commandGroup, got \(slice.blocks[0].content)")
            return
        }
        #expect(id == "c0")
        #expect(grouped.count == 100)  // グループは途中で切られず全件を保持する
        #expect(slice.blocks[0].id == "c0")
    }

    @Test func 空入力とblockLimit0の扱い() {
        let empty = ChatTranscriptGrouping.visibleSlice(from: [], blockLimit: 50)
        #expect(empty.blocks.isEmpty)
        #expect(empty.hiddenBlockCount == 0)

        let items = agents("m", 3)
        let zero = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 0)
        #expect(zero.blocks.isEmpty)
        #expect(zero.hiddenBlockCount == 3)

        let negative = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: -5)
        #expect(negative.blocks.isEmpty)
        #expect(negative.hiddenBlockCount == 3)
    }

    @Test func 可視部分の平坦化は元のitem列の末尾と一致する() {
        let items = agents("m", 5) + cmds("c", 3) + agents("n", 4)
        let slice = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 5)
        // 可視は [c0,c1,c2] グループ + n0..n3 = 5 ブロック → item では c0,c1,c2,n0,n1,n2,n3
        #expect(flatten(slice) == Array(items.suffix(7)))
    }

    // === identity の安定（SC5） ===

    @Test func 窓を広げても可視ブロックのidは変わらない() {
        let items = agents("m", 30) + cmds("c", 40) + agents("n", 30)
        let before = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 50)
        let after = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: 100)

        let beforeIDs = before.blocks.map(\.id)
        let afterTail = Array(after.blocks.map(\.id).suffix(beforeIDs.count))
        #expect(beforeIDs == afterTail)
    }

    @Test func ストリーミングでグループが伸びても可視ブロックのidは変わらない() {
        let base = agents("m", 3) + cmds("c", 10)
        let grown = agents("m", 3) + cmds("c", 11)

        let before = ChatTranscriptGrouping.visibleSlice(from: base, blockLimit: 50)
        let after = ChatTranscriptGrouping.visibleSlice(from: grown, blockLimit: 50)
        #expect(before.blocks.map(\.id) == after.blocks.map(\.id))
    }

    // === reveal 用の item→block 翻訳（SC6） ===

    @Test func blockIndexはitemが属するブロックの位置を返す() {
        let items = agents("m", 3) + cmds("c", 10) + agents("n", 2)
        // ブロック: m0(0), m1(1), m2(2), [c0..c9](3), n0(4), n1(5)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "m0", in: items) == 0)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "m2", in: items) == 2)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "c0", in: items) == 3)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "c9", in: items) == 3)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "n1", in: items) == 5)
        #expect(ChatTranscriptGrouping.blockIndex(ofItemWithID: "missing", in: items) == nil)
    }

    @Test func 隠れ域のitemはblockIndexとwindowRevealで可視化できる() {
        let items = agents("m", 60) + cmds("c", 500)
        let blockCount = ChatTranscriptGrouping.blockCount(of: items)  // 60 + 1 = 61
        #expect(blockCount == 61)

        guard let targetBlockIndex = ChatTranscriptGrouping.blockIndex(ofItemWithID: "m0", in: items) else {
            Issue.record("blockIndex が nil を返した")
            return
        }
        #expect(targetBlockIndex == 0)

        var window = TranscriptWindow(context: .single)
        // 既定 50 ブロックでは先頭 11 ブロックが隠れ域
        #expect(window.visibleRange(totalCount: blockCount).startIndex == 11)

        window.reveal(index: targetBlockIndex, totalCount: blockCount)
        let revealed = ChatTranscriptGrouping.visibleSlice(from: items, blockLimit: window.limit)
        #expect(revealed.blocks.contains { $0.id == "m0" })
    }
}
