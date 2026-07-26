import Foundation
import Testing
import StructuredChatKit
@testable import SessionFeature

/// task-5 受け入れテスト（PM 著・**アサーション変更禁止**）。
///
/// 凍結する契約:
///  1. 自由入力欄にフォーカスすると、その質問の選択（single）が解除される。
///  2. 自由入力欄にフォーカスすると、その質問の選択（multi）が全解除される。
///  3. フォーカスは他の質問の選択に影響しない。
///  4. 自由入力が残ったまま選択肢をタップしたら、送信内容は**表示どおり選択肢**になる（逆方向の食い違い解消）。
///  5. フォーカスだけでは回答が成立しない（選択が消え自由入力も空なので未回答）。
///
/// 実装役が満たすべき公開面（この契約に合わせて実装すること）:
/// ```swift
/// extension UserQuestionFormModel {
///     mutating func freeTextDidFocus(question: String)   // フォーカスを表す明示の遷移
/// }
/// ```
/// **`setFreeText` の中で選択解除してはならない**（既存白箱テスト
/// 「自由入力を空に戻すと選択肢回答にフォールバックする」が壊れる）。
@Suite("Acceptance: AskUserQuestion 自由入力のフォーカス挙動（task-5）")
struct AcceptanceUserQuestionFocusTests {

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

    @Test func 自由入力にフォーカスすると単一選択が解除される() {
        var form = UserQuestionFormModel(questions: [single("Q1")])
        form.selectSingle(question: "Q1", label: "A案")
        #expect(form.selections["Q1"] == ["A案"], "前提: 選択されている")

        form.freeTextDidFocus(question: "Q1")

        #expect(
            form.selections["Q1", default: []].isEmpty,
            "自由入力にフォーカスしたら選択肢は非選択になる（表示と送信のずれを作らない）"
        )
    }

    @Test func 自由入力にフォーカスすると複数選択が全解除される() {
        var form = UserQuestionFormModel(questions: [multi("Q1")])
        form.toggleMulti(question: "Q1", label: "X")
        form.toggleMulti(question: "Q1", label: "Y")
        #expect(form.selections["Q1", default: []].count == 2, "前提: 2件選択されている")

        form.freeTextDidFocus(question: "Q1")

        #expect(form.selections["Q1", default: []].isEmpty, "複数選択も全解除される")
    }

    @Test func フォーカスは他の質問の選択に影響しない() {
        var form = UserQuestionFormModel(questions: [single("Q1"), single("Q2")])
        form.selectSingle(question: "Q1", label: "A案")
        form.selectSingle(question: "Q2", label: "B案")

        form.freeTextDidFocus(question: "Q1")

        #expect(form.selections["Q1", default: []].isEmpty)
        #expect(form.selections["Q2"] == ["B案"], "別の質問の選択は保持される")
    }

    @Test func フォーカス後に自由入力すると自由入力だけがペイロードになる() {
        var form = UserQuestionFormModel(questions: [single("Q1")])
        form.selectSingle(question: "Q1", label: "A案")
        form.freeTextDidFocus(question: "Q1")
        form.setFreeText(question: "Q1", text: "独自の回答")

        #expect(form.canSubmit)
        #expect(form.payload == ["Q1": ["独自の回答"]])
    }

    @Test func 自由入力が残ったまま選択肢をタップすると送信内容は選択肢になる() {
        var form = UserQuestionFormModel(questions: [single("Q1")])
        form.setFreeText(question: "Q1", text: "独自の回答")
        form.selectSingle(question: "Q1", label: "A案")

        #expect(
            form.payload == ["Q1": ["A案"]],
            "選択肢をタップしたら自由入力はクリアされ、表示どおり選択肢が送られる（逆方向の食い違い解消）"
        )
    }

    @Test func 複数選択でも選択肢タップで自由入力がクリアされる() {
        var form = UserQuestionFormModel(questions: [multi("Q1")])
        form.setFreeText(question: "Q1", text: "独自の回答")
        form.toggleMulti(question: "Q1", label: "X")

        #expect(form.payload == ["Q1": ["X"]])
    }

    @Test func フォーカスだけでは回答が成立しない() {
        var form = UserQuestionFormModel(questions: [single("Q1")])
        form.selectSingle(question: "Q1", label: "A案")
        form.freeTextDidFocus(question: "Q1")

        #expect(
            form.canSubmit == false,
            "選択が解除され自由入力も空なので未回答（送信ボタンは無効のまま）"
        )
        #expect(form.payload == nil)
    }
}
