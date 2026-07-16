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

@Suite struct SessionTreeViewModelTests {
    @Test func rowsAreCollapsedByDefaultAndHideChildren() {
        let parent = input(1, name: "orchestrator", agentRef: .builtin(.claudeCode))
        let child = input(
            2,
            parent: parent.id,
            launchContext: .orchestration,
            status: .running,
            name: "worker",
            agentRef: .builtin(.codex)
        )
        let sibling = input(3, name: "standalone", agentRef: .builtin(.cursor))
        let forest = SessionTree.buildForest(from: [parent, child, sibling])
        let viewModel = SessionTreeViewModel()

        let rows = viewModel.rows(from: forest)

        #expect(rows.map(\.id) == [parent.id, sibling.id])
        #expect(rows.map(\.depth) == [0, 0])
        #expect(rows[0].hasChildren)
        #expect(rows[0].isExpanded == false)
        #expect(rows[0].name == "orchestrator")
        #expect(rows[0].agentKind == .claudeCode)
        #expect(rows[1].hasChildren == false)
    }

    @Test func togglingParentExpandsAndCollapsesDescendantRows() {
        let parent = input(1, name: "orchestrator", agentRef: .builtin(.claudeCode))
        let child = input(
            2,
            parent: parent.id,
            launchContext: .orchestration,
            status: .running,
            name: "worker",
            agentRef: .builtin(.codex)
        )
        let grandchild = input(
            3,
            parent: child.id,
            launchContext: .orchestration,
            status: .awaitingApproval(prompt: "continue?"),
            name: "reviewer",
            agentRef: .builtin(.cursor)
        )
        let forest = SessionTree.buildForest(from: [parent, child, grandchild])
        let viewModel = SessionTreeViewModel()

        viewModel.toggleExpansion(for: parent.id, in: forest)
        var rows = viewModel.rows(from: forest)

        #expect(rows.map(\.id) == [parent.id, child.id])
        #expect(rows.map(\.depth) == [0, 1])
        #expect(rows[0].isExpanded)
        #expect(rows[1].hasChildren)
        #expect(rows[1].isExpanded == false)
        #expect(rows[1].status == .running)
        #expect(rows[1].launchContext == .orchestration)
        #expect(rows[1].agentKind == .codex)

        viewModel.toggleExpansion(for: child.id, in: forest)
        rows = viewModel.rows(from: forest)
        #expect(rows.map(\.id) == [parent.id, child.id, grandchild.id])
        #expect(rows.map(\.depth) == [0, 1, 2])
        #expect(rows[2].status == .awaitingApproval(prompt: "continue?"))
        #expect(rows[2].agentKind == .cursor)

        viewModel.toggleExpansion(for: parent.id, in: forest)
        rows = viewModel.rows(from: forest)
        #expect(rows.map(\.id) == [parent.id])
        #expect(rows[0].isExpanded == false)
    }

    @Test func displayNameFallsBackToShortIDWhenNameIsBlank() {
        let blank = input(1, name: "   ")
        let forest = SessionTree.buildForest(from: [blank])
        let viewModel = SessionTreeViewModel()

        let rows = viewModel.rows(from: forest)

        #expect(rows[0].displayName == "#010000")
    }

    @Test func togglingLeafDoesNotRecordExpansionState() {
        let parent = input(1)
        let leaf = input(2, parent: parent.id, launchContext: .orchestration)
        let forest = SessionTree.buildForest(from: [parent, leaf])
        let viewModel = SessionTreeViewModel()

        viewModel.toggleExpansion(for: leaf.id, in: forest)

        #expect(viewModel.expandedSessionIDs.isEmpty)
        #expect(viewModel.rows(from: forest).map(\.id) == [parent.id])
    }
}
