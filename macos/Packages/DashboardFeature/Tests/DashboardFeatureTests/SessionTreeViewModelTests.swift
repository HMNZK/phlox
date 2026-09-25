import Foundation
import Testing
import UniformTypeIdentifiers
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

// 見本（PhloxSidebar）: オーケストレーションの内部セッションは親の子の末尾に「内部セッション n」の 1 行でまとめる。
@Suite struct SidebarTreeLineTests {
    private func describe(_ lines: [SidebarTreeLine]) -> [String] {
        lines.map { line in
            switch line {
            case .session(let row, let offset): "\(row.name)@\(row.depth + offset)"
            case .internalSessions(_, let depth, let count, let isExpanded): "internal(\(count))@\(depth)\(isExpanded ? "+" : "")"
            }
        }
    }

    @Test func internalSessionsAreFoldedIntoOneRowAtTheEndOfTheParent() {
        let parent = input(1, name: "pm")
        let worker1 = input(2, parent: parent.id, launchContext: .orchestration, name: "w1")
        let normal = input(3, parent: parent.id, name: "child")
        let worker2 = input(4, parent: parent.id, launchContext: .orchestration, name: "w2")
        let forest = SessionTree.buildForest(from: [parent, worker1, normal, worker2])

        let lines = SidebarTreeLine.make(forest, isExpanded: { $0 == parent.id }, expandedParents: [])

        #expect(describe(lines) == ["pm@0", "child@1", "internal(2)@1"])
    }

    @Test func openingTheFoldShowsTheInternalSessionsOneLevelDeeper() {
        let parent = input(1, name: "pm")
        let worker = input(2, parent: parent.id, launchContext: .orchestration, name: "w")
        let grandchild = input(3, parent: worker.id, launchContext: .orchestration, name: "g")
        let forest = SessionTree.buildForest(from: [parent, worker, grandchild])
        let expanded: Set<SessionID> = [parent.id, worker.id]

        let lines = SidebarTreeLine.make(forest, isExpanded: { expanded.contains($0) }, expandedParents: expanded)

        #expect(describe(lines) == ["pm@0", "internal(1)@1+", "w@2", "internal(1)@3+", "g@4"])
    }

    @Test func collapsedParentShowsNoFold() {
        let parent = input(1, name: "pm")
        let worker = input(2, parent: parent.id, launchContext: .orchestration, name: "w")
        let forest = SessionTree.buildForest(from: [parent, worker])

        #expect(describe(SidebarTreeLine.make(forest, isExpanded: { _ in false }, expandedParents: [parent.id])) == ["pm@0"])
    }
}

@Suite struct SidebarReorderTests {
    private let a = fixedSessionID(1), b = fixedSessionID(2), c = fixedSessionID(3), d = fixedSessionID(4)

    /// 入れ替えを順に当てた結果の並び（`reorderSession` と同じ swap）。
    private func apply(_ partners: [SessionID], moving: SessionID, to order: [SessionID]) -> [SessionID] {
        var order = order
        for partner in partners {
            order.swapAt(order.firstIndex(of: moving)!, order.firstIndex(of: partner)!)
        }
        return order
    }

    @Test func movesDownAndUpWithinTheSiblings() {
        let siblings = [a, b, c, d]
        #expect(apply(SidebarReorder.swapPartners(moving: a, to: 3, in: siblings), moving: a, to: siblings) == [b, c, a, d])
        #expect(apply(SidebarReorder.swapPartners(moving: a, to: 4, in: siblings), moving: a, to: siblings) == [b, c, d, a])
        #expect(apply(SidebarReorder.swapPartners(moving: d, to: 1, in: siblings), moving: d, to: siblings) == [a, d, b, c])
        #expect(apply(SidebarReorder.swapPartners(moving: c, to: 1, in: siblings), moving: c, to: siblings) == [a, c, b, d])
    }

    @Test func noOpForItsOwnPlaceOrAStranger() {
        let siblings = [a, b, c]
        #expect(SidebarReorder.swapPartners(moving: b, to: 1, in: siblings).isEmpty)
        #expect(SidebarReorder.swapPartners(moving: b, to: 2, in: siblings).isEmpty)
        #expect(SidebarReorder.swapPartners(moving: d, to: 0, in: siblings).isEmpty)
        #expect(SidebarReorder.swapPartners(moving: a, to: 9, in: siblings).isEmpty)
    }

    /// 運ぶ中身はアプリの中だけの型で、文字としては読めない（外から持ち込んだ文字を並べ替えとして受け付けない）。
    @Test func payloadIsAPrivateTypeThatIsNotText() {
        let provider = SidebarReorderPayload.provider(for: a)
        #expect(provider.registeredTypeIdentifiers == [SidebarReorderPayload.type.identifier])
        #expect(!SidebarReorderPayload.type.conforms(to: .text))
        #expect(!provider.hasItemConformingToTypeIdentifier(UTType.text.identifier))
    }

    /// 兄弟でない行（別の親の子）の位置は変わらない。
    @Test func otherSessionsKeepTheirPlacesInTheWholeOrder() {
        let other = fixedSessionID(9)
        let whole = [a, other, b, c]
        let partners = SidebarReorder.swapPartners(moving: a, to: 3, in: [a, b, c])
        #expect(apply(partners, moving: a, to: whole) == [b, other, c, a])
    }
}
