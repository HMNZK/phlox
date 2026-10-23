import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

@Suite("質問IDのデコード")
struct UserQuestionIdentityDecodingTests {
    @Test("同文の質問と回答キーをwireのIDのまま保持する")
    func preservesQuestionIDsAndAnswers() throws {
        let json = """
        {"sessionId":"S1","messages":[
          {"id":"card","type":"userQuestion","requestId":"req","state":"answered",
           "questions":[
             {"id":"0","question":"同じ質問","header":"質問","multiSelect":false,"options":[]},
             {"id":"1","question":"同じ質問","header":"質問","multiSelect":false,"options":[]}
           ],"answers":{"0":["最初の回答"],"1":["次の回答"]}}
        ]}
        """
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(json.utf8))
        let message = try #require(dto.messages.first?.toDomain())
        guard case let .userQuestion(_, _, questions, answers, state) = message else {
            Issue.record("質問カードを受信できなかった")
            return
        }

        #expect(questions.map(\.id) == ["0", "1"])
        #expect(questions.map(\.answerKey) == ["0", "1"])
        #expect(answers == ["0": ["最初の回答"], "1": ["次の回答"]])
        #expect(state == .answered)
    }

    @Test("IDのない従来のwireは質問文で回答できる")
    func decodesLegacyQuestionsWithoutID() throws {
        let json = """
        {"question":"従来の質問","header":"質問","multiSelect":false,"options":[]}
        """
        let dto = try JSONDecoder().decode(UserQuestionItemDTO.self, from: Data(json.utf8))
        let question = dto.toDomain()

        #expect(question.id == nil)
        #expect(question.answerKey == "従来の質問")
    }
}
