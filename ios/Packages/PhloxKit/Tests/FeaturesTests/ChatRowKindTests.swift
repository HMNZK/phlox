import Foundation
import Testing
import PhloxCore
@testable import Features

@Suite("iOS チャット行種別")
struct ChatRowKindTests {
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
}
