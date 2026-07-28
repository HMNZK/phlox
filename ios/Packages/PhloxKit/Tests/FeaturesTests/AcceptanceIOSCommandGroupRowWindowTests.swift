// 契約の正本: tasks/task-4.md（tool-call-collapse-threshold run）— iOS ツール実行カードの
// ヘッダ/行分離と、展開時の行数上限。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 【背景】task-3 で表示窓がブロック単位になり、1つの commandGroup が数百〜数千件を抱えうるように
// なった。旧 SessionDetailCommandGroupPresentation は**折りたたみ状態でも**全 item を走査して
// 行データを作り、展開すれば全件を非 Lazy な VStack へ流していた。件数に比例して描画が重くなる。
// よってヘッダと行データを分離し、展開時にも行数上限を設ける。macOS 側（task-2）と同じ契約。
// iOS 既存の規則「空出力フィルタは唯一の行には適用しない」（ADR 0026）は維持する。
//
// 凍結 API:
//   struct SessionDetailCommandGroupHeader: Equatable {
//       let title: String; let isRunning: Bool; let shouldRender: Bool
//       init(items: [ChatMessage], lastTranscriptID: String?, isTurnRunning: Bool)
//   }
//   struct SessionDetailCommandGroupRowsSlice: Equatable {
//       let rows: [SessionDetailCommandGroupRow]; let hiddenRowCount: Int
//   }
//   enum SessionDetailCommandGroupRowWindow {
//       static let defaultLimit: Int
//       static let expandStep: Int
//       static func slice(items: [ChatMessage], lastTranscriptID: String?, isTurnRunning: Bool, limit: Int) -> SessionDetailCommandGroupRowsSlice
//   }
//
// 用語: **表示対象行** = items.count == 1 なら全行、そうでなければ「実行中 or 出力が空白のみでない」行だけ。

import Foundation
import Testing
import PhloxCore
@testable import Features

private func cmd(_ id: String, output: String = "output") -> ChatMessage {
    .command(id: id, command: "cmd \(id)", output: output)
}

private func cmds(_ count: Int, output: String = "output") -> [ChatMessage] {
    (0..<count).map { cmd("c\($0)", output: output) }
}

@Suite("Acceptance: iOS ツール実行カードのヘッダ/行分離と展開時の行数上限")
struct AcceptanceIOSCommandGroupRowWindowTests {
    // === 上限定数 ===

    @Test func 行の窓の既定値と拡張幅() {
        #expect(SessionDetailCommandGroupRowWindow.defaultLimit == 50)
        #expect(SessionDetailCommandGroupRowWindow.expandStep == 50)
    }

    // === ヘッダ（折りたたみ時に使う値。行データを作らない） ===

    @Test func 見出しは件数付きでitem件数に依らず正しい() {
        let single = SessionDetailCommandGroupHeader(items: cmds(1), lastTranscriptID: nil, isTurnRunning: false)
        #expect(single.title == "ツール実行 ×1")

        let huge = SessionDetailCommandGroupHeader(items: cmds(5000), lastTranscriptID: nil, isTurnRunning: false)
        #expect(huge.title == "ツール実行 ×5000")
    }

    @Test func ヘッダの実行中判定はターン実行中かつ末尾itemが最新のときだけ真() {
        let items = cmds(3)

        #expect(SessionDetailCommandGroupHeader(items: items, lastTranscriptID: "c2", isTurnRunning: true).isRunning)
        #expect(!SessionDetailCommandGroupHeader(items: items, lastTranscriptID: "other", isTurnRunning: true).isRunning)
        #expect(!SessionDetailCommandGroupHeader(items: items, lastTranscriptID: "c2", isTurnRunning: false).isRunning)
    }

    // === 描画要否（iOS 既存の「単独行には空出力フィルタを適用しない」規則の維持） ===

    @Test func 単独で出力が空でも非実行中でもカードを描画する() {
        let header = SessionDetailCommandGroupHeader(
            items: [cmd("c0", output: "")],
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(header.shouldRender)
    }

    @Test func 単独で出力が空でも展開すればコマンド文字列が読める() {
        let slice = SessionDetailCommandGroupRowWindow.slice(
            items: [cmd("c0", output: "")],
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: SessionDetailCommandGroupRowWindow.defaultLimit
        )
        #expect(slice.rows.count == 1)
        #expect(slice.rows[0].command == "cmd c0")
        #expect(slice.hiddenRowCount == 0)
    }

    @Test func 複数件で全て空出力かつ非実行中なら描画しない() {
        let header = SessionDetailCommandGroupHeader(
            items: cmds(3, output: ""),
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(!header.shouldRender)
    }

    @Test func 複数件でも1件でも出力があれば描画する() {
        let items = [cmd("c0", output: ""), cmd("c1", output: "done"), cmd("c2", output: "")]
        let header = SessionDetailCommandGroupHeader(items: items, lastTranscriptID: nil, isTurnRunning: false)
        #expect(header.shouldRender)
    }

    @Test func 実行中なら全て空出力でも描画する() {
        let header = SessionDetailCommandGroupHeader(
            items: cmds(3, output: ""),
            lastTranscriptID: "c2",
            isTurnRunning: true
        )
        #expect(header.shouldRender)
    }

    // === 展開時の行数上限 ===

    @Test func 展開直後の行数は上限までで残りは隠れ件数になる() {
        let slice = SessionDetailCommandGroupRowWindow.slice(
            items: cmds(5000),
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: SessionDetailCommandGroupRowWindow.defaultLimit
        )

        #expect(slice.rows.count == 50)
        #expect(slice.hiddenRowCount == 4950)
        #expect(slice.rows.first?.id == "c4950")  // 末尾側から取る（最新が見える）
        #expect(slice.rows.last?.id == "c4999")
    }

    @Test func 上限を拡張幅ぶん増やすと行が増える() {
        let expanded = SessionDetailCommandGroupRowWindow.slice(
            items: cmds(5000),
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: SessionDetailCommandGroupRowWindow.defaultLimit + SessionDetailCommandGroupRowWindow.expandStep
        )

        #expect(expanded.rows.count == 100)
        #expect(expanded.hiddenRowCount == 4900)
        #expect(expanded.rows.last?.id == "c4999")
    }

    @Test func 行数が上限以下なら全件出て隠れ件数は0() {
        let slice = SessionDetailCommandGroupRowWindow.slice(
            items: cmds(10),
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: SessionDetailCommandGroupRowWindow.defaultLimit
        )

        #expect(slice.rows.count == 10)
        #expect(slice.hiddenRowCount == 0)
    }

    @Test func 上限0以下なら行は空で全件が隠れ件数になる() {
        for limit in [0, -5] {
            let slice = SessionDetailCommandGroupRowWindow.slice(
                items: cmds(10),
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
        let slice = SessionDetailCommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: SessionDetailCommandGroupRowWindow.defaultLimit
        )

        #expect(slice.rows.map(\.id) == ["c0", "c2"])
        #expect(slice.hiddenRowCount == 0)  // 隠れ件数は「表示対象行のうち未表示分」であり除外行を含まない
    }

    @Test func 実行中の行は出力が空でも残る() {
        let items = [cmd("c0", output: "a"), cmd("c1", output: "")]
        let slice = SessionDetailCommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "c1",
            isTurnRunning: true,
            limit: SessionDetailCommandGroupRowWindow.defaultLimit
        )

        #expect(slice.rows.map(\.id) == ["c0", "c1"])
        #expect(slice.rows.last?.isRunning == true)
        #expect(slice.rows.first?.isRunning == false)
    }
}
