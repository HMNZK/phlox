import Foundation
import Testing
@testable import CodexAppServerKit

@Suite("Async question protocol")
struct AsyncQuestionProtocolTests {
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
