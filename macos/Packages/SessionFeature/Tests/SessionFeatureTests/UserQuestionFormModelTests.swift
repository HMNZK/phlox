// AskUserQuestion の回答フォーム状態（UserQuestionFormModel）。純粋なフォーム状態で、送信の副作用を持たない。
//   - selectSingle は選択の置き換えのみ（送信しない。payload は canSubmit 成立まで nil）
//   - toggleMulti はトグルのみ
//   - 全質問に回答（選択、または空白でない自由入力）が揃って初めて canSubmit == true
//   - 自由入力は同一質問の選択より優先される（非空のとき）
//   - 自由入力欄にフォーカスすると選択は解除され、選択肢をタップすると自由入力はクリアされる
//     （表示と送信内容を食い違わせない）。`setFreeText` の中では選択を解除しない
//   - payload は「質問文 → 回答 label 配列」。multi-select はソート済み
// View 側（UserQuestionCell）はこのモデルを使い、カード最下部の送信ボタンからのみ onRespond を呼ぶ。

import Foundation
import Testing
import StructuredChatKit
@testable import SessionFeature

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

@Suite("UserQuestionFormModel")
struct UserQuestionFormModelTests {
    private func question(_ text: String) -> ChatUserQuestion {
        single(text, options: ["A", "B"])
    }

    @Test func 単一選択は選択しただけでは送信可能ペイロードを作らない_全問回答で成立する() {
        var form = UserQuestionFormModel(questions: [single("Q1"), single("Q2")])
        #expect(form.canSubmit == false)

        form.selectSingle(question: "Q1", label: "A案")

        #expect(form.canSubmit == false)  // まだ Q2 が未回答 = 即送信されない根拠
        #expect(form.payload == nil)

        form.selectSingle(question: "Q2", label: "B案")

        #expect(form.canSubmit)
        #expect(form.payload == ["Q1": ["A案"], "Q2": ["B案"]])
    }

    @Test func 単一選択は置き換えで多重選択にならない() {
        var form = UserQuestionFormModel(questions: [single("Q1")])
        form.selectSingle(question: "Q1", label: "A案")
        form.selectSingle(question: "Q1", label: "B案")

        #expect(form.payload == ["Q1": ["B案"]])
    }

    @Test func 複数選択はトグルで増減しソート済みで送信される() {
        var form = UserQuestionFormModel(questions: [multi("Q1")])
        form.toggleMulti(question: "Q1", label: "Z")
        form.toggleMulti(question: "Q1", label: "X")
        #expect(form.canSubmit)
        #expect(form.payload == ["Q1": ["X", "Z"]])

        form.toggleMulti(question: "Q1", label: "Z")
        #expect(form.payload == ["Q1": ["X"]])

        form.toggleMulti(question: "Q1", label: "X")
        #expect(form.canSubmit == false)  // 全解除で未回答に戻る
    }

    @Test func 自由入力は空白のみなら回答扱いにしない() {
        var form = UserQuestionFormModel(questions: [single("Q1")])
        form.setFreeText(question: "Q1", text: "   \n ")

        #expect(form.canSubmit == false)
    }

    @Test func 自由入力は非空なら選択より優先される() {
        var form = UserQuestionFormModel(questions: [single("Q1")])
        form.selectSingle(question: "Q1", label: "A案")
        form.setFreeText(question: "Q1", text: "独自の回答")

        #expect(form.canSubmit)
        #expect(form.payload == ["Q1": ["独自の回答"]])
    }

    // MARK: - 自由入力欄のフォーカス

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

    @Test func 自由入力の更新だけでは既存の選択を解除しない() {
        var form = UserQuestionFormModel(questions: [question("Q1")])
        form.selectSingle(question: "Q1", label: "A")

        form.setFreeText(question: "Q1", text: "一時入力")

        #expect(form.selections["Q1"] == ["A"])
        form.setFreeText(question: "Q1", text: "")
        #expect(form.payload == ["Q1": ["A"]])
    }

    @Test func 選択は対象質問の自由入力だけを解除する() {
        var form = UserQuestionFormModel(questions: [question("Q1"), question("Q2")])
        form.setFreeText(question: "Q1", text: "Q1 の入力")
        form.setFreeText(question: "Q2", text: "Q2 の入力")

        form.selectSingle(question: "Q1", label: "A")

        #expect(form.freeText["Q1"] == nil)
        #expect(form.freeText["Q2"] == "Q2 の入力")
        #expect(form.payload == ["Q1": ["A"], "Q2": ["Q2 の入力"]])
    }

    @Test func フォーカス中の非空入力は選択を解除する() {
        var form = UserQuestionFormModel(questions: [question("Q1")])
        form.selectSingle(question: "Q1", label: "A")

        form.freeTextDidChangeWhileFocused(question: "Q1", text: "後から入力")

        #expect(
            form.selections["Q1", default: []].isEmpty,
            "表示上チェックが残ったまま自由入力が送られてはならない"
        )
        #expect(form.payload == ["Q1": ["後から入力"]])
    }

    @Test func フォーカス中に空へ戻しても選択肢へのフォールバックを壊さない() {
        var form = UserQuestionFormModel(questions: [question("Q1")])
        form.selectSingle(question: "Q1", label: "A")

        form.freeTextDidChangeWhileFocused(question: "Q1", text: "")

        #expect(form.selections["Q1"] == ["A"])
        #expect(form.payload == ["Q1": ["A"]])
    }

    // MARK: - 境界

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
