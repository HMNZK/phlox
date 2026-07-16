import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

private func agoraPolicyInput(
    id: SessionID,
    parent: SessionID? = nil,
    projectID: ProjectID
) -> SessionTreeInput {
    SessionTreeInput(
        id: id,
        parentSessionID: parent,
        projectID: projectID,
        launchContext: .interactive,
        status: .idle,
        name: id.rawValue.uuidString,
        agentRef: .builtin(.codex)
    )
}

@Suite("AgoraParticipantsPolicy whitebox")
struct AgoraParticipantsPolicyTests {
    @Test func keepsRootsAndDirectChildrenInOrderedIDsOrderAndExcludesGrandchildren() {
        let rootA = SessionID()
        let childA1 = SessionID()
        let grandchildA = SessionID()
        let rootB = SessionID()
        let childA2 = SessionID()
        let childB = SessionID()

        let result = AgoraParticipantsPolicy.participants(
            orderedIDs: [rootA, childA1, grandchildA, rootB, childA2, childB],
            parentByID: [
                childA1: rootA,
                grandchildA: childA1,
                childA2: rootA,
                childB: rootB,
            ]
        )

        #expect(result == [rootA, childA1, rootB, childA2, childB])
    }

    @Test func excludesSelfCycleAndTwoNodeCycle() {
        let root = SessionID()
        let selfCycle = SessionID()
        let cycleA = SessionID()
        let cycleB = SessionID()

        let result = AgoraParticipantsPolicy.participants(
            orderedIDs: [root, selfCycle, cycleA, cycleB],
            parentByID: [
                selfCycle: selfCycle,
                cycleA: cycleB,
                cycleB: cycleA,
            ]
        )

        #expect(result == [root])
    }

    @Test func orderedProjectSessionIDsKeepsParallelRootsAndChildrenAndExcludesOtherProjects() {
        let projectA = ProjectID()
        let projectB = ProjectID()
        let rootA1 = SessionID()
        let childA1 = SessionID()
        let rootB = SessionID()
        let rootA2 = SessionID()

        let forest = SessionTree.buildForest(from: [
            agoraPolicyInput(id: rootA1, projectID: projectA),
            agoraPolicyInput(id: childA1, parent: rootA1, projectID: projectA),
            agoraPolicyInput(id: rootB, projectID: projectB),
            agoraPolicyInput(id: rootA2, projectID: projectA),
        ])

        let result = AgoraParticipantsPolicy.orderedProjectSessionIDs(
            forest: forest,
            projectID: projectA
        )

        #expect(result == [rootA1, childA1, rootA2])
    }
}
