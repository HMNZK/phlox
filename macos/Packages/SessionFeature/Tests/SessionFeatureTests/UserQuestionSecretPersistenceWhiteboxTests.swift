import StructuredChatKit
import Testing

@Suite("Whitebox: 秘密回答の永続化マスク（task-6）")
struct UserQuestionSecretPersistenceWhiteboxTests {
    @Test("秘密の回答だけを固定長マスクへ置き換え、通常の回答は保持する")
    func persistedAnswersMaskOnlySecretQuestions() {
        let secretQuestion = ChatUserQuestion(
            question: "API キー",
            header: "認証",
            options: [],
            multiSelect: false,
            id: "secret",
            isSecret: true
        )
        let plainQuestion = ChatUserQuestion(
            question: "方式",
            header: "設定",
            options: [],
            multiSelect: false
        )
        let answers = ["secret": ["short", "a much longer secret"], "方式": ["A案"]]

        let persisted = ChatUserQuestion.persistedAnswers(
            from: answers,
            for: [secretQuestion, plainQuestion]
        )

        #expect(persisted["secret"] == ["●●●●●●●●", "●●●●●●●●"])
        #expect(persisted["方式"] == ["A案"])
    }
}
