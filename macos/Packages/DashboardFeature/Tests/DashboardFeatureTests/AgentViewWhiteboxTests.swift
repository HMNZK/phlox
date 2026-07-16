import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

private func agentViewMessage(_ id: String, at t: TimeInterval? = nil) -> TeamTimelineSourceMessage {
    TeamTimelineSourceMessage(
        id: id,
        timestamp: t.map { Date(timeIntervalSince1970: $0) },
        content: .terminalText(id)
    )
}

private func agentViewSource(
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

@Test func whitebox_agentViewCollapsedSubsessionKeepsCardAndHidesDescendantEntries() {
    let root = SessionID()
    let child = SessionID()
    let grandchild = SessionID()

    let entries = AgentChatTimelineBuilder.build(
        sources: [
            agentViewSource(root, parent: nil, name: "main", messages: [
                agentViewMessage("root-1", at: 10),
                agentViewMessage("root-2", at: 40),
            ]),
            agentViewSource(child, parent: root, name: "worker", messages: [
                agentViewMessage("child-1", at: 20),
            ]),
            agentViewSource(grandchild, parent: child, name: "nested", messages: [
                agentViewMessage("grandchild-1", at: 25),
            ]),
        ],
        rootID: root,
        messageLimitPerSession: 0
    )

    let visibleIDs = AgentTimelineCollapsePolicy.visibleEntryIDs(
        entries: entries,
        collapsedSessionIDs: [child]
    )

    #expect(visibleIDs == [
        "\(root.rawValue.uuidString):root-1",
        "subsession-\(child.rawValue.uuidString)",
        "\(root.rawValue.uuidString):root-2",
    ])
}

@Test func whitebox_agentViewMessageBodyTapDoesNotOpenSubsession() {
    #expect(AgentSubsessionTapPolicy.opensSingleView(for: .header) == true)
    #expect(AgentSubsessionTapPolicy.opensSingleView(for: .cardChrome) == true)
    #expect(AgentSubsessionTapPolicy.opensSingleView(for: .messageBody) == false)
}

@Test func whitebox_agentViewComposerCycleResolutionReturnsStableVisitedSession() {
    let a = SessionID()
    let b = SessionID()
    let parentByID: [SessionID: SessionID?] = [a: b, b: a]

    let resolved = TeamComposerTarget.resolveRootSessionID(
        selectedSessionID: a,
        parentByID: parentByID
    )

    #expect(resolved == a || resolved == b)
}

@Test @MainActor
func whitebox_agentViewComposerReadinessUpdatesWithoutTimelineRebuild() {
    let store = TeamTimelineStore()
    let root = SessionID()
    var buildCount = 0
    let signature = TeamTimelineSignature(["stable"])

    let rebuilt = store.refreshAgentTimelineIfNeeded(
        signature: signature,
        rootID: root,
        messageLimitPerSession: 200
    ) {
        buildCount += 1
        return [
            agentViewSource(root, parent: nil, name: "main", messages: [
                agentViewMessage("root-1", at: 10),
            ]),
        ]
    }

    #expect(rebuilt)
    #expect(buildCount == 1)
    #expect(store.isComposerReadyForInput == false)

    let readinessChanged = store.refreshComposerReadiness(true)
    let timelineRebuilt = store.refreshAgentTimelineIfNeeded(
        signature: signature,
        rootID: root,
        messageLimitPerSession: 200
    ) {
        buildCount += 1
        return []
    }

    #expect(readinessChanged)
    #expect(store.isComposerReadyForInput)
    #expect(timelineRebuilt == false)
    #expect(buildCount == 1)
}

@Test @MainActor
func whitebox_agentViewComposerReadinessDoesNotWriteWhenUnchanged() {
    let store = TeamTimelineStore()

    #expect(store.refreshComposerReadiness(false) == false)
    #expect(store.isComposerReadyForInput == false)

    #expect(store.refreshComposerReadiness(true))
    #expect(store.isComposerReadyForInput)

    #expect(store.refreshComposerReadiness(true) == false)
    #expect(store.isComposerReadyForInput)
}

@Test func whitebox_agentViewComposerRestoresDraftAfterSendFailure() {
    #expect(TeamComposerDraftPolicy.draftAfterSendFailure(currentDraft: "", sentText: "retry me") == "retry me")
    #expect(TeamComposerDraftPolicy.draftAfterSendFailure(currentDraft: "new draft", sentText: "retry me") == "new draft")
}
