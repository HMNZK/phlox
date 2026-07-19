import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

// task-4 受け入れテスト（PM 著・凍結）。契約: tasks/task-4.md / PhloxQuestionWireContract。
// fixture は macOS 側 ControlQuestionWireContract の出力（task-3）と同一形（契約の共有 fixture）。
// アサーションの変更は禁止。テストハーネスの欠陥を発見した場合は PM に報告し、
// 承認を得たうえでハーネス部分に限り修理してよい。

@Suite("AskUserQuestion デコード（契約 fixture）")
struct UserQuestionDecodingAcceptanceTests {
    private let pendingFixture = """
    {"sessionId":"S1","messages":[
      {"id":"a1","type":"agent","text":"before"},
      {"id":"question-req-1","type":"userQuestion","requestId":"req-1","state":"pending",
       "questions":[{"question":"デプロイ先は?","header":"Deploy","multiSelect":false,
         "options":[{"label":"staging","description":"検証環境"},{"label":"prod"}]}]}
    ]}
    """

    private let answeredFixture = """
    {"sessionId":"S1","messages":[
      {"id":"question-req-2","type":"userQuestion","requestId":"req-2","state":"answered",
       "questions":[{"question":"含める機能は?","header":"Scope","multiSelect":true,
         "options":[{"label":"A"},{"label":"B"},{"label":"C"}]}],
       "answers":{"含める機能は?":["A","C"]}}
    ]}
    """

    @Test("pending の userQuestion が ChatMessage.userQuestion にデコードされる")
    func decodesPendingUserQuestion() throws {
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(pendingFixture.utf8))
        let messages = dto.messages.compactMap { $0.toDomain() }
        #expect(messages.count == 2)
        guard case let .userQuestion(id, requestId, questions, answers, state)? = messages.last else {
            Issue.record("expected userQuestion, got \(String(describing: messages.last))")
            return
        }
        #expect(id == "question-req-1")
        #expect(requestId == "req-1")
        #expect(state == .pending)
        #expect(answers == nil)
        #expect(questions.count == 1)
        guard let question = questions.first else { return }
        #expect(question.question == "デプロイ先は?")
        #expect(question.header == "Deploy")
        #expect(question.multiSelect == false)
        guard question.options.count == 2 else {
            Issue.record("expected 2 options, got \(question.options)")
            return
        }
        #expect(question.options[0].label == "staging")
        #expect(question.options[0].description == "検証環境")
        #expect(question.options[1].label == "prod")
        #expect(question.options[1].description == nil)
    }

    @Test("answered の userQuestion が answers/state 付きでデコードされる")
    func decodesAnsweredUserQuestion() throws {
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(answeredFixture.utf8))
        let messages = dto.messages.compactMap { $0.toDomain() }
        #expect(messages.count == 1)
        guard case let .userQuestion(_, requestId, questions, answers, state)? = messages.first else {
            Issue.record("expected userQuestion, got \(String(describing: messages.first))")
            return
        }
        #expect(requestId == "req-2")
        #expect(state == .answered)
        #expect(answers == ["含める機能は?": ["A", "C"]])
        #expect(questions.first?.multiSelect == true)
    }

    @Test("expired state もデコードされる")
    func decodesExpiredState() throws {
        let fixture = """
        {"sessionId":"S1","messages":[
          {"id":"q3","type":"userQuestion","requestId":"req-3","state":"expired",
           "questions":[{"question":"Q","header":"H","multiSelect":false,"options":[{"label":"A"},{"label":"B"}]}]}
        ]}
        """
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(fixture.utf8))
        let messages = dto.messages.compactMap { $0.toDomain() }
        guard case let .userQuestion(_, _, _, _, state)? = messages.first else {
            Issue.record("expected userQuestion, got \(String(describing: messages.first))")
            return
        }
        #expect(state == .expired)
    }

    @Test("必須フィールド欠落・未知 state は nil（前方互換の除外方針を維持）")
    func malformedUserQuestionIsDropped() throws {
        let fixture = """
        {"sessionId":"S1","messages":[
          {"id":"broken-1","type":"userQuestion","state":"pending",
           "questions":[{"question":"Q","header":"H","multiSelect":false,"options":[{"label":"A"},{"label":"B"}]}]},
          {"id":"broken-2","type":"userQuestion","requestId":"req-x","state":"???",
           "questions":[{"question":"Q","header":"H","multiSelect":false,"options":[{"label":"A"},{"label":"B"}]}]},
          {"id":"ok","type":"agent","text":"still works"}
        ]}
        """
        let dto = try JSONDecoder().decode(ChatMessagesDTO.self, from: Data(fixture.utf8))
        let messages = dto.messages.compactMap { $0.toDomain() }
        #expect(messages.count == 1)
        #expect(messages.first?.id == "ok")
    }
}
