import Foundation
import Testing
@testable import AgentDomain

@Suite("SessionAttentionPolicy whitebox (task-2)")
struct SessionAttentionPolicyWhiteboxTests {
    @Test func awaitingStatesDoNotRequireUnseenFlag() {
        #expect(SessionAttentionPolicy.requiresAttention(
            status: .awaitingUserQuestion,
            hasUnseenCompletion: false
        ))
        #expect(SessionAttentionPolicy.requiresAttention(
            status: .awaitingApproval(prompt: "ok?"),
            hasUnseenCompletion: false
        ))
    }

    @Test func unseenFlagOverridesIdleStatus() {
        #expect(SessionAttentionPolicy.requiresAttention(status: .idle, hasUnseenCompletion: true))
        #expect(!SessionAttentionPolicy.requiresAttention(status: .idle, hasUnseenCompletion: false))
    }

    @Test func completedAndErrorFollowUnseenFlagOnly() {
        #expect(!SessionAttentionPolicy.requiresAttention(
            status: .completed(exitCode: 1),
            hasUnseenCompletion: false
        ))
        #expect(SessionAttentionPolicy.requiresAttention(
            status: .completed(exitCode: 1),
            hasUnseenCompletion: true
        ))
    }
}
