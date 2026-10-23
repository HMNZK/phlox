import Testing
import PhloxCore
@testable import Features

@Suite("質問IDごとの回答")
struct UserQuestionIdentityTests {
    @Test("同文の質問でも異なるIDへ選択と自由入力を送る")
    func duplicateTitlesHaveIndependentAnswers() {
        let first = question(id: "0")
        let second = question(id: "1")
        var form = UserQuestionFormState(questions: [first, second])

        form.selectSingle(question: first.answerKey, label: "A")
        #expect(form.unansweredCount == 1)
        #expect(!form.canSubmit)
        form.setFreeText(question: second.answerKey, text: "独自の回答")

        #expect(form.answers == ["0": ["A"], "1": ["独自の回答"]])
        #expect(form.canSubmit)
        #expect(first.question == second.question)
    }

    @Test("ID付きの保存回答を別々に復元する")
    func restoresAnswersByID() {
        var form = UserQuestionFormState(questions: [question(id: "0"), question(id: "1")])
        let answers = ["0": ["B"], "1": ["補足"]]

        form.seed(from: answers)

        #expect(form.answers == answers)
        #expect(form.selections["0"] == ["B"])
        #expect(form.freeText["1"] == "補足")
    }

    @Test("IDのない従来の質問は質問文を回答キーに使う")
    func preservesLegacyAnswerKeys() {
        let question = question(id: nil)
        var form = UserQuestionFormState(questions: [question])

        form.selectSingle(question: question.answerKey, label: "A")

        #expect(question.answerKey == "同じ質問")
        #expect(form.answers == ["同じ質問": ["A"]])
    }

    @Test("回答済みカードもIDで回答を取り出す")
    func settledCardsUseAnswerID() {
        let question = question(id: "0")
        let details = SessionDetailTranscriptPresentation.settledQuestionDetails(
            for: question,
            state: .answered,
            answers: ["0": ["補足"]]
        )

        #expect(details == [.input("補足")])
    }

    private func question(id: String?) -> UserQuestionItem {
        UserQuestionItem(
            question: "同じ質問",
            header: "選択",
            options: [UserQuestionOption(label: "A"), UserQuestionOption(label: "B")],
            multiSelect: false,
            id: id
        )
    }
}
