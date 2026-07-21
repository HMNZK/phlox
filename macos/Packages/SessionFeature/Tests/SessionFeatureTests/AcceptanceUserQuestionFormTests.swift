// 契約の正本: tasks/task-3.md — AskUserQuestion カードの明示送信（選択で即送信をやめる）。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 契約（UserQuestionFormModel — 純粋なフォーム状態。送信の副作用を持たない）:
//   - selectSingle は選択の置き換えのみ（送信しない。payload は canSubmit 成立まで nil）
//   - toggleMulti はトグルのみ
//   - 全質問に回答（選択、または空白でない自由入力）が揃って初めて canSubmit == true
//   - 自由入力は同一質問の選択より優先される（非空のとき）
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

@Suite("Acceptance: AskUserQuestion フォームの明示送信（ask-question-ux task-3）")
struct AcceptanceUserQuestionFormTests {
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
}
