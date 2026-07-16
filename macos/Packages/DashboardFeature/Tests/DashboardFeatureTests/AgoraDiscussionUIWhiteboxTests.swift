import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite("TeamTimelineAgoraPolicy whitebox (task-5)")
@MainActor
struct TeamTimelineAgoraPolicyWhiteboxTests {
    @Test func 討論中フェーズのみ_discussionActive() {
        #expect(TeamTimelineAgoraPolicy.isDiscussionActive(phase: .discussing))
        #expect(TeamTimelineAgoraPolicy.isDiscussionActive(phase: .concluding))
        #expect(!TeamTimelineAgoraPolicy.isDiscussionActive(phase: .idle))
        #expect(!TeamTimelineAgoraPolicy.isDiscussionActive(phase: .ended(.stopped)))
        #expect(!TeamTimelineAgoraPolicy.isDiscussionActive(phase: nil))
    }

    @Test func プロジェクト解決可能なら討論開始可能() {
        #expect(TeamTimelineAgoraPolicy.canStartDiscussion(canResolveProject: true))
        #expect(!TeamTimelineAgoraPolicy.canStartDiscussion(canResolveProject: false))
    }

    @Test func 非討論中は参加者集合_nil() {
        #expect(TeamTimelineAgoraPolicy.discussionParticipantIDs(coordinator: nil) == nil)
    }

    @Test func 討論中の追加エージェントは_claudeCode_固定() {
        #expect(TeamTimelineAgoraPolicy.addAgentKindDuringDiscussion(isDiscussionActive: true) == .claudeCode)
        #expect(TeamTimelineAgoraPolicy.addAgentKindDuringDiscussion(isDiscussionActive: false) == nil)
    }
}

@Suite("AgoraComposerRouting integration whitebox (task-5)")
struct AgoraComposerRoutingWhiteboxTests {
    @Test func 非討論かつ開始可能なら議題投入() {
        let action = AgoraComposerRouting.action(
            phase: nil,
            canStartDiscussion: true,
            text: "議題A"
        )
        #expect(action == .startDiscussion(agenda: "議題A"))
    }

    @Test func 非討論かつ開始不可なら従来送信() {
        let action = AgoraComposerRouting.action(
            phase: nil,
            canStartDiscussion: false,
            text: "hello"
        )
        #expect(action == .legacyRootSend("hello"))
    }

    @Test func 討論中はユーザー発言() {
        let action = AgoraComposerRouting.action(
            phase: .discussing,
            canStartDiscussion: true,
            text: "意見"
        )
        #expect(action == .discussionUtterance("意見"))
    }

    @Test func concluding_中もユーザー発言() {
        let action = AgoraComposerRouting.action(
            phase: .concluding,
            canStartDiscussion: false,
            text: "補足"
        )
        #expect(action == .discussionUtterance("補足"))
    }
}

@MainActor
@Suite("TeamTimelineStore agora discussion whitebox (task-5-fix1)")
struct TeamTimelineStoreAgoraDiscussionWhiteboxTests {
    private func stubSource(
        id: SessionID,
        parentSessionID: SessionID?,
        displayName: String
    ) -> AgentTimelineSource {
        AgentTimelineSource(
            id: id,
            parentSessionID: parentSessionID,
            displayName: displayName,
            agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
            messages: []
        )
    }

    @Test func 討論中_孫参加者はStore二次フィルタで落ちない() {
        let store = TeamTimelineStore()
        let root = SessionID()
        let child = SessionID()
        let grand = SessionID()
        let discussionParticipants: Set<SessionID> = [root, child, grand]

        _ = store.refreshAgoraTimelineIfNeeded(
            signature: TeamTimelineSignature(["discussion-3-tier"]),
            messageLimitPerSession: 200,
            discussionParticipants: discussionParticipants
        ) {
            [
                stubSource(id: root, parentSessionID: nil, displayName: "r"),
                stubSource(id: child, parentSessionID: root, displayName: "c"),
                stubSource(id: grand, parentSessionID: child, displayName: "g"),
            ]
        }

        #expect(store.sources.map(\.id) == [root, child, grand])
    }
}

@Suite("TeamTimelineSignature agora discussion whitebox (task-5-fix1)")
struct TeamTimelineSignatureAgoraDiscussionWhiteboxTests {
    private func sampleSessions(selectedID: SessionID) -> [TeamTimelineSignatureSession] {
        [
            TeamTimelineSignatureSession(
                id: selectedID,
                parentSessionID: nil,
                projectID: ProjectID(),
                launchContext: .interactive,
                status: .running,
                name: "Root",
                displayName: "Root",
                agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
                content: .pty(lastOutputAt: nil)
            ),
        ]
    }

    @Test func 同一session群で討論参加者集合だけ差し替えるとsignatureが変わる() {
        let selectedID = SessionID()
        let participantA = SessionID()
        let participantB = SessionID()
        let sessions = sampleSessions(selectedID: selectedID)

        let signatureA = TeamTimelineSignature.make(
            selectedSessionID: selectedID,
            sessions: sessions,
            discussionParticipantIDs: [participantA]
        )
        let signatureB = TeamTimelineSignature.make(
            selectedSessionID: selectedID,
            sessions: sessions,
            discussionParticipantIDs: [participantA, participantB]
        )

        #expect(signatureA != signatureB)
    }

    @Test func nil同士と同一集合ではsignatureが変わらない() {
        let selectedID = SessionID()
        let sessions = sampleSessions(selectedID: selectedID)
        let participants: Set<SessionID> = [SessionID(), SessionID()]

        let nilDefault = TeamTimelineSignature.make(
            selectedSessionID: selectedID,
            sessions: sessions
        )
        let nilExplicit = TeamTimelineSignature.make(
            selectedSessionID: selectedID,
            sessions: sessions,
            discussionParticipantIDs: nil
        )
        #expect(nilDefault == nilExplicit)

        let setA = TeamTimelineSignature.make(
            selectedSessionID: selectedID,
            sessions: sessions,
            discussionParticipantIDs: participants
        )
        let setB = TeamTimelineSignature.make(
            selectedSessionID: selectedID,
            sessions: sessions,
            discussionParticipantIDs: participants
        )
        #expect(setA == setB)
    }
}
