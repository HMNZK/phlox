import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

private func agoraLayoutMessage(_ id: String, at timestamp: TimeInterval) -> TeamTimelineSourceMessage {
    TeamTimelineSourceMessage(
        id: id,
        timestamp: Date(timeIntervalSince1970: timestamp),
        content: .terminalText(id)
    )
}

@MainActor
@Suite("TeamTimelineView flat agora path whitebox")
struct TeamTimelineViewLayoutTests {
    @Test func timelineSignatureChangesWhenSelectedProjectChangesAndKeepsNilCompatibility() {
        let selectedSessionID = SessionID()
        let projectA = ProjectID()
        let projectB = ProjectID()
        let sessions = [
            TeamTimelineSignatureSession(
                id: selectedSessionID,
                parentSessionID: nil,
                projectID: projectA,
                launchContext: .interactive,
                status: .running,
                name: "Root",
                displayName: "Root",
                agentDescriptor: AgentRegistry.descriptor(for: .codex),
                content: .pty(lastOutputAt: nil)
            ),
        ]

        let signatureA = TeamTimelineSignature.make(
            selectedSessionID: selectedSessionID,
            selectedProjectID: projectA,
            sessions: sessions
        )
        let signatureB = TeamTimelineSignature.make(
            selectedSessionID: selectedSessionID,
            selectedProjectID: projectB,
            sessions: sessions
        )
        let legacyNilA = TeamTimelineSignature.make(
            selectedSessionID: selectedSessionID,
            sessions: sessions
        )
        let legacyNilB = TeamTimelineSignature.make(
            selectedSessionID: selectedSessionID,
            selectedProjectID: nil,
            sessions: sessions
        )

        #expect(signatureA != signatureB)
        #expect(legacyNilA == legacyNilB)
    }

    @Test func flatTimelineRefreshKeepsSignatureGateAndDoesNotCallMakeSourcesWhenUnchanged() {
        let store = TeamTimelineStore()
        let root = SessionID()
        var buildCount = 0

        let rebuilt = store.refreshAgoraTimelineIfNeeded(
            signature: TeamTimelineSignature(["same"]),
            messageLimitPerSession: 200
        ) {
            buildCount += 1
            return [
                AgentTimelineSource(
                    id: root,
                    parentSessionID: nil,
                    displayName: "Root",
                    agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
                    messages: [agoraLayoutMessage("first", at: 10)]
                ),
            ]
        }

        let skipped = store.refreshAgoraTimelineIfNeeded(
            signature: TeamTimelineSignature(["same"]),
            messageLimitPerSession: 200
        ) {
            buildCount += 1
            return [
                AgentTimelineSource(
                    id: root,
                    parentSessionID: nil,
                    displayName: "Root",
                    agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
                    messages: [agoraLayoutMessage("must-not-build", at: 20)]
                ),
            ]
        }

        #expect(rebuilt)
        #expect(skipped == false)
        #expect(buildCount == 1)
        #expect(store.items.map(\.sourceMessageID) == ["first"])
    }

    @Test func flatTimelineRefreshPublishesOnlyRootAndDirectChildrenWithPerSessionMessageLimit() {
        let store = TeamTimelineStore()
        let root = SessionID()
        let child = SessionID()
        let grandchild = SessionID()

        _ = store.refreshAgoraTimelineIfNeeded(
            signature: TeamTimelineSignature(["rev-1"]),
            messageLimitPerSession: 2
        ) {
            [
                AgentTimelineSource(
                    id: root,
                    parentSessionID: nil,
                    displayName: "Root",
                    agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
                    messages: [
                        agoraLayoutMessage("root-old", at: 1),
                        agoraLayoutMessage("root-newer", at: 30),
                        agoraLayoutMessage("root-newest", at: 40),
                    ]
                ),
                AgentTimelineSource(
                    id: child,
                    parentSessionID: root,
                    displayName: "Child",
                    agentDescriptor: AgentRegistry.descriptor(for: .codex),
                    messages: [agoraLayoutMessage("child", at: 20)]
                ),
                AgentTimelineSource(
                    id: grandchild,
                    parentSessionID: child,
                    displayName: "Grandchild",
                    agentDescriptor: AgentRegistry.descriptor(for: .cursor),
                    messages: [agoraLayoutMessage("grandchild", at: 10)]
                ),
            ]
        }

        #expect(store.sources.map(\.id) == [root, child])
        #expect(store.items.map(\.sourceMessageID) == ["child", "root-newer", "root-newest"])
    }
}
