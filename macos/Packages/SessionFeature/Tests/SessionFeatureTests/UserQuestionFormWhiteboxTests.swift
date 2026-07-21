import Foundation
import Testing
import StructuredChatKit
@testable import SessionFeature

// task-3 白箱テスト（実装エージェント著）。受け入れテストが触れない複合・境界を補完する。

private func single(_ text: String, options: [String] = ["A案", "B案"]) -> ChatUserQuestion {
    ChatUserQuestion(
        question: text,
        header: "H",
        options: options.map { ChatUserQuestionOption(label: $0) },
        multiSelect: false
    )
}

private func multi(_ text: String, options: [String] = ["X", "Y", "Z"]) -> ChatUserQuestion {
    ChatUserQuestion(
        question: text,
        header: "H",
        options: options.map { ChatUserQuestionOption(label: $0) },
        multiSelect: true
    )
}

@Suite("Whitebox: UserQuestionFormModel（ask-question-ux task-3）")
struct UserQuestionFormWhiteboxTests {
    @Test func 選択肢なし質問は自由入力のみで成立する() {
        let question = ChatUserQuestion(
            question: "Q1",
            header: "H",
            options: [],
            multiSelect: false
        )
        var form = UserQuestionFormModel(questions: [question])
        form.setFreeText(question: "Q1", text: "メモ")

        #expect(form.canSubmit)
        #expect(form.payload == ["Q1": ["メモ"]])
    }

    @Test func 複数質問カードは単一質問だけ回答では送信不可() {
        var form = UserQuestionFormModel(questions: [single("Q1"), multi("Q2")])
        form.selectSingle(question: "Q1", label: "A案")

        #expect(form.canSubmit == false)
        #expect(form.payload == nil)

        form.toggleMulti(question: "Q2", label: "X")
        #expect(form.canSubmit)
        #expect(form.payload == ["Q1": ["A案"], "Q2": ["X"]])
    }

    @Test func 自由入力を空に戻すと選択肢回答にフォールバックする() {
        var form = UserQuestionFormModel(questions: [single("Q1")])
        form.selectSingle(question: "Q1", label: "A案")
        form.setFreeText(question: "Q1", text: "一時入力")
        form.setFreeText(question: "Q1", text: "")

        #expect(form.canSubmit)
        #expect(form.payload == ["Q1": ["A案"]])
    }

    @Test func payloadは質問定義順ではなく質問文キーで安定する() {
        var form = UserQuestionFormModel(questions: [single("Q2"), single("Q1")])
        form.selectSingle(question: "Q2", label: "B案")
        form.selectSingle(question: "Q1", label: "A案")

        guard let payload = form.payload else {
            Issue.record("expected payload")
            return
        }
        #expect(payload.keys.sorted() == ["Q1", "Q2"])
        #expect(payload["Q1"] == ["A案"])
        #expect(payload["Q2"] == ["B案"])
    }
}
