import XCTest
import PhloxCore
@testable import Features

final class UserQuestionCardFocusWhiteboxTests: XCTestCase {
    private func question(_ text: String = "Q", multiSelect: Bool = false) -> UserQuestionItem {
        UserQuestionItem(
            question: text,
            header: "H",
            options: [UserQuestionOption(label: "A"), UserQuestionOption(label: "B")],
            multiSelect: multiSelect
        )
    }

    func testUpdatingFreeTextDoesNotClearSelectionUntilFocusTransition() {
        var form = UserQuestionFormState(questions: [question()])
        form.selectSingle(question: "Q", label: "A")

        form.setFreeText(question: "Q", text: "独自回答")

        XCTAssertEqual(form.selections["Q"], ["A"])
        XCTAssertEqual(form.freeText["Q"], "独自回答")
    }

    func testSelectingOptionClearsFreeTextAndUsesSortedMultiAnswers() {
        var form = UserQuestionFormState(questions: [question(multiSelect: true)])
        form.setFreeText(question: "Q", text: "独自回答")

        form.toggleMulti(question: "Q", label: "B")
        form.toggleMulti(question: "Q", label: "A")

        XCTAssertEqual(form.freeText["Q"], "")
        XCTAssertEqual(form.answers, ["Q": ["A", "B"]])
    }

    func testSeedRestoresKnownOptionsAndCustomAnswer() {
        var form = UserQuestionFormState(questions: [question()])

        form.seed(from: ["Q": ["A", "復元済み入力"]])

        XCTAssertEqual(form.selections["Q"], ["A"])
        XCTAssertEqual(form.freeText["Q"], "復元済み入力")
    }
}
