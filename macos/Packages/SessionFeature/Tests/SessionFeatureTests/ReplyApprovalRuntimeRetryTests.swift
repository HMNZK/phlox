import AgentDomain
import Foundation
import Testing
@testable import SessionFeature

private enum ApprovalTransportTestError: Error { case unavailable }

@MainActor
struct ReplyApprovalRuntimeRetryTests {
    @Test func failedTransportKeepsTheSameApprovalArmedUntilAnExplicitRetrySucceeds() async throws {
        let requestID = UUID()
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: nil)
        snapshot.status = .awaitingApproval(prompt: "allow command?")
        snapshot.pendingApprovals = [ChatApprovalRequest(id: requestID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "item", prompt: "allow command?")]
        snapshot.draftRecoveryID = UUID()
        let recovered = AsyncStream<Void>.makeStream()
        var receivedRequests: [UUID] = []
        var fetches = 0
        var acknowledgements = 0
        let viewModel = ChatSessionViewModel(projection: snapshot) { _, command in
            switch command {
            case .approval(let id, _):
                receivedRequests.append(id)
                if receivedRequests.count == 1 { throw ApprovalTransportTestError.unavailable }
                return .none
            case .recoverLaunchDraft:
                fetches += 1
                return .draft(text: "failed draft", attachments: [])
            case .acknowledgeRecoveredDraft:
                acknowledgements += 1
                recovered.continuation.yield(())
                return .none
            default: throw SessionRuntimeProjectionError.unsupportedCommand
            }
        }
        var recoveredIterator = recovered.stream.makeAsyncIterator()
        _ = await recoveredIterator.next()
        viewModel.draft = "local editing remains"
        let approval = try #require(viewModel.currentReplyApproval)
        viewModel.markApprovalPresented(approval.id, at: .distantPast)

        let first = await viewModel.respond(to: approval, decision: .accept)
        #expect(!first)
        #expect(viewModel.isApprovalArmed(approval.id))
        #expect(receivedRequests == [requestID])
        #expect(viewModel.draft == "local editing remains")

        try viewModel.applyRuntimeSnapshot(snapshot)
        let second = await viewModel.respond(to: approval, decision: .accept)
        #expect(second)
        #expect(receivedRequests == [requestID, requestID])
        #expect(!viewModel.isApprovalArmed(approval.id))
        #expect(viewModel.draft == "local editing remains")
        #expect(fetches == 1)
        #expect(acknowledgements == 1)

        let duplicate = await viewModel.respond(to: approval, decision: .accept)
        #expect(!duplicate)
        #expect(receivedRequests.count == 2)
    }
}
