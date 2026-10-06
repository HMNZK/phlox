import Foundation
import XCTest
import PhloxCore
@testable import Features

/// ユーザー質問カードの回答フォーム状態（`UserQuestionFormState`）。
///
///  1. 自由入力欄にフォーカスすると、その質問の選択（single / multi）が解除される。
///  2. フォーカスは他の質問の選択に影響しない。
///  3. 選択肢をタップすると自由入力がクリアされる。
///  4. フォーカスだけでは回答が成立しない。
///  5. 自由入力が非空なら回答は自由入力。空白のみは回答扱いにしない。
///
/// `setFreeText` の中で選択解除してはならない（テキストを空に戻したときに選択へ戻れなくなる）。
final class UserQuestionFormStateTests: XCTestCase {

    private func single(_ text: String, options: [String] = ["A案", "B案"]) -> UserQuestionItem {
        UserQuestionItem(
            question: text,
            header: "H",
            options: options.map { UserQuestionOption(label: $0) },
            multiSelect: false
        )
    }

    private func multi(_ text: String, options: [String] = ["X", "Y", "Z"]) -> UserQuestionItem {
        UserQuestionItem(
            question: text,
            header: "H",
            options: options.map { UserQuestionOption(label: $0) },
            multiSelect: true
        )
    }

    func testFocusClearsSingleSelection() {
        var form = UserQuestionFormState(questions: [single("Q1")])
        form.selectSingle(question: "Q1", label: "A案")
        XCTAssertEqual(form.selections["Q1"], ["A案"], "前提: 選択されている")

        form.freeTextDidFocus(question: "Q1")

        XCTAssertTrue(
            form.selections["Q1", default: []].isEmpty,
            "自由入力にフォーカスしたら選択肢は非選択になる"
        )
    }

    func testFocusClearsAllMultiSelections() {
        var form = UserQuestionFormState(questions: [multi("Q1")])
        form.toggleMulti(question: "Q1", label: "X")
        form.toggleMulti(question: "Q1", label: "Y")
        XCTAssertEqual(form.selections["Q1", default: []].count, 2, "前提: 2件選択されている")

        form.freeTextDidFocus(question: "Q1")

        XCTAssertTrue(form.selections["Q1", default: []].isEmpty, "複数選択も全解除される")
    }

    func testFocusDoesNotAffectOtherQuestions() {
        var form = UserQuestionFormState(questions: [single("Q1"), single("Q2")])
        form.selectSingle(question: "Q1", label: "A案")
        form.selectSingle(question: "Q2", label: "B案")

        form.freeTextDidFocus(question: "Q1")

        XCTAssertTrue(form.selections["Q1", default: []].isEmpty)
        XCTAssertEqual(form.selections["Q2"], ["B案"], "別の質問の選択は保持される")
    }

    func testSelectingOptionClearsFreeText() {
        var form = UserQuestionFormState(questions: [single("Q1")])
        form.setFreeText(question: "Q1", text: "独自の回答")
        form.selectSingle(question: "Q1", label: "A案")

        XCTAssertEqual(
            form.answers ?? [:],
            ["Q1": ["A案"]],
            "選択肢をタップしたら自由入力はクリアされ、表示どおり選択肢が送られる"
        )
    }

    func testFocusAloneDoesNotSatisfyAnswer() {
        var form = UserQuestionFormState(questions: [single("Q1")])
        form.selectSingle(question: "Q1", label: "A案")
        form.freeTextDidFocus(question: "Q1")

        XCTAssertFalse(form.canSubmit, "選択が解除され自由入力も空なので未回答")
        XCTAssertNil(form.answers)
    }

    func testFreeTextTakesPrecedenceAndBlankIsNotAnAnswer() {
        var form = UserQuestionFormState(questions: [single("Q1")])
        form.freeTextDidFocus(question: "Q1")
        form.setFreeText(question: "Q1", text: "独自の回答")
        XCTAssertTrue(form.canSubmit)
        XCTAssertEqual(form.answers ?? [:], ["Q1": ["独自の回答"]])

        var blank = UserQuestionFormState(questions: [single("Q1")])
        blank.setFreeText(question: "Q1", text: "   \n ")
        XCTAssertFalse(blank.canSubmit, "空白のみは回答扱いにしない")
    }

    /// 選択肢が無い質問は自由入力のみで成立する。
    func testQuestionWithoutOptionsIsAnsweredByFreeTextOnly() {
        let question = UserQuestionItem(question: "Q1", header: "H", options: [], multiSelect: false)
        var form = UserQuestionFormState(questions: [question])
        form.setFreeText(question: "Q1", text: "メモ")

        XCTAssertTrue(form.canSubmit)
        XCTAssertEqual(form.answers ?? [:], ["Q1": ["メモ"]])
    }

    /// 複数質問カードは全問回答で初めて送信可能。
    func testAllQuestionsMustBeAnswered() {
        var form = UserQuestionFormState(questions: [single("Q1"), multi("Q2")])
        form.selectSingle(question: "Q1", label: "A案")
        XCTAssertFalse(form.canSubmit)

        form.toggleMulti(question: "Q2", label: "X")
        XCTAssertTrue(form.canSubmit)
        XCTAssertEqual(form.answers ?? [:], ["Q1": ["A案"], "Q2": ["X"]])
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

    func testSelectingOptionReleasesFocusSoReentryClearsSelectionBeforeSendingFreeText() {
        var form = UserQuestionFormState(questions: [question()])
        form.freeTextDidFocus(question: "Q")
        form.selectSingle(question: "Q", label: "A")

        form.freeTextDidFocus(question: "Q")
        form.setFreeText(question: "Q", text: "独自回答")

        XCTAssertTrue(form.selections["Q", default: []].isEmpty)
        XCTAssertEqual(form.answers, ["Q": ["独自回答"]])
    }

    private func question(_ text: String = "Q", multiSelect: Bool = false) -> UserQuestionItem {
        UserQuestionItem(
            question: text,
            header: "H",
            options: [UserQuestionOption(label: "A"), UserQuestionOption(label: "B")],
            multiSelect: multiSelect
        )
    }
}
