import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

private let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)  // 2027-01-15 08:00 UTC

private func makeMetadata() -> ChatTranscriptExportMetadata {
    ChatTranscriptExportMetadata(
        sessionTitle: "Lotus",
        agentName: "Claude Code",
        projectName: "Phlox",
        workingDirectory: "/tmp/phlox",
        exportedAt: fixedDate
    )
}

@Test("見出しにセッション情報が入る")
func export_includesMetadataHeader() {
    let markdown = ChatTranscriptExporter.markdown(items: [], metadata: makeMetadata())
    #expect(markdown.hasPrefix("# Lotus\n"))
    #expect(markdown.contains("- エージェント: Claude Code"))
    #expect(markdown.contains("- プロジェクト: Phlox"))
    #expect(markdown.contains("- 作業ディレクトリ: `/tmp/phlox`"))
}

@Test("ユーザーとアシスタントの発言が本文ごと出る")
func export_rendersMessages() {
    let items: [ChatItem] = [
        .userMessage(id: "1", text: "こんにちは", timestamp: fixedDate),
        .agentMessage(id: "2", text: "はい、なんでしょう", timestamp: fixedDate),
    ]
    let markdown = ChatTranscriptExporter.markdown(items: items, metadata: makeMetadata())
    #expect(markdown.contains("## 👤 ユーザー"))
    #expect(markdown.contains("こんにちは"))
    #expect(markdown.contains("## 🤖 アシスタント"))
    #expect(markdown.contains("はい、なんでしょう"))
}

@Test("推論は既定では出ず、指定したときだけ引用で出る")
func export_reasoningIsOptional() {
    let items: [ChatItem] = [.reasoning(id: "1", text: "考え中\n二行目", timestamp: fixedDate)]

    let without = ChatTranscriptExporter.markdown(items: items, metadata: makeMetadata())
    #expect(without.contains("考え中") == false)

    let with = ChatTranscriptExporter.markdown(
        items: items,
        metadata: makeMetadata(),
        options: ChatTranscriptExportOptions(includesReasoning: true)
    )
    #expect(with.contains("## 💭 思考"))
    #expect(with.contains("> 考え中"))
    #expect(with.contains("> 二行目"))
}

@Test("コマンドはコードブロックになり、出力は設定で外せる")
func export_commandExecution() {
    let items: [ChatItem] = [
        .commandExecution(id: "1", command: "ls -la", output: "total 0", timestamp: fixedDate),
    ]

    let with = ChatTranscriptExporter.markdown(items: items, metadata: makeMetadata())
    #expect(with.contains("```sh\nls -la\n```"))
    #expect(with.contains("total 0"))

    let without = ChatTranscriptExporter.markdown(
        items: items,
        metadata: makeMetadata(),
        options: ChatTranscriptExportOptions(includesCommandOutput: false)
    )
    #expect(without.contains("total 0") == false)
}

@Test("ファイル変更・エラー・コスト・タスクが読める形で出る")
func export_rendersStructuredItems() {
    let items: [ChatItem] = [
        .fileChange(id: "1", changes: [FilePatchChange(path: "a.swift", diff: "", kind: "edit")], timestamp: fixedDate),
        .error(id: "2", message: "失敗しました", timestamp: fixedDate),
        .turnCost(id: "3", costUSD: 0.1234, timestamp: fixedDate),
        .taskList(id: "4", tasks: [
            AgentTaskItem(id: "t1", title: "調べる", status: .completed),
            AgentTaskItem(id: "t2", title: "直す", status: .inProgress),
            AgentTaskItem(id: "t3", title: "確かめる", status: .pending),
        ], timestamp: fixedDate),
    ]
    let markdown = ChatTranscriptExporter.markdown(items: items, metadata: makeMetadata())

    #expect(markdown.contains("- `a.swift`（edit）"))
    #expect(markdown.contains("> 失敗しました"))
    #expect(markdown.contains("$ 0.1234"))
    #expect(markdown.contains("- [x] 調べる"))
    #expect(markdown.contains("- [ ] 直す（作業中）"))
    #expect(markdown.contains("- [ ] 確かめる"))
}

@Test("確認カードは選択肢と回答を残す")
func export_rendersUserQuestion() {
    let question = ChatUserQuestion(
        question: "どちらにしますか？",
        header: "方式",
        options: [
            ChatUserQuestionOption(label: "A", description: "こちら"),
            ChatUserQuestionOption(label: "B", description: nil),
        ],
        multiSelect: false
    )
    let items: [ChatItem] = [
        .userQuestion(
            id: "1",
            requestId: "r1",
            questions: [question],
            answers: ["どちらにしますか？": ["A"]],
            state: .answered,
            timestamp: fixedDate
        ),
    ]
    let markdown = ChatTranscriptExporter.markdown(items: items, metadata: makeMetadata())

    #expect(markdown.contains("**方式** どちらにしますか？"))
    #expect(markdown.contains("- A — こちら"))
    #expect(markdown.contains("→ 回答: A"))
}

@Test("時刻は設定で外せる")
func export_timestampsAreOptional() {
    let items: [ChatItem] = [.userMessage(id: "1", text: "hi", timestamp: fixedDate)]
    let markdown = ChatTranscriptExporter.markdown(
        items: items,
        metadata: makeMetadata(),
        options: ChatTranscriptExportOptions(includesTimestamps: false)
    )
    #expect(markdown.contains("## 👤 ユーザー\n"))
    #expect(markdown.contains("## 👤 ユーザー —") == false)
}

@Test("既定ファイル名はパスに使えない文字を潰す")
func export_suggestedFileNameSanitizesTitle() {
    let name = ChatTranscriptExporter.suggestedFileName(sessionTitle: "a/b:c", exportedAt: fixedDate)
    #expect(name.hasPrefix("a-b-c-"))
    #expect(name.hasSuffix(".md"))
    #expect(name.contains("/") == false)
}

@Test("空タイトルでも既定ファイル名が壊れない")
func export_suggestedFileNameFallsBack() {
    let name = ChatTranscriptExporter.suggestedFileName(sessionTitle: "   ", exportedAt: fixedDate)
    #expect(name.hasPrefix("chat-"))
}
