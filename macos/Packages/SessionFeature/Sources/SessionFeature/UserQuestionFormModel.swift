import Foundation
import StructuredChatKit

/// AskUserQuestion カードの回答フォーム状態（ask-question-ux task-3 契約。
/// 受け入れテスト AcceptanceUserQuestionFormTests が凍結。スタブ実装＝task-3 が本実装する）。
///
/// 契約の骨子: 選択・入力はフォーム状態を更新するだけで送信の副作用を持たない。
/// 送信はカード最下部の送信ボタン（canSubmit のときのみ有効）から明示的に行う。
struct UserQuestionFormModel {
    let questions: [ChatUserQuestion]

    private(set) var selections: [String: Set<String>] = [:]
    private(set) var freeText: [String: String] = [:]

    init(questions: [ChatUserQuestion]) {
        self.questions = questions
    }

    /// single-select: 選択肢を1つ選ぶ（既選択の置き換え。送信はしない）。
    mutating func selectSingle(question: String, label: String) {
        selections[question] = [label]
    }

    /// multi-select: 選択肢をトグルする（送信はしない）。
    mutating func toggleMulti(question: String, label: String) {
        var updated = selections[question, default: []]
        if updated.contains(label) {
            updated.remove(label)
        } else {
            updated.insert(label)
        }
        selections[question] = updated
    }

    /// 自由入力を更新する（送信はしない）。
    mutating func setFreeText(question: String, text: String) {
        freeText[question] = text
    }

    /// 全質問に回答が揃ったときだけ true（選択肢の選択、または空白でない自由入力）。
    var canSubmit: Bool {
        questions.allSatisfy { isAnswered($0) }
    }

    /// 送信ペイロード（質問文 → 回答 label 配列）。canSubmit == false のときは nil。
    var payload: [String: [String]]? {
        guard canSubmit else { return nil }
        var result: [String: [String]] = [:]
        for question in questions {
            guard let labels = answerLabels(for: question) else { return nil }
            result[question.question] = labels
        }
        return result
    }

    private func trimmedFreeText(for question: String) -> String {
        freeText[question, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isAnswered(_ question: ChatUserQuestion) -> Bool {
        if !trimmedFreeText(for: question.question).isEmpty {
            return true
        }
        return !selections[question.question, default: []].isEmpty
    }

    private func answerLabels(for question: ChatUserQuestion) -> [String]? {
        let trimmed = trimmedFreeText(for: question.question)
        if !trimmed.isEmpty {
            return [trimmed]
        }
        let selected = selections[question.question, default: []]
        guard !selected.isEmpty else { return nil }
        if question.multiSelect {
            return selected.sorted()
        }
        return [selected.sorted().first!]
    }
}
