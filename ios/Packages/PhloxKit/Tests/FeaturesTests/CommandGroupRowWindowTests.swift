// iOS ツール実行カードのヘッダ/行分離と、展開時の行数上限。
//
// 背景: 表示窓がブロック単位になり、1つの commandGroup が数百〜数千件を抱えうる。
// 折りたたみ状態で全 item を走査せず、展開時にも行数上限を設ける（macOS 側と同じ契約）。
// iOS 既存の規則「空出力フィルタは唯一の行には適用しない」（ADR 0026）は維持する。
//
// 用語: **表示対象行** = items.count == 1 なら全行、そうでなければ「実行中 or 出力が空白のみでない」行だけ。

import Foundation
import Testing
import PhloxCore
import DesignSystemIOS
@testable import Features

private func cmd(_ id: String, output: String = "output") -> ChatMessage {
    .command(id: id, command: "cmd \(id)", output: output)
}

private func rowWindowCommand(_ id: String, output: String = "output") -> ChatMessage {
    .command(id: id, command: "command \(id)", output: output)
}

private func cmds(_ count: Int, output: String = "output") -> [ChatMessage] {
    (0..<count).map { cmd("c\($0)", output: output) }
}

@Suite("iOS ツール実行カードのヘッダ/行分離・展開時の行数上限・コピー")
struct CommandGroupRowWindowTests {
    // === 上限定数 ===

    @Test func 行の窓の既定値と拡張幅() {
        #expect(SessionDetailCommandGroupRowWindow.defaultLimit == 50)
        #expect(SessionDetailCommandGroupRowWindow.expandStep == 50)
    }

    // === ヘッダ（折りたたみ時に使う値。行データを作らない） ===

    @Test func コマンドが無いグループは件数付きフォールバック見出しになる() {
        let single = SessionDetailCommandGroupHeader(
            items: [.command(id: "c0", command: nil, output: "output")],
            lastTranscriptID: nil,
            isTurnRunning: false
        )
        #expect(single.title == "ツール実行 ×1")

        let hugeItems = (0..<5000).map {
            ChatMessage.command(id: "c\($0)", command: nil, output: "output")
        }
        let huge = SessionDetailCommandGroupHeader(items: hugeItems, lastTranscriptID: nil, isTurnRunning: false)
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

    // === コピー ===

    @Test func グループコピーはコピー可能な内容だけを順序どおり空行区切りで連結する() {
        let items = [
            rowWindowCommand("c1", output: "first"),
            ChatMessage.agent(id: "a1", text: " \n\t "),
            ChatMessage.error(id: "e1", message: "failed"),
        ]

        #expect(
            ChatMessageCopyText.commandGroupCopyText(items)
                == "$ command c1\nfirst\n\nfailed"
        )
    }

    @Test func 単独グループのコピーは単一メッセージのコピー規則を維持する() {
        let item = rowWindowCommand("c1", output: "output")

        #expect(
            ChatMessageCopyText.commandGroupCopyText([item])
                == ChatMessageCopyText.copyText(for: item)
        )
    }

    @Test func コピー可能な内容がないグループはボタンを表示しない() {
        let items = [
            ChatMessage.command(id: "c1", command: nil, output: " \n\t "),
            ChatMessage.agent(id: "a1", text: " "),
        ]

        #expect(!ChatMessageCopyText.commandGroupHasCopyableText(items))
        #expect(ChatMessageCopyText.commandGroupCopyText(items) == nil)
    }

    @Test func 遅延コピー文字列は要求されるまで生成しない() {
        let items = [rowWindowCommand("c1", output: "output")]
        var generationCount = 0
        let deferredText = ChatMessageDeferredCopyText {
            generationCount += 1
            return ChatMessageCopyText.commandGroupCopyText(items)
        }

        #expect(generationCount == 0)
        #expect(deferredText.value() == "$ command c1\noutput")
        #expect(generationCount == 1)
    }

    @Test func グループコピー可否は全メッセージ種別でコピー文字列の有無と一致する() {
        let patterns = ["\u{200B}", "", " \n\t ", "通常テキスト"]

        for text in patterns {
            let question = UserQuestionItem(
                question: text,
                header: "header",
                options: [],
                multiSelect: false
            )
            let messages: [ChatMessage] = [
                .user(id: "user-\(text)", text: text),
                .agent(id: "agent-\(text)", text: text),
                .reasoning(id: "reasoning-\(text)", text: text),
                .subAgent(id: "sub-agent-\(text)", text: text),
                .command(id: "command-\(text)", command: nil, output: text),
                .error(id: "error-\(text)", message: text),
                .fileChange(id: "file-change-\(text)", changes: [
                    ChatFileChange(path: text, diff: "", kind: nil),
                ]),
                .userQuestion(
                    id: "question-\(text)",
                    requestId: "request-\(text)",
                    questions: [question],
                    answers: nil,
                    state: .pending
                ),
            ]

            for message in messages {
                #expect(
                    ChatMessageCopyText.commandGroupHasCopyableText([message])
                        == (ChatMessageCopyText.commandGroupCopyText([message]) != nil),
                    "コピー可否と文字列が不一致: \(message)"
                )
            }
        }
    }

    @Test func フィルタ後の表示対象行に対して末尾から上限を適用する() {
        let items = [
            rowWindowCommand("c1", output: "first"),
            rowWindowCommand("c2", output: ""),
            rowWindowCommand("c3", output: "third"),
            rowWindowCommand("c4", output: "fourth"),
        ]

        let slice = SessionDetailCommandGroupRowWindow.slice(
            items: items,
            lastTranscriptID: nil,
            isTurnRunning: false,
            limit: 2
        )

        #expect(slice.rows.map(\.id) == ["c3", "c4"])
        #expect(slice.hiddenRowCount == 1)
    }

    @Test func ヘッダは空のグループで非描画かつ非実行中を返す() {
        let header = SessionDetailCommandGroupHeader(items: [], lastTranscriptID: nil, isTurnRunning: false)

        #expect(!header.shouldRender)
        #expect(!header.isRunning)
    }

    // ADR 0038: 「閉状態で行データもコピー文字列も作らない」は SwiftUI の body 評価を単体テストから
    // 観測できないため、ソース検査で固定する（test-policy の例外。eager に書き戻すと落ちる）。

    @Test func グループコピー可否は最初のコピー可能な要素で短絡する() throws {
        let source = try SessionViewUXSource.text(
            "Sources/Features/SessionDetail/ChatMessageCopyText.swift"
        )
        let function = try #require(
            SourceFunction.body(named: "commandGroupHasCopyableText", in: source)
        )

        #expect(function.contains(
            "messages.contains { commandGroupCopyablePart(for: $0) != nil }"
        ))
    }

    @Test func ツール実行カードは展開時にだけ行データを構築しコピー文字列を遅延提供する() throws {
        let rowSource = try SessionViewUXSource.text(
            "Sources/Features/SessionDetail/SessionDetailToolCallGroupRow.swift"
        )
        let body = try #require(SourceFunction.body(named: "body", in: rowSource))
        let expandedBlock = try #require(SourceFunction.block(named: "if isExpanded", in: body))

        #expect(
            expandedBlock.contains("SessionDetailCommandGroupRowWindow.slice("),
            "slice の構築が if isExpanded の外に出ている（閉状態でも行データを作る）"
        )

        let viewSource = try SessionViewUXSource.text("Sources/Features/SessionDetail/SessionDetailView.swift")
        let chatBlock = try #require(SourceFunction.body(named: "chatBlock", in: viewSource))
        #expect(chatBlock.contains(
            "copyTextProvider: { ChatMessageCopyText.commandGroupCopyText(items) }"
        ))
    }
}

private enum SourceFunction {
    static func body(named name: String, in source: String) -> String? {
        guard let declarationRange = source.range(of: "func \(name)")
            ?? source.range(of: "var \(name):")
        else {
            return nil
        }
        return bracedBody(after: declarationRange.upperBound, in: source)
    }

    static func block(named name: String, in source: String) -> String? {
        guard let declarationRange = source.range(of: "\(name) {") else { return nil }
        return bracedBody(after: declarationRange.lowerBound, in: source)
    }

    private static func bracedBody(after start: String.Index, in source: String) -> String? {
        guard let bodyStart = source[start...].firstIndex(of: "{") else { return nil }

        var depth = 1
        var index = source.index(after: bodyStart)
        while index < source.endIndex {
            switch source[index] {
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return String(source[bodyStart...index]) }
            default: break
            }
            index = source.index(after: index)
        }
        return nil
    }
}
