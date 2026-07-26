import Foundation
import XCTest
import PhloxCore
@testable import Features

/// task-6 受け入れテスト（PM 著・**実装役は編集禁止**）。
///
/// 凍結する契約:
///  1. 自由入力欄にフォーカスすると、その質問の選択（single）が解除される。
///  2. 自由入力欄にフォーカスすると、その質問の選択（multi）が全解除される。
///  3. フォーカスは他の質問の選択に影響しない。
///  4. 選択肢をタップすると自由入力がクリアされる（既存 UserQuestionCard.swift:169-170 の挙動を維持）。
///  5. フォーカスだけでは回答が成立しない。
///  6. 自由入力が非空なら回答は自由入力（既存の優先順位を維持）。空白のみは回答扱いにしない。
///
/// 実装役が満たすべき公開面（この契約に合わせて実装すること）:
/// View の `@State` に散っていた回答フォーム状態を純粋な値型へ切り出す。
/// ```swift
/// // ios/Packages/PhloxKit/Sources/Features/SessionDetail/UserQuestionFormState.swift
/// struct UserQuestionFormState: Equatable {
///     init(questions: [UserQuestionItem])
///     var selections: [String: Set<String>] { get }
///     var freeText: [String: String] { get }
///     mutating func selectSingle(question: String, label: String)
///     mutating func toggleMulti(question: String, label: String)
///     mutating func setFreeText(question: String, text: String)
///     mutating func freeTextDidFocus(question: String)   // フォーカスを表す明示の遷移
///     var canSubmit: Bool { get }
///     var answers: [String: [String]]? { get }           // canSubmit == false のときは nil
/// }
/// ```
/// **`setFreeText` の中で選択解除してはならない**（テキストを空に戻したときに選択へ戻れなくなる）。
final class AcceptanceUserQuestionCardFocusTests: XCTestCase {

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

    /// 契約1
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

    /// 契約2
    func testFocusClearsAllMultiSelections() {
        var form = UserQuestionFormState(questions: [multi("Q1")])
        form.toggleMulti(question: "Q1", label: "X")
        form.toggleMulti(question: "Q1", label: "Y")
        XCTAssertEqual(form.selections["Q1", default: []].count, 2, "前提: 2件選択されている")

        form.freeTextDidFocus(question: "Q1")

        XCTAssertTrue(form.selections["Q1", default: []].isEmpty, "複数選択も全解除される")
    }

    /// 契約3
    func testFocusDoesNotAffectOtherQuestions() {
        var form = UserQuestionFormState(questions: [single("Q1"), single("Q2")])
        form.selectSingle(question: "Q1", label: "A案")
        form.selectSingle(question: "Q2", label: "B案")

        form.freeTextDidFocus(question: "Q1")

        XCTAssertTrue(form.selections["Q1", default: []].isEmpty)
        XCTAssertEqual(form.selections["Q2"], ["B案"], "別の質問の選択は保持される")
    }

    /// 契約4: 既存挙動（選択肢タップで自由入力クリア）の維持。
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

    /// 契約5
    func testFocusAloneDoesNotSatisfyAnswer() {
        var form = UserQuestionFormState(questions: [single("Q1")])
        form.selectSingle(question: "Q1", label: "A案")
        form.freeTextDidFocus(question: "Q1")

        XCTAssertFalse(form.canSubmit, "選択が解除され自由入力も空なので未回答")
        XCTAssertNil(form.answers)
    }

    /// 契約6: 自由入力の優先順位と空白扱いは既存どおり。
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

    /// 契約7: View がフォーカス連動と折り返しを実際に配線している。
    /// 値型だけ直して View が繋がっていなければユーザーの症状は 1 つも消えないため、
    /// ソースを直接読んで配線を凍結する（同パッケージの
    /// `Wave3SessionDetailChromeWhiteboxTests.swift` に前例のある方式）。
    func testUserQuestionCardWiresFocusAndWrapping() throws {
        let source = try sourceText("Sources/Features/SessionDetail/UserQuestionCard.swift")
        let compact = source.filter { !$0.isWhitespace }

        XCTAssertTrue(
            source.contains("@FocusState"),
            "自由入力欄のフォーカスを View が観測すること（要望1の配線）"
        )
        XCTAssertTrue(
            compact.contains("freeTextDidFocus("),
            "フォーカス時に freeTextDidFocus(question:) を呼ぶこと。呼ばなければ選択は外れない"
        )
        XCTAssertTrue(
            compact.contains("axis:.vertical"),
            "自由入力欄は axis: .vertical で複数行にすること（要望2＝右端で折り返す）"
        )
        XCTAssertTrue(
            compact.contains("UserQuestionFormState"),
            "選択・自由入力の状態は View の @State に散らさず UserQuestionFormState で持つこと"
        )
    }

    // MARK: - helpers

    private func sourceText(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: packageRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }
}
