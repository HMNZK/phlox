import Foundation
import Testing
@testable import CodexAppServerKit

@Suite("Async question protocol")
struct AsyncQuestionProtocolTests {
    @Test("カード用の質問は選択肢と自由入力を保持し、不正な一部だけを採用しない")
    func completeQuestionBatches() throws {
        func item(_ questions: [JSONValue], delivery: String = "async") throws -> ThreadItem {
            try JSONDecoder().decode(ThreadItem.self, from: JSONEncoder().encode(JSONValue.object([
                "type": .string("agentMessage"), "delivery": .string(delivery), "questions": .array(questions),
            ])))
        }
        let question: JSONValue = .object([
            "title": .string("同じ質問"), "options": .array([.string("はい"), .string("いいえ")]),
        ])
        let questions = try item([question, .object(["title": .string("同じ質問")])]).asyncQuestions
        #expect(questions.map(\.title) == ["同じ質問", "同じ質問"])
        #expect(questions[0].options == ["はい", "いいえ"])
        #expect(questions[1].options == nil)
        for invalid: JSONValue in [
            .null, .object(["title": .string(" ")]),
            .object(["title": .string("question"), "options": .array([])]),
            .object(["title": .string("question"), "options": .array([.string(" ")])]),
            .object(["title": .string("question"), "options": .array([.number(1)])]),
            .object(["title": .string("question"), "options": .string("invalid")]),
        ] {
            #expect(try item([question, invalid]).asyncQuestions.isEmpty)
        }
        #expect(try item([question], delivery: "normal").asyncQuestions.isEmpty)
    }

    @Test("0.163.0形式の質問を保持し、普通の文章や空質問から推測しない")
    func structuredQuestionsOnly() throws {
        func decode(_ fields: [String: JSONValue]) throws -> ThreadItem {
            try JSONDecoder().decode(ThreadItem.self, from: JSONEncoder().encode(JSONValue.object(fields)))
        }
        let base: [String: JSONValue] = ["id": .string("q"), "type": .string("agentMessage"),
                                        "text": .string("続けますか？")]
        #expect(try decode(base).asyncQuestionTitles.isEmpty)
        var raw = base
        raw["delivery"] = .string("async")
        raw["questions"] = .array([.object(["title": .string("承認しますか？")]),
                                    .object(["title": .string("どちらを選びますか？")]),
                                    .object(["title": .string(" ")])])
        let item = try decode(raw)
        #expect(item.asyncQuestionTitles == ["承認しますか？", "どちらを選びますか？"])
        #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(item)) == .object(raw))
        raw["delivery"] = .null
        #expect(try decode(raw).asyncQuestionTitles.isEmpty)
        raw["delivery"] = .string("async")
        raw["type"] = .string("reasoning")
        #expect(try decode(raw).asyncQuestionTitles.isEmpty)
    }
}
