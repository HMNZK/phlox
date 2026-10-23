import Foundation
import StructuredChatKit

struct CodexAsyncQuestionID: Equatable, Sendable {
    private static let prefix = "codex-async:"
    let threadID: String
    let turnID: String
    let itemID: String
    let requestID: String

    init?(threadID: String, turnID: String, itemID: String) {
        guard [threadID, turnID, itemID].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              let data = try? JSONEncoder().encode([threadID, turnID, itemID]) else { return nil }
        self.threadID = threadID
        self.turnID = turnID
        self.itemID = itemID
        self.requestID = Self.prefix + "1:" + data.base64EncodedString()
    }

    init?(requestID: String) {
        guard requestID.hasPrefix(Self.prefix + "1:"),
              let data = Data(base64Encoded: String(requestID.dropFirst((Self.prefix + "1:").count))),
              let parts = try? JSONDecoder().decode([String].self, from: data), parts.count == 3
        else { return nil }
        self.init(threadID: parts[0], turnID: parts[1], itemID: parts[2])
    }

    static func isAsyncRequest(_ requestID: String) -> Bool {
        requestID.hasPrefix(prefix)
    }

    static func answerText(questions: [ChatUserQuestion], answers: [String: [String]]) -> String? {
        guard !questions.isEmpty,
              Set(answers.keys) == Set(questions.map(\.answerKey)) else { return nil }
        var lines: [String] = []
        for (index, question) in questions.enumerated() {
            guard let values = answers[question.answerKey], values.count == 1,
                  !values[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            lines.append("\(index + 1). \(question.question)\n\(values[0])")
        }
        return lines.joined(separator: "\n\n")
    }
}
