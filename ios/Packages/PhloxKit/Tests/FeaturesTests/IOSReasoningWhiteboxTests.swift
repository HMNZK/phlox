import Foundation
import Testing
import PhloxCore
@testable import Features

@Suite("iOS チャット行種別 白箱")
struct IOSReasoningWhiteboxTests {
    @Test("ChatRowKind は全メッセージ種別を表示器へ対応付ける")
    func mapsEveryMessageKind() {
        let question = UserQuestionItem(
            question: "どれを使いますか？",
            header: "選択",
            options: [UserQuestionOption(label: "A")],
            multiSelect: false
        )
        let messages: [(ChatMessage, ChatRowKind)] = [
            (.user(id: "u", text: "x"), .userBubble),
            (.agent(id: "a", text: "x"), .agentBubble),
            (.reasoning(id: "r", text: "x"), .reasoning),
            (.subAgent(id: "s", text: "x"), .subAgent),
            (.command(id: "c", command: "ls", output: ""), .commandCard),
            (.fileChange(id: "f", changes: []), .fileChangeCard),
            (.error(id: "e", message: "x"), .error),
            (
                .userQuestion(
                    id: "q",
                    requestId: "rq",
                    questions: [question],
                    answers: nil,
                    state: .pending
                ),
                .userQuestion
            ),
        ]

        for (message, expected) in messages {
            #expect(ChatRowKind.forMessage(message) == expected)
        }
    }

    @Test("行の描画分岐は ChatRowKind を駆動役にし、default で握りつぶさない")
    func chatRowSwitchIsExhaustiveByKind() throws {
        for relativePath in [
            "Sources/Features/SessionDetail/SessionDetailView.swift",
            "Sources/Features/SessionDetail/SubAgentDetailView.swift",
        ] {
            let source = try sourceText(relativePath)
            let compact = source.filter { !$0.isWhitespace }

            #expect(
                compact.contains("switchChatRowKind.forMessage(message){"),
                "\(relativePath): 行の種類は ChatRowKind で分岐すること"
            )
            #expect(
                !compact.contains("switch(ChatRowKind.forMessage(message),message)"),
                "\(relativePath): ChatRowKind をタプルの飾りにしないこと"
            )
            #expect(
                !compact.contains("default:EmptyView()"),
                "\(relativePath): default で未知の行を握りつぶさないこと"
            )
        }
    }

    private func sourceText(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
