import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

private func fixedSessionID(_ value: UInt8) -> SessionID {
    SessionID(rawValue: UUID(uuid: (
        value, 0, 0, 0,
        0, 0,
        0, 0,
        0, 0,
        0, 0, 0, 0, 0, 0
    )))
}

private func fixedProjectID(_ value: UInt8 = 1) -> ProjectID {
    ProjectID(rawValue: UUID(uuid: (
        value, 0, 0, 0,
        0, 0,
        0, 0,
        0, 0,
        0, 0, 0, 0, 0, 1
    )))
}

private func input(
    _ value: UInt8,
    parent: SessionID? = nil,
    launchContext: SessionLaunchContext = .interactive,
    status: SessionStatus = .idle,
    name: String? = nil,
    agentRef: AgentRef = .builtin(.codex)
) -> SessionTreeInput {
    SessionTreeInput(
        id: fixedSessionID(value),
        parentSessionID: parent,
        projectID: fixedProjectID(),
        launchContext: launchContext,
        status: status,
        name: name ?? "session-\(value)",
        agentRef: agentRef
    )
}

@Suite struct SessionTreeTests {
    @Test func parentWithManyChildrenNestsChildrenUnderParentInInputOrder() {
        let parent = input(1, name: "parent")
        let firstChild = input(2, parent: parent.id, launchContext: .orchestration)
        let secondChild = input(3, parent: parent.id, launchContext: .orchestration)

        let forest = SessionTree.buildForest(from: [parent, firstChild, secondChild])

        #expect(forest.map(\.id) == [parent.id])
        #expect(forest[0].depth == 0)
        #expect(forest[0].children.map(\.id) == [firstChild.id, secondChild.id])
        #expect(forest[0].children.map(\.depth) == [1, 1])
        #expect(forest[0].children.map(\.launchContext) == [.orchestration, .orchestration])
    }

    @Test func multilevelTreeAssignsRecursiveDepths() {
        let root = input(1)
        let child = input(2, parent: root.id, launchContext: .orchestration)
        let grandchild = input(3, parent: child.id, launchContext: .orchestration)

        let forest = SessionTree.buildForest(from: [root, child, grandchild])

        let rootNode = forest[0]
        let childNode = rootNode.children[0]
        let grandchildNode = childNode.children[0]
        #expect(rootNode.id == root.id)
        #expect(rootNode.depth == 0)
        #expect(childNode.id == child.id)
        #expect(childNode.depth == 1)
        #expect(grandchildNode.id == grandchild.id)
        #expect(grandchildNode.depth == 2)
        #expect(grandchildNode.children.isEmpty)
    }

    @Test func orphanWithMissingParentIsPromotedToRoot() {
        let missingParent = fixedSessionID(99)
        let orphan = input(1, parent: missingParent)
        let root = input(2)

        let forest = SessionTree.buildForest(from: [orphan, root])

        #expect(forest.map(\.id) == [orphan.id, root.id])
        #expect(forest.map(\.depth) == [0, 0])
        #expect(forest.allSatisfy { $0.children.isEmpty })
    }

    @Test func flatSessionsAllBecomeRoots() {
        let first = input(1)
        let second = input(2)
        let third = input(3)

        let forest = SessionTree.buildForest(from: [first, second, third])

        #expect(forest.map(\.id) == [first.id, second.id, third.id])
        #expect(forest.map(\.depth) == [0, 0, 0])
        #expect(forest.allSatisfy { $0.children.isEmpty })
    }

    @Test func sameInputProducesSameOutputOrderAndShape() {
        let root = input(1)
        let firstChild = input(2, parent: root.id, name: "first")
        let orphan = input(4, parent: fixedSessionID(44), status: .running)
        let secondChild = input(3, parent: root.id, name: "second")
        let sessions = [root, firstChild, orphan, secondChild]

        let firstForest = SessionTree.buildForest(from: sessions)
        let secondForest = SessionTree.buildForest(from: sessions)

        #expect(firstForest == secondForest)
        #expect(firstForest.map(\.id) == [root.id, orphan.id])
        #expect(firstForest[0].children.map(\.id) == [firstChild.id, secondChild.id])
    }

    @Test(.timeLimit(.minutes(1))) func cycleDoesNotHangAndDoesNotDuplicateNodes() {
        let aID = fixedSessionID(1)
        let bID = fixedSessionID(2)
        let a = input(1, parent: bID)
        let b = input(2, parent: aID)

        let forest = SessionTree.buildForest(from: [a, b])
        let flattened = flatten(forest)

        #expect(flattened.map(\.id) == [a.id, b.id])
        #expect(Set(flattened.map(\.id)).count == 2)
        #expect(flattened.count == 2)
        #expect(forest.first?.depth == 0)
        #expect(forest.first?.children.first?.depth == 1)
    }

    @Test(.timeLimit(.minutes(1))) func selfReferencingParentEmitsSingleRootWithoutChildren() {
        let aID = fixedSessionID(1)
        let selfRef = input(1, parent: aID)

        let forest = SessionTree.buildForest(from: [selfRef])
        let flattened = flatten(forest)

        #expect(forest.map(\.id) == [aID])
        #expect(forest[0].depth == 0)
        #expect(forest[0].children.isEmpty)
        #expect(flattened.count == 1)
    }

    private func flatten(_ nodes: [SessionTreeNode]) -> [SessionTreeNode] {
        nodes.flatMap { [$0] + flatten($0.children) }
    }
}
