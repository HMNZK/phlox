import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

private func agoraMessage(_ id: String, at timestamp: TimeInterval?) -> TeamTimelineSourceMessage {
    TeamTimelineSourceMessage(
        id: id,
        timestamp: timestamp.map { Date(timeIntervalSince1970: $0) },
        content: .terminalText(id)
    )
}

private func agoraSource(
    _ id: SessionID,
    parent: SessionID?,
    name: String,
    messages: [TeamTimelineSourceMessage]
) -> AgentTimelineSource {
    AgentTimelineSource(
        id: id,
        parentSessionID: parent,
        displayName: name,
        agentDescriptor: AgentRegistry.descriptor(for: .codex),
        messages: messages
    )
}

@Suite("AgoraTimelineBuilder whitebox")
struct AgoraTimelineBuilderTests {
    @Test func filtersToParticipantsThenDelegatesOrderingToTeamTimelineModelMerge() {
        let root = SessionID()
        let child = SessionID()
        let grandchild = SessionID()

        let items = AgoraTimelineBuilder.build(
            sources: [
                agoraSource(root, parent: nil, name: "root", messages: [
                    agoraMessage("root-nil", at: nil),
                ]),
                agoraSource(child, parent: root, name: "child", messages: [
                    agoraMessage("child-timed", at: 10),
                    agoraMessage("child-nil", at: nil),
                ]),
                agoraSource(grandchild, parent: child, name: "grandchild", messages: [
                    agoraMessage("grandchild-excluded", at: 1),
                ]),
            ],
            participants: [root, child]
        )

        #expect(items.map(\.sourceMessageID) == ["child-timed", "root-nil", "child-nil"])
        #expect(!items.contains { $0.sessionID == grandchild })
    }
}
