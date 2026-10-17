import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

@Suite("ツール許可質問の wire 項目")
struct ToolPermissionQuestionTests {
    @Test("toolName と toolDetail を userQuestion の質問に写す")
    func decodesToolPermissionQuestion() throws {
        let json = """
        {"sessionId":"S1","messages":[
          {"id":"q1","type":"userQuestion","requestId":"r1","state":"pending",
           "questions":[{"question":"Allow Bash?","header":"Bash","multiSelect":false,
             "options":[{"label":"Allow"},{"label":"Deny"}],
             "toolName":"Bash","toolDetail":"swift build 2>&1 | tail -20"}]}
        ]}
        """
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(json.utf8))
        let message = try #require(dto.messages.first?.toDomain())
        guard case let .userQuestion(_, _, questions, _, _) = message else {
            Issue.record("expected userQuestion")
            return
        }
        let question = try #require(questions.first)

        #expect(question.toolName == "Bash")
        #expect(question.toolDetail == "swift build 2>&1 | tail -20")
        #expect(question.isToolPermission)
    }

    @Test("古い Mac や通常の質問で toolName が無ければ通常質問")
    func missingToolNameIsNotPermission() throws {
        let json = """
        {"question":"Deploy where?","header":"Deploy","multiSelect":false,
         "options":[{"label":"staging"}]}
        """
        let dto = try JSONDecoder().decode(UserQuestionItemDTO.self, from: Data(json.utf8))
        let question = dto.toDomain()

        #expect(question.toolName == nil)
        #expect(question.toolDetail == nil)
        #expect(!question.isToolPermission)
    }
}
