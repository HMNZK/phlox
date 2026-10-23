import Foundation
import SwiftUI
import Testing
import StructuredChatKit
@testable import SessionFeature

@Suite("Codex asynchronous question identity")
struct CodexAsyncQuestionIDTests {
    @Test func identifiersRoundTripWithoutDelimiterCollisions() throws {
        let first = try #require(CodexAsyncQuestionID(threadID: "thread:日本語", turnID: "turn", itemID: "a:b"))
        #expect(CodexAsyncQuestionID(requestID: first.requestID) == first)
        let other = try #require(CodexAsyncQuestionID(threadID: "thread", turnID: "日本語:turn", itemID: "a:b"))
        #expect(first.requestID != other.requestID)
        #expect(CodexAsyncQuestionID(threadID: "thread:日本語", turnID: "turn", itemID: "a:b")?.requestID == first.requestID)
    }

    @Test func malformedAndUnknownVersionsAreRejected() {
        let emptyThread = Data(#"["","turn","item"]"#.utf8).base64EncodedString()
        for id in ["plain", "codex-async:1:not-base64", "codex-async:2:W10=", "codex-async:1:W10=", "codex-async:1:" + emptyThread] {
            #expect(CodexAsyncQuestionID(requestID: id) == nil)
        }
        #expect(CodexAsyncQuestionID.isAsyncRequest("codex-async:2:W10="))
        #expect(CodexAsyncQuestionID(threadID: "thread", turnID: " ", itemID: "item") == nil)
    }

    @Test func incompleteBlankOrForeignAnswersAreRejected() {
        let questions = ["first", "second"].map {
            ChatUserQuestion(question: "同文", header: "", options: [], multiSelect: false, id: $0)
        }
        for answers in [["first": ["A"]], ["first": ["A"], "second": [" "]], ["first": ["A", "B"], "second": ["C"]], ["同文": ["A"]]] {
            #expect(CodexAsyncQuestionID.answerText(questions: questions, answers: answers) == nil)
        }
        #expect(CodexAsyncQuestionID.answerText(questions: questions, answers: ["first": ["A"], "second": ["B"]]) == "1. 同文\nA\n\n2. 同文\nB")
    }

    @Test @MainActor func blockingQuestionTakesPriorityOverEarlierAsynchronousQuestion() throws {
        let asyncID = try #require(CodexAsyncQuestionID(threadID: "thread", turnID: "turn", itemID: "item"))
        let questions = [ChatUserQuestion(question: "選択", header: "", options: [], multiSelect: false)]
        let asynchronous = ChatItem.userQuestion(id: "async", requestId: asyncID.requestID, questions: questions,
                                               answers: nil, state: .pending, timestamp: Date())
        let synchronous = ChatItem.userQuestion(id: "sync", requestId: "blocking", questions: questions,
                                              answers: nil, state: .pending, timestamp: Date())
        #expect(ChatReplyArea<EmptyView>.pendingQuestionItem(in: [asynchronous, synchronous])?.id == "sync")
        #expect(ChatReplyArea<EmptyView>.pendingQuestionItem(in: [asynchronous])?.id == "async")
    }
}
