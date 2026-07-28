import Foundation
import PhloxCore

struct UserQuestionFormState: Equatable {
    private let questions: [UserQuestionItem]
    private(set) var selections: [String: Set<String>] = [:]
    private(set) var freeText: [String: String] = [:]

    init(questions: [UserQuestionItem]) {
        self.questions = questions
    }

    mutating func selectSingle(question: String, label: String) {
        let selected = selections[question] ?? []
        selections[question] = selected.contains(label) ? [] : [label]
        freeText[question] = ""
    }

    mutating func toggleMulti(question: String, label: String) {
        var selected = selections[question] ?? []
        if selected.contains(label) {
            selected.remove(label)
        } else {
            selected.insert(label)
        }
        selections[question] = selected
        freeText[question] = ""
    }

    mutating func setFreeText(question: String, text: String) {
        freeText[question] = text
    }

    mutating func freeTextDidFocus(question: String) {
        selections[question] = []
    }

    var canSubmit: Bool {
        questions.allSatisfy { question in
            let custom = freeText[question.question]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !custom.isEmpty || !(selections[question.question] ?? []).isEmpty
        }
    }

    var answers: [String: [String]]? {
        guard canSubmit else { return nil }

        var result: [String: [String]] = [:]
        for question in questions {
            let custom = freeText[question.question]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !custom.isEmpty {
                result[question.question] = [custom]
            } else {
                result[question.question] = Array(selections[question.question] ?? []).sorted()
            }
        }
        return result
    }

    mutating func seed(from answers: [String: [String]]) {
        for question in questions {
            guard let values = answers[question.question] else { continue }
            selections[question.question] = Set(values.filter { label in
                question.options.contains(where: { $0.label == label })
            })
            if let custom = values.first(where: { value in
                !question.options.contains(where: { $0.label == value })
            }) {
                freeText[question.question] = custom
            }
        }
    }
}
