import Foundation
import Testing
import PhloxCore
@testable import Features

private func rowWindowCommand(_ id: String, output: String = "output") -> ChatMessage {
    .command(id: id, command: "command \(id)", output: output)
}

@Suite("SessionDetailCommandGroupRowWindow white-box")
struct IOSCommandGroupRowWindowWhiteboxTests {
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

    @Test func 遅延コピー文字列は要求されるまで生成しない() {
        let items = [rowWindowCommand("c1", output: "output")]
        var generationCount = 0
        let deferredText = ChatMessageCopyButton.DeferredText {
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
