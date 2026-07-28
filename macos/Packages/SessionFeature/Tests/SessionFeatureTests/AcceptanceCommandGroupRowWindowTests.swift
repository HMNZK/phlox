// 契約の正本: tasks/task-2.md（tool-call-collapse-threshold run）— ツール実行カードの
// ヘッダ/行分離と、展開時の行数上限。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 【背景】task-1 で表示窓がブロック単位になり、1つの commandGroup が数百〜数千件を抱えうるように
// なった。旧 CommandGroupPresentation は**折りたたみ状態でも**全 item を走査して行データを作り、
// 展開すれば全件を非 Lazy VStack へ流していた。これは ADR 0030 が対処した CPU 暴走・ハングの
// 再発経路になる。よってヘッダと行データを分離し、展開時にも行数上限を設ける。
// あわせて task-1 が入れた回帰（単独・空出力・非実行中のツール実行がカードごと消える）を、
// iOS の既存規則「空出力フィルタは唯一の行には適用しない」の移植で塞ぐ。
//
// 凍結 API:
//   struct CommandGroupHeader: Equatable {
//       let title: String; let timestamp: Date; let isRunning: Bool; let shouldRender: Bool
//       init(items: [ChatItem], lastTranscriptID: String?, isTurnRunning: Bool)
//   }
//   struct CommandGroupRowsSlice: Equatable { let rows: [CommandGroupRow]; let hiddenRowCount: Int }
//   enum CommandGroupRowWindow {
//       static let defaultLimit: Int
//       static let expandStep: Int
//       static func slice(items: [ChatItem], lastTranscriptID: String?, isTurnRunning: Bool, limit: Int) -> CommandGroupRowsSlice
//   }
//
// 用語: **表示対象行** = items.count == 1 なら全行、そうでなければ「実行中 or 出力が空白のみでない」行だけ。

import Foundation
import Testing
@testable import SessionFeature

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

private func cmd(_ id: String, output: String = "output", offset: TimeInterval = 0) -> ChatItem {
    .commandExecution(id: id, command: "cmd \(id)", output: output, timestamp: t0.addingTimeInterval(offset))
}

private func cmds(_ count: Int, output: String = "output") -> [ChatItem] {
    (0..<count).map { cmd("c\($0)", output: output, offset: TimeInterval($0)) }
}

@Suite("Acceptance: ツール実行カードのヘッダ/行分離と展開時の行数上限")
struct AcceptanceCommandGroupRowWindowTests {
    // === 上限定数 ===

    @Test func 行の窓の既定値と拡張幅() {
        #expect(CommandGroupRowWindow.defaultLimit == 50)
        #expect(CommandGroupRowWindow.expandStep == 50)
    }

    // === ヘッダ（折りたたみ時に使う値。行データを作らない） ===

    @Test func 見出しは件数付きでitem件数に依らず正しい() {
        let single = CommandGroupHeader(items: cmds(1), lastTranscriptID: nil, isTurnRunning: false)
        #expect(single.title == "ツール実行 ×1")

        let huge = CommandGroupHeader(items: cmds(5000), lastTranscriptID: nil, isTurnRunning: false)
        #expect(huge.title == "ツール実行 ×5000")
    }

    @Test func ヘッダの時刻は最後のコマンドの時刻() {
        let items = cmds(3)
        let header = CommandGroupHeader(items: items, lastTranscriptID: nil, isTurnRunning: false)
        #expect(header.timestamp == t0.addingTimeInterval(2))
    }

    @Test func ヘッダの実行中判定はターン実行中かつ末尾itemが最新のときだけ真() {
        let items = cmds(3)

        let running = CommandGroupHeader(items: items, lastTranscriptID: "c2", isTurnRunning: true)
        #expect(running.isRunning)

        let notLatest = CommandGroupHeader(items: items, lastTranscriptID: "other", isTurnRunning: true)
        #expect(!notLatest.isRunning)

        let turnIdle = CommandGroupHeader(items: items, lastTranscriptID: "c2", isTurnRunning: false)
        #expect(!turnIdle.isRunning)
    }

    // === 描画要否（SC10: 単独行の空出力規則） ===

    @Test func 単独で出力が空でも非実行中でもカードを描画する() {
        let items = [cmd("c0", output: "")]
        let header = CommandGroupHeader(items: items, lastTranscriptID: nil, isTurnRunning: false)
        #expect(header.shouldRender)  // 変更前は .single で常に見えていた。消してはならない
    }

    @Test func 単独で出力が空でも展開すればコマンド文字列が読める() {
        let items = [cmd("c0", output: "")]
        let slice = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: CommandGroupRowWindow.defaultLimit
        )
        #expect(slice.rows.count == 1)
        #expect(slice.rows[0].command == "cmd c0")
        #expect(slice.hiddenRowCount == 0)
    }

    @Test func 複数件で全て空出力かつ非実行中なら描画しない() {
        let items = cmds(3, output: "")
        let header = CommandGroupHeader(items: items, lastTranscriptID: nil, isTurnRunning: false)
        #expect(!header.shouldRender)  // 既存契約の維持（ノイズ抑制）
    }

    @Test func 複数件でも1件でも出力があれば描画する() {
        let items = [cmd("c0", output: ""), cmd("c1", output: "done"), cmd("c2", output: "")]
        let header = CommandGroupHeader(items: items, lastTranscriptID: nil, isTurnRunning: false)
        #expect(header.shouldRender)
    }

    @Test func 実行中なら全て空出力でも描画する() {
        let items = cmds(3, output: "")
        let header = CommandGroupHeader(items: items, lastTranscriptID: "c2", isTurnRunning: true)
        #expect(header.shouldRender)
    }

    // === 展開時の行数上限（SC11） ===

    @Test func 展開直後の行数は上限までで残りは隠れ件数になる() {
        let items = cmds(5000)
        let slice = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: CommandGroupRowWindow.defaultLimit
        )

        #expect(slice.rows.count == 50)
        #expect(slice.hiddenRowCount == 4950)
        #expect(slice.rows.first?.id == "c4950")  // 末尾側から取る（最新が見える）
        #expect(slice.rows.last?.id == "c4999")
    }

    @Test func 上限を拡張幅ぶん増やすと行が増える() {
        let items = cmds(5000)
        let expanded = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: CommandGroupRowWindow.defaultLimit + CommandGroupRowWindow.expandStep
        )

        #expect(expanded.rows.count == 100)
        #expect(expanded.hiddenRowCount == 4900)
        #expect(expanded.rows.last?.id == "c4999")
    }

    @Test func 行数が上限以下なら全件出て隠れ件数は0() {
        let items = cmds(10)
        let slice = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: CommandGroupRowWindow.defaultLimit
        )

        #expect(slice.rows.count == 10)
        #expect(slice.hiddenRowCount == 0)
    }

    @Test func 上限0以下なら行は空で全件が隠れ件数になる() {
        let items = cmds(10)
        for limit in [0, -5] {
            let slice = CommandGroupRowWindow.slice(
                items: items,
                lastTranscriptID: nil,
                isTurnRunning: false,
                limit: limit
            )
            #expect(slice.rows.isEmpty, "limit=\(limit)")
            #expect(slice.hiddenRowCount == 10, "limit=\(limit)")
        }
    }

    // === 行の中身（既存契約の維持） ===

    @Test func 複数件では空出力の完了済み行を除外し隠れ件数にも数えない() {
        let items = [cmd("c0", output: "a"), cmd("c1", output: ""), cmd("c2", output: "b")]
        let slice = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: CommandGroupRowWindow.defaultLimit
        )

        #expect(slice.rows.map(\.id) == ["c0", "c2"])
        #expect(slice.hiddenRowCount == 0)  // 隠れ件数は「表示対象行のうち未表示分」であり除外行を含まない
    }

    @Test func 実行中の行は出力が空でも残る() {
        let items = [cmd("c0", output: "a"), cmd("c1", output: "")]
        let slice = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true,
            limit: CommandGroupRowWindow.defaultLimit
        )

        #expect(slice.rows.map(\.id) == ["c0", "c1"])
        #expect(slice.rows.last?.isRunning == true)
        #expect(slice.rows.first?.isRunning == false)
    }
}
