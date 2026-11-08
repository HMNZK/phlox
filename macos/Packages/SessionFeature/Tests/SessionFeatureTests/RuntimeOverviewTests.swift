import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite @MainActor struct RuntimeOverviewTests {
    @Test func largeTranscriptDoesNotEnterOverviewButPendingQuestionRemains() throws {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.status = .running
        snapshot.transcriptRevision = 17
        let request = try #require(CodexAsyncQuestionID(threadID: "thread", turnID: "turn", itemID: "pending-question"))
        snapshot.transcript = [
            .agentMessage(id: "large-answer", text: String(repeating: "x", count: 65 * 1024 * 1024), timestamp: .distantPast),
            .userQuestion(id: "pending-question", requestId: request.requestID,
                questions: [ChatUserQuestion(question: "続けますか", header: "確認", options: [], multiSelect: false)],
                answers: nil, state: .pending, timestamp: Date(timeIntervalSince1970: 1234)),
        ]
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }

        let overview = session.makeRuntimeOverview()
        let bytes = try JSONEncoder().encode(overview)

        guard case .chat(let chat) = overview.kind else {
            Issue.record("Chat overview was not returned")
            return
        }
        #expect(bytes.count < 16 * 1024)
        #expect(chat.transcriptRevision == 17)
        #expect(chat.transcriptItemCount == 2)
        #expect(chat.pendingInteractions.count == 1)
        #expect(overview.status == .running)
        #expect(overview.displayStatus == .awaitingUserQuestion)
        #expect(overview.displayStatusEnteredAt == Date(timeIntervalSince1970: 1234))
        guard case .question(let index, let prompt, _, _) = chat.pendingInteractions[0] else {
            Issue.record("Pending question was lost")
            return
        }
        #expect(index == 1)
        #expect(prompt.text == "続けますか")
    }

    @Test func longApprovalIsMarkedAsRequiringDetail() throws {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        let approvalID = UUID(uuidString: "3A8F3549-D14C-4DE1-9A48-ACB97AA73903")!
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "item",
            prompt: String(repeating: "allow ", count: 200_000))]
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }

        let overview = session.makeRuntimeOverview()
        let bytes = try JSONEncoder().encode(overview)

        guard case .chat(let chat) = overview.kind,
              case .approval(let id, let prompt, let requiresDetail, _)? = chat.pendingInteractions.first else {
            Issue.record("Pending approval was lost")
            return
        }
        #expect(bytes.count < 16 * 1024)
        #expect(id == approvalID)
        #expect(prompt.truncated)
        #expect(requiresDetail)
    }
}
