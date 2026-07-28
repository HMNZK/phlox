import Foundation
import Testing
import StructuredChatKit
@testable import SessionFeature

@Suite("Whitebox: UserQuestionFormModel 自由入力フォーカス（task-5）")
struct UserQuestionFocusWhiteboxTests {
    private func cellSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let sourceURL = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/SessionFeature/UserQuestionCell.swift")
        return try String(contentsOf: sourceURL, encoding: .utf8)
    }

    private func question(_ text: String) -> ChatUserQuestion {
        ChatUserQuestion(
            question: text,
            header: "H",
            options: [ChatUserQuestionOption(label: "A"), ChatUserQuestionOption(label: "B")],
            multiSelect: false
        )
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

    @Test func 自由入力欄のフォーカスがモデルへ配線されている() throws {
        let source = try cellSource()

        #expect(source.contains("@FocusState private var focusedFreeTextQuestion"))
        #expect(source.contains(".focused($focusedFreeTextQuestion, equals: question.question)"))
        #expect(source.contains("form.freeTextDidFocus(question: question.question)"))
        #expect(source.contains("form.freeTextDidChangeWhileFocused(question: questionText, text: newValue)"))
    }

    @Test func 自由入力欄は複数行で折り返す() throws {
        let source = try cellSource()

        #expect(source.contains("axis: .vertical"))
        #expect(source.contains(".lineLimit(1...4)"))
    }
}
