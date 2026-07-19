import Foundation
import Testing
import StructuredChatKit
@testable import SessionFeature

// task-0 受け入れテスト（PM 著・凍結）。契約: ChatItem.userQuestion の Codable 後方互換。
// アサーションの変更は禁止。テストハーネスの欠陥を発見した場合は PM に報告し、
// 承認を得たうえでハーネス部分に限り修理してよい。

private let sampleQuestions = [
    ChatUserQuestion(
        question: "デプロイ先は?",
        header: "Deploy",
        options: [
            ChatUserQuestionOption(label: "staging", description: "検証環境"),
            ChatUserQuestionOption(label: "prod", description: nil),
        ],
        multiSelect: false
    ),
    ChatUserQuestion(
        question: "含める機能は?",
        header: "Scope",
        options: [
            ChatUserQuestionOption(label: "A", description: nil),
            ChatUserQuestionOption(label: "B", description: nil),
        ],
        multiSelect: true
    ),
]

@Suite struct AcceptanceUserQuestionChatItemCodableTests {
    @Test func pendingUserQuestionRoundTripsThroughCodable() throws {
        let item = ChatItem.userQuestion(
            id: "question-req-1",
            requestId: "req-1",
            questions: sampleQuestions,
            answers: nil,
            state: .pending,
            timestamp: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode([item])
        let decoded = try JSONDecoder().decode([ChatItem].self, from: data)
        #expect(decoded == [item])
    }

    @Test func answeredUserQuestionRoundTripsWithAnswers() throws {
        let item = ChatItem.userQuestion(
            id: "question-req-2",
            requestId: "req-2",
            questions: sampleQuestions,
            answers: ["デプロイ先は?": ["staging"], "含める機能は?": ["A", "B"]],
            state: .answered,
            timestamp: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let data = try JSONEncoder().encode([item])
        let decoded = try JSONDecoder().decode([ChatItem].self, from: data)
        #expect(decoded == [item])
        if case let .userQuestion(_, _, _, answers, state, _) = decoded[0] {
            #expect(answers?["含める機能は?"] == ["A", "B"])
            #expect(state == .answered)
        } else {
            Issue.record("expected userQuestion, got \(decoded[0])")
        }
    }

    @Test func legacyTranscriptWithoutUserQuestionStillDecodes() throws {
        // 旧バージョンが書いたトランスクリプト（userQuestion なし）が読めること。
        let legacy = """
        [{"agentMessage":{"id":"a1","text":"hello","timestamp":700000000}},\
        {"turnCost":{"id":"t1","costUSD":0.5,"timestamp":700000001}}]
        """
        let decoded = try JSONDecoder().decode([ChatItem].self, from: Data(legacy.utf8))
        #expect(decoded.count == 2)
        #expect(decoded[0].id == "a1")
        #expect(decoded[1].id == "t1")
    }

    @Test func expiredStateSurvivesRoundTrip() throws {
        let item = ChatItem.userQuestion(
            id: "question-req-3",
            requestId: "req-3",
            questions: [sampleQuestions[0]],
            answers: nil,
            state: .expired,
            timestamp: Date(timeIntervalSince1970: 1_700_000_200)
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(ChatItem.self, from: data)
        if case let .userQuestion(_, _, _, _, state, _) = decoded {
            #expect(state == .expired)
        } else {
            Issue.record("expected userQuestion, got \(decoded)")
        }
    }
}
