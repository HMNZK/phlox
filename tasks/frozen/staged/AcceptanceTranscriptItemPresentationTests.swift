// 実パス: macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptItemPresentationTests.swift
// task-46（UX-05a）受け入れテスト（PM 著・不変）。TranscriptItemPresentation 未実装のコンパイル RED が正常。
// 期待値は tasks/task-46.md の独立リテラル。分類モデルや CommandGroupHeader の出力から生成しない。
//
// 凍結する公開面:
//   struct TranscriptItemPresentation: Equatable, Sendable
//   enum Classification { answer, detail, status, error }
//   enum SemanticInk { normal, process, error }
//   enum CommandPath { single, group }
//   let isVisible, classification, heading, subtitle, isCollapsible, defaultExpanded, semanticInk, expandedBody
//   static func answer(text:)
//   static func reasoning(text:summary:)
//   static func command(path:itemCount:isRunning:hasNonBlankOutput:)
//   static func fileChange(title:)
//   static func taskList(count:)
//   static func activity(label:)
//   static func error(message:)
//   static func isExpanded(userOverride:defaultExpanded:)
//   static func retainedUserOverride(previous:remainedMounted:)
// コマンド単体／グループは path で区別する。件数 1 だけから経路を推測しない。

import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

private enum FrozenHeading {
    static let reasoning = "思考の詳細"
    static let command1 = "処理の詳細（1件）"
    static let command2 = "処理の詳細（2件）"
    static let command51 = "処理の詳細（51件）"
    static let task0 = "タスク（0件）"
    static let task1 = "タスク（1件）"
    static let task2 = "タスク（2件）"
    static let emptyTasks = "タスクなし"
    static let error = "エラー"
    static let running = "実行中"
    static let outputAvailable = "出力あり"
}

private let frozenTime = Date(timeIntervalSince1970: 1_700_000_000)

private func commandItem(id: String, output: String, command: String? = "echo ok") -> ChatItem {
    .commandExecution(id: id, command: command, output: output, timestamp: frozenTime)
}

private struct CommandTableRow: Sendable {
    let path: TranscriptItemPresentation.CommandPath
    let outputs: [String]
    let heading: String
    let latestRunning: (visible: Bool, subtitle: String?, rowIDs: [String])
    let latestCompleted: (visible: Bool, subtitle: String?, rowIDs: [String])
    let pastRunning: (visible: Bool, subtitle: String?, rowIDs: [String])
    let pastCompleted: (visible: Bool, subtitle: String?, rowIDs: [String])
}

@Suite("task-46: TranscriptItemPresentation 表示分類")
struct AcceptanceTranscriptItemPresentationTests {

    @Test("通常・複数段落の回答は回答分類・折り畳み不可・本文表示")
    func answerStaysReadable() {
        let text = "第一段落。\n\n第二段落。"
        let presentation = TranscriptItemPresentation.answer(text: text)
        #expect(presentation.isVisible)
        #expect(presentation.classification == .answer)
        #expect(presentation.heading == nil)
        #expect(presentation.subtitle == nil)
        #expect(!presentation.isCollapsible)
        #expect(presentation.defaultExpanded)
        #expect(presentation.semanticInk == .normal)
        #expect(presentation.expandedBody == text)
        #expect(
            TranscriptItemPresentation.isExpanded(
                userOverride: false,
                defaultExpanded: presentation.defaultExpanded
            )
        )
    }

    @Test("1行・複数行・60文字超の非空思考は思考の詳細・詳細分類・既定閉")
    func nonEmptyReasoningIsCollapsibleDetail() {
        let overSixty = String(repeating: "あ", count: 61)
        #expect(overSixty.count == 61)
        let cases: [(String, String?)] = [
            ("一行の思考", "一行の思考"),
            ("複数行の\n思考本文", "要約"),
            (overSixty, nil),
        ]
        for (text, summary) in cases {
            let presentation = TranscriptItemPresentation.reasoning(text: text, summary: summary)
            #expect(presentation.isVisible)
            #expect(presentation.classification == .detail)
            #expect(presentation.heading == FrozenHeading.reasoning)
            #expect(presentation.subtitle == summary)
            #expect(presentation.isCollapsible)
            #expect(!presentation.defaultExpanded)
            #expect(presentation.semanticInk == .process)
            #expect(presentation.expandedBody == text)
            #expect(
                !TranscriptItemPresentation.isExpanded(
                    userOverride: nil,
                    defaultExpanded: presentation.defaultExpanded
                )
            )
        }
    }

    @Test("空・空白だけの思考は非表示")
    func blankReasoningIsHidden() {
        for text in ["", " \t\n"] {
            let presentation = TranscriptItemPresentation.reasoning(text: text, summary: "残してはいけない")
            #expect(!presentation.isVisible)
            #expect(presentation.classification == .detail)
            #expect(presentation.heading == FrozenHeading.reasoning)
            #expect(!presentation.defaultExpanded)
        }
    }

    @Test("非空思考・要約 nil は表示・補足なし・展開本文へ原文が届く")
    func reasoningWithoutSummaryKeepsBody() {
        let text = "要約なしの思考本文"
        let presentation = TranscriptItemPresentation.reasoning(text: text, summary: nil)
        #expect(presentation.isVisible)
        #expect(presentation.subtitle == nil)
        #expect(presentation.expandedBody == text)
    }

    @Test("同長別内容・別要約は新しい原文と要約が反映される")
    func sameLengthReplacementUpdatesReasoning() {
        let first = TranscriptItemPresentation.reasoning(text: "abcd", summary: "要約A")
        let second = TranscriptItemPresentation.reasoning(text: "wxyz", summary: "要約B")
        #expect(first.expandedBody == "abcd")
        #expect(second.expandedBody == "wxyz")
        #expect(first.subtitle == "要約A")
        #expect(second.subtitle == "要約B")
        #expect(first.expandedBody != second.expandedBody)
        #expect(first.subtitle != second.subtitle)
    }

    @Test("タスク0・1・2件の見出しと既定閉")
    func taskHeadingsAndDefaultCollapsed() {
        let zero = TranscriptItemPresentation.taskList(count: 0)
        let one = TranscriptItemPresentation.taskList(count: 1)
        let two = TranscriptItemPresentation.taskList(count: 2)
        #expect(zero.heading == FrozenHeading.task0)
        #expect(one.heading == FrozenHeading.task1)
        #expect(two.heading == FrozenHeading.task2)
        for presentation in [zero, one, two] {
            #expect(presentation.isVisible)
            #expect(presentation.classification == .detail)
            #expect(presentation.isCollapsible)
            #expect(!presentation.defaultExpanded)
            #expect(presentation.semanticInk == .process)
        }
        #expect(zero.expandedBody == FrozenHeading.emptyTasks)
        #expect(one.expandedBody == nil)
        #expect(two.expandedBody == nil)
    }

    @Test("空タスクの展開本文はタスクなし")
    func emptyTaskExpandedBody() {
        #expect(TranscriptItemPresentation.taskList(count: 0).expandedBody == FrozenHeading.emptyTasks)
    }

    @Test("override nil・true・false は閉・開・閉")
    func overrideDerivesExpansion() {
        #expect(!TranscriptItemPresentation.isExpanded(userOverride: nil, defaultExpanded: false))
        #expect(TranscriptItemPresentation.isExpanded(userOverride: true, defaultExpanded: false))
        #expect(!TranscriptItemPresentation.isExpanded(userOverride: false, defaultExpanded: false))
        #expect(!TranscriptItemPresentation.isExpanded(userOverride: false, defaultExpanded: true))
    }

    @Test("セルが残る内容更新・実行終了では開閉を保持する")
    func overrideSurvivesInPlaceUpdate() {
        #expect(TranscriptItemPresentation.retainedUserOverride(previous: true, remainedMounted: true) == true)
        #expect(TranscriptItemPresentation.retainedUserOverride(previous: false, remainedMounted: true) == false)
        let kept = TranscriptItemPresentation.retainedUserOverride(previous: true, remainedMounted: true)
        #expect(TranscriptItemPresentation.isExpanded(userOverride: kept, defaultExpanded: false))
        let afterRunEnds = TranscriptItemPresentation.command(
            path: .single,
            itemCount: 1,
            isRunning: false,
            hasNonBlankOutput: true
        )
        #expect(afterRunEnds.isVisible)
        #expect(TranscriptItemPresentation.isExpanded(userOverride: kept, defaultExpanded: afterRunEnds.defaultExpanded))
    }

    @Test("非空・開 → 空白 → 非空の同一 ID は非表示を挟み再表示時は閉")
    func blankGapResetsOverride() {
        let open = TranscriptItemPresentation.retainedUserOverride(previous: true, remainedMounted: true)
        #expect(open == true)
        let blank = TranscriptItemPresentation.reasoning(text: " \n", summary: nil)
        #expect(!blank.isVisible)
        let afterUnmount = TranscriptItemPresentation.retainedUserOverride(
            previous: open,
            remainedMounted: blank.isVisible
        )
        #expect(afterUnmount == nil)
        let restored = TranscriptItemPresentation.reasoning(text: "再表示", summary: nil)
        #expect(restored.isVisible)
        #expect(
            !TranscriptItemPresentation.isExpanded(
                userOverride: afterUnmount,
                defaultExpanded: restored.defaultExpanded
            )
        )
    }

    @Test("処理中は状態分類・折り畳み不可・活動ラベル")
    func activityUsesExistingLabel() {
        let label = "Thinking..."
        let presentation = TranscriptItemPresentation.activity(label: label)
        #expect(presentation.isVisible)
        #expect(presentation.classification == .status)
        #expect(presentation.heading == label)
        #expect(presentation.subtitle == nil)
        #expect(!presentation.isCollapsible)
        #expect(presentation.defaultExpanded)
        #expect(presentation.semanticInk == .process)
    }

    @Test("エラー本文 a/**/b: error はエラー見出し・分類・同一文字列")
    func errorKeepsDiagnosticText() {
        let message = "a/**/b: error"
        let presentation = TranscriptItemPresentation.error(message: message)
        #expect(presentation.isVisible)
        #expect(presentation.classification == .error)
        #expect(presentation.heading == FrozenHeading.error)
        #expect(presentation.semanticInk == .error)
        #expect(!presentation.isCollapsible)
        #expect(presentation.defaultExpanded)
        #expect(presentation.expandedBody == message)
    }

    @Test("差分0・1・500・501行は未操作時に閉。501行は初期500・残り1")
    func fileChangeStaysCollapsedAndCapsAt500() {
        #expect(FileChangeDisplayPolicy.visibleLineLimit == 500)
        for lineCount in [0, 1, 500, 501] {
            #expect(!FileChangeDisplayPolicy.isExpanded(userOverride: nil, lineCount: lineCount))
            #expect(!TranscriptItemPresentation.fileChange(title: "編集済み A.swift").defaultExpanded)
        }
        let total = 501
        #expect(min(total, FileChangeDisplayPolicy.visibleLineLimit) == 500)
        #expect(total - FileChangeDisplayPolicy.visibleLineLimit == 1)
        let presentation = TranscriptItemPresentation.fileChange(title: "編集済み A.swift")
        #expect(presentation.isVisible)
        #expect(presentation.classification == .detail)
        #expect(presentation.heading == "編集済み A.swift")
        #expect(presentation.isCollapsible)
        #expect(presentation.semanticInk == .process)
    }

    @Test("21行出力は初期20・隠れた1・展開時21・コピーは全文")
    func twentyOneLineOutputWindow() {
        let output = (1...21).map { "line \($0)" }.joined(separator: "\n")
        let collapsed = CommandGroupOutputDisplay(output: output, isExpanded: false)
        let expanded = CommandGroupOutputDisplay(output: output, isExpanded: true)
        #expect(CommandGroupOutputDisplay.visibleLineLimit == 20)
        #expect(collapsed.isTruncated)
        #expect(collapsed.hiddenLineCount == 1)
        #expect(collapsed.displayedOutput == (1...20).map { "line \($0)" }.joined(separator: "\n"))
        #expect(!expanded.isTruncated)
        #expect(expanded.displayedOutput == output)
        #expect(collapsed.copyText == output)
        #expect(expanded.copyText == output)
    }
}

@Suite("task-46: コマンド表示の固定期待値")
struct AcceptanceTranscriptItemPresentationCommandTableTests {

    /// 契約「コマンド表示の固定期待値」表。Header / Presentation の出力から組まない。
    private static let rows: [CommandTableRow] = [
        CommandTableRow(
            path: .single,
            outputs: [""],
            heading: FrozenHeading.command1,
            latestRunning: (true, FrozenHeading.running, ["a"]),
            latestCompleted: (false, nil, []),
            pastRunning: (false, nil, []),
            pastCompleted: (false, nil, [])
        ),
        CommandTableRow(
            path: .single,
            outputs: [" \n"],
            heading: FrozenHeading.command1,
            latestRunning: (true, FrozenHeading.running, ["a"]),
            latestCompleted: (false, nil, []),
            pastRunning: (false, nil, []),
            pastCompleted: (false, nil, [])
        ),
        CommandTableRow(
            path: .single,
            outputs: ["ok"],
            heading: FrozenHeading.command1,
            latestRunning: (true, FrozenHeading.running, ["a"]),
            latestCompleted: (true, FrozenHeading.outputAvailable, ["a"]),
            pastRunning: (true, FrozenHeading.outputAvailable, ["a"]),
            pastCompleted: (true, FrozenHeading.outputAvailable, ["a"])
        ),
        CommandTableRow(
            path: .group,
            outputs: [""],
            heading: FrozenHeading.command1,
            latestRunning: (true, FrozenHeading.running, ["a"]),
            latestCompleted: (true, nil, ["a"]),
            pastRunning: (true, nil, ["a"]),
            pastCompleted: (true, nil, ["a"])
        ),
        CommandTableRow(
            path: .group,
            outputs: [" \n"],
            heading: FrozenHeading.command1,
            latestRunning: (true, FrozenHeading.running, ["a"]),
            latestCompleted: (true, nil, ["a"]),
            pastRunning: (true, nil, ["a"]),
            pastCompleted: (true, nil, ["a"])
        ),
        CommandTableRow(
            path: .group,
            outputs: ["ok"],
            heading: FrozenHeading.command1,
            latestRunning: (true, FrozenHeading.running, ["a"]),
            latestCompleted: (true, FrozenHeading.outputAvailable, ["a"]),
            pastRunning: (true, FrozenHeading.outputAvailable, ["a"]),
            pastCompleted: (true, FrozenHeading.outputAvailable, ["a"])
        ),
        CommandTableRow(
            path: .group,
            outputs: ["", ""],
            heading: FrozenHeading.command2,
            latestRunning: (true, FrozenHeading.running, ["b"]),
            latestCompleted: (false, nil, []),
            pastRunning: (false, nil, []),
            pastCompleted: (false, nil, [])
        ),
        CommandTableRow(
            path: .group,
            outputs: [" \n", " \n"],
            heading: FrozenHeading.command2,
            latestRunning: (true, FrozenHeading.running, ["b"]),
            latestCompleted: (false, nil, []),
            pastRunning: (false, nil, []),
            pastCompleted: (false, nil, [])
        ),
        CommandTableRow(
            path: .group,
            outputs: ["ok", "ok"],
            heading: FrozenHeading.command2,
            latestRunning: (true, FrozenHeading.running, ["a", "b"]),
            latestCompleted: (true, FrozenHeading.outputAvailable, ["a", "b"]),
            pastRunning: (true, FrozenHeading.outputAvailable, ["a", "b"]),
            pastCompleted: (true, FrozenHeading.outputAvailable, ["a", "b"])
        ),
        CommandTableRow(
            path: .group,
            outputs: ["ok", ""],
            heading: FrozenHeading.command2,
            latestRunning: (true, FrozenHeading.running, ["a", "b"]),
            latestCompleted: (true, FrozenHeading.outputAvailable, ["a"]),
            pastRunning: (true, FrozenHeading.outputAvailable, ["a"]),
            pastCompleted: (true, FrozenHeading.outputAvailable, ["a"])
        ),
        CommandTableRow(
            path: .group,
            outputs: ["", "ok"],
            heading: FrozenHeading.command2,
            latestRunning: (true, FrozenHeading.running, ["b"]),
            latestCompleted: (true, FrozenHeading.outputAvailable, ["b"]),
            pastRunning: (true, FrozenHeading.outputAvailable, ["b"]),
            pastCompleted: (true, FrozenHeading.outputAvailable, ["b"])
        ),
        CommandTableRow(
            path: .group,
            outputs: ["ok", " \n"],
            heading: FrozenHeading.command2,
            latestRunning: (true, FrozenHeading.running, ["a", "b"]),
            latestCompleted: (true, FrozenHeading.outputAvailable, ["a"]),
            pastRunning: (true, FrozenHeading.outputAvailable, ["a"]),
            pastCompleted: (true, FrozenHeading.outputAvailable, ["a"])
        ),
        CommandTableRow(
            path: .group,
            outputs: [" \n", "ok"],
            heading: FrozenHeading.command2,
            latestRunning: (true, FrozenHeading.running, ["b"]),
            latestCompleted: (true, FrozenHeading.outputAvailable, ["b"]),
            pastRunning: (true, FrozenHeading.outputAvailable, ["b"]),
            pastCompleted: (true, FrozenHeading.outputAvailable, ["b"])
        ),
    ]

    @Test("コマンド表の表示可否・補足・行 ID を Header と Presentation へ別々に照合する")
    func commandTableMatchesHeaderAndPresentation() {
        for row in Self.rows {
            expectRow(row, command: "echo ok")
        }
    }

    @Test("command を nil にしても表示可否・補足・件数・行 ID は同じ")
    func nilCommandKeepsCountsAndRows() {
        for row in Self.rows {
            expectRow(row, command: nil)
        }
    }

    @Test("1件という件数だけから経路を推測しない")
    func pathIsNotInferredFromCount() {
        let singleEmpty = TranscriptItemPresentation.command(
            path: .single,
            itemCount: 1,
            isRunning: false,
            hasNonBlankOutput: false
        )
        let groupEmpty = TranscriptItemPresentation.command(
            path: .group,
            itemCount: 1,
            isRunning: false,
            hasNonBlankOutput: false
        )
        #expect(!singleEmpty.isVisible)
        #expect(groupEmpty.isVisible)
        #expect(singleEmpty.heading == FrozenHeading.command1)
        #expect(groupEmpty.heading == FrozenHeading.command1)
    }

    @Test("a,b が表示される最新実行中の行状態は [false,true]。過去と完了は [false,false]")
    func rowRunningFlags() {
        let items = [
            commandItem(id: "a", output: "ok"),
            commandItem(id: "b", output: "ok"),
        ]
        let latestRunning = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "b",
            isTurnRunning: true,
            limit: CommandGroupRowWindow.defaultLimit
        )
        #expect(latestRunning.rows.map(\.id) == ["a", "b"])
        #expect(latestRunning.rows.map(\.isRunning) == [false, true])

        let pastRunning = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "z",
            isTurnRunning: true,
            limit: CommandGroupRowWindow.defaultLimit
        )
        let completed = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "b",
            isTurnRunning: false,
            limit: CommandGroupRowWindow.defaultLimit
        )
        #expect(pastRunning.rows.map(\.isRunning) == [false, false])
        #expect(completed.rows.map(\.isRunning) == [false, false])
    }

    @Test("51件の見出しは処理の詳細（51件）。初期窓は c02...c51、隠れ1、追加後は c01 を含む51行")
    func fiftyOneItemWindow() {
        let ids = [
            "c01", "c02", "c03", "c04", "c05", "c06", "c07", "c08", "c09", "c10",
            "c11", "c12", "c13", "c14", "c15", "c16", "c17", "c18", "c19", "c20",
            "c21", "c22", "c23", "c24", "c25", "c26", "c27", "c28", "c29", "c30",
            "c31", "c32", "c33", "c34", "c35", "c36", "c37", "c38", "c39", "c40",
            "c41", "c42", "c43", "c44", "c45", "c46", "c47", "c48", "c49", "c50",
            "c51",
        ]
        let expectedInitial = [
            "c02", "c03", "c04", "c05", "c06", "c07", "c08", "c09", "c10", "c11",
            "c12", "c13", "c14", "c15", "c16", "c17", "c18", "c19", "c20", "c21",
            "c22", "c23", "c24", "c25", "c26", "c27", "c28", "c29", "c30", "c31",
            "c32", "c33", "c34", "c35", "c36", "c37", "c38", "c39", "c40", "c41",
            "c42", "c43", "c44", "c45", "c46", "c47", "c48", "c49", "c50", "c51",
        ]
        #expect(ids.count == 51)
        #expect(expectedInitial.count == 50)
        let items = ids.map { commandItem(id: $0, output: "ok") }
        let presentation = TranscriptItemPresentation.command(
            path: .group,
            itemCount: 51,
            isRunning: true,
            hasNonBlankOutput: true
        )
        #expect(presentation.heading == FrozenHeading.command51)
        #expect(presentation.subtitle == FrozenHeading.running)

        let initial = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "c51",
            isTurnRunning: true,
            limit: CommandGroupRowWindow.defaultLimit
        )
        #expect(CommandGroupRowWindow.defaultLimit == 50)
        #expect(initial.rows.map(\.id) == expectedInitial)
        #expect(initial.hiddenRowCount == 1)

        let expanded = CommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: "c51",
            isTurnRunning: true,
            limit: CommandGroupRowWindow.defaultLimit + CommandGroupRowWindow.expandStep
        )
        #expect(expanded.rows.map(\.id) == ids)
        #expect(expanded.hiddenRowCount == 0)

        let completed = TranscriptItemPresentation.command(
            path: .group,
            itemCount: 51,
            isRunning: false,
            hasNonBlankOutput: true
        )
        let pastRunning = CommandGroupHeader(items: items, lastTranscriptID: "z", isTurnRunning: true)
        #expect(completed.subtitle == FrozenHeading.outputAvailable)
        #expect(!pastRunning.isRunning)
        #expect(
            TranscriptItemPresentation.command(
                path: .group,
                itemCount: 51,
                isRunning: pastRunning.isRunning,
                hasNonBlankOutput: true
            ).subtitle == FrozenHeading.outputAvailable
        )
    }

    private func expectRow(_ row: CommandTableRow, command: String?) {
        let ids: [String] = row.outputs.count == 1 ? ["a"] : ["a", "b"]
        let items = zip(ids, row.outputs).map { commandItem(id: $0, output: $1, command: command) }
        let lastID = ids.last ?? "a"
        let states: [(last: String?, running: Bool, expected: (visible: Bool, subtitle: String?, rowIDs: [String]))] = [
            (lastID, true, row.latestRunning),
            (lastID, false, row.latestCompleted),
            ("z", true, row.pastRunning),
            ("z", false, row.pastCompleted),
        ]
        for state in states {
            let header = CommandGroupHeader(
                items: items,
                lastTranscriptID: state.last,
                isTurnRunning: state.running
            )
            let slice = CommandGroupRowWindow.slice(
                items: items,
                lastTranscriptID: state.last,
                isTurnRunning: state.running,
                limit: CommandGroupRowWindow.defaultLimit
            )
            let hasNonBlank = row.outputs.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let presentation = TranscriptItemPresentation.command(
                path: row.path,
                itemCount: row.outputs.count,
                isRunning: header.isRunning,
                hasNonBlankOutput: hasNonBlank
            )
            #expect(presentation.heading == row.heading)
            #expect(header.isRunning == (state.running && lastID == state.last))
            switch row.path {
            case .single:
                #expect(presentation.isVisible == state.expected.visible)
                #expect(presentation.subtitle == state.expected.subtitle)
                #expect(state.expected.rowIDs == (state.expected.visible ? ids : []))
            case .group:
                #expect(header.shouldRender == state.expected.visible)
                #expect(presentation.isVisible == state.expected.visible)
                #expect(presentation.subtitle == state.expected.subtitle)
                if state.expected.visible {
                    #expect(slice.rows.map(\.id) == state.expected.rowIDs)
                } else {
                    #expect(state.expected.rowIDs.isEmpty)
                }
            }
            #expect(presentation.classification == .detail)
            #expect(presentation.isCollapsible)
            #expect(!presentation.defaultExpanded)
            #expect(presentation.semanticInk == .process)
        }
    }
}
