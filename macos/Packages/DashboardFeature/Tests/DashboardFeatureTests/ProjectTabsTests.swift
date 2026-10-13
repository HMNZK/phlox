import Foundation
import AppKit
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite struct ProjectTabLayoutTests {
    @Test func openSelectCloseAndUniqueItems() {
        let chat = ProjectTab.chat(SessionID())
        var layout = ProjectTabLayout()
        layout.open(chat)
        layout.open(.newChat)
        layout.open(.newChat)
        layout.open(.changes)
        #expect(layout.items == [.newChat, .changes])
        layout.select(chat)
        #expect(layout.selected == chat)
        let chatClosed = layout.close(chat)
        #expect(!chatClosed)
        layout.select(.changes)
        let changesClosed = layout.close(.changes, chats: [chat])
        #expect(changesClosed)
        #expect(layout.selected == .newChat)
        let newChatClosed = layout.close(.newChat, chats: [chat])
        #expect(newChatClosed)
        #expect(layout.selected == chat)
        #expect(layout.items.isEmpty)
    }

    @Test func cycleUsesChatsThenItems() {
        let chats = [ProjectTab.chat(SessionID()), .chat(SessionID())]
        var layout = ProjectTabLayout()
        layout.open(.changes)
        layout.cycle(by: 1, chats: chats)
        #expect(layout.selected == chats[0])
        layout.cycle(by: -1, chats: chats)
        #expect(layout.selected == .changes)
        layout.cycle(by: 5, chats: chats)
        #expect(layout.selected == chats[1])
    }

    @Test func splitSelectionAndClosing() {
        let chat = ProjectTab.chat(SessionID())
        var layout = ProjectTabLayout()
        layout.open(chat)
        layout.open(.changes)
        layout.toggleSplit(chats: [chat])
        #expect(layout.left == chat)
        #expect(layout.right == .changes)
        #expect(layout.focusesRight)
        layout.select(chat)
        #expect(!layout.focusesRight)
        layout.select(.changes)
        layout.toggleSplit(chats: [chat])
        #expect(layout.left == .changes)
        #expect(layout.right == nil)
        layout.splitRight(chat, chats: [chat])
        let changesClosed = layout.close(.changes, chats: [chat])
        #expect(changesClosed)
        #expect(layout.left == chat)
        #expect(layout.right == nil)
        #expect(!layout.focusesRight)
    }

    @Test func emptyAndSingleItemCannotSplit() {
        var layout = ProjectTabLayout()
        layout.toggleSplit()
        #expect(layout.left == nil)
        layout.open(.newChat)
        layout.toggleSplit()
        #expect(layout.right == nil)
        let closed = layout.close(.newChat)
        #expect(closed)
        #expect(layout.selected == nil)
    }

    @Test func closingRightAndHiddenItemPreservesLeft() {
        let chat = ProjectTab.chat(SessionID())
        var layout = ProjectTabLayout()
        layout.open(chat)
        layout.open(.changes)
        layout.open(.file("a.txt"))
        layout.select(chat)
        layout.splitRight(.changes, chats: [chat])
        let closedHidden = layout.close(.file("a.txt"), chats: [chat])
        #expect(closedHidden)
        #expect(layout.left == chat && layout.right == .changes)
        let closedRight = layout.close(.changes, chats: [chat])
        #expect(closedRight)
        #expect(layout.left == chat && layout.right == nil)
        #expect(!layout.focusesRight)
        layout.select(.browser)
        #expect(layout.selected == chat)
    }

    @Test func terminalsAreMultipleAndChatIsNeverAnItem() {
        let first = ProjectTab.terminal(TerminalTabID())
        let second = ProjectTab.terminal(TerminalTabID())
        var layout = ProjectTabLayout()
        layout.open(first)
        layout.open(second)
        layout.open(.chat(SessionID()))
        #expect(layout.items == [first, second])
    }

    @Test func deletedChatSelectsNeighborAndKeepsProjectItems() {
        let first = ProjectTab.chat(SessionID()), middle = ProjectTab.chat(SessionID()), last = ProjectTab.chat(SessionID())
        var layout = ProjectTabLayout()
        layout.open(.file("a.txt"))
        layout.open(middle)
        layout.reconcileChats(previous: [first, middle, last], current: [first, last])
        #expect(layout.selected == last)
        #expect(layout.items == [.file("a.txt")])
        layout.reconcileChats(previous: [first, last], current: [first])
        #expect(layout.selected == .file("a.txt"))
        layout.select(first)
        layout.splitRight(.file("a.txt"), chats: [first])
        layout.reconcileChats(previous: [first], current: [])
        #expect(layout.left == .file("a.txt"))
        #expect(layout.right == nil)
        #expect(!layout.focusesRight)
    }

    @Test func showChatKeepsSimulatorVisible() {
        let sessionID = SessionID()
        let chat = ProjectTab.chat(sessionID)
        var layout = ProjectTabLayout()
        layout.open(chat)
        layout.open(.simulator)
        layout.open(.changes)
        layout.splitRight(.simulator, chats: [chat])
        layout.showChat(sessionID, keeping: .simulator)
        #expect(layout.left == chat)
        #expect(layout.right == .simulator)
        #expect(!layout.focusesRight)
    }

    @Test func sidebarPreorderWithinCandidateScope() {
        let project = ProjectID()
        let parent = SessionID(), child = SessionID(), next = SessionID(), hidden = SessionID()
        func input(_ id: SessionID, parent: SessionID? = nil) -> SessionTreeInput {
            SessionTreeInput(id: id, parentSessionID: parent, projectID: project,
                            launchContext: parent == nil ? .interactive : .orchestration,
                            status: .idle, name: "chat", agentRef: .builtin(.codex))
        }
        let forest = SessionTree.buildForest(from: [input(parent), input(next), input(child, parent: parent), input(hidden)])
        #expect(ProjectTab.chats(in: forest, candidates: [next, child, parent]) == [.chat(parent), .chat(child), .chat(next)])
    }
}

@Suite @MainActor struct ProjectTabStoreTests {
    @Test func dashboardNumberedTabsFollowExpandedSidebarThenItems() async throws {
        let project = Project(name: "project", directoryPath: "/tmp", createdAt: Date(), isManagedDirectory: false)
        let projects = InMemoryProjectStore()
        try await projects.save([project])
        let parent = SessionID(), child = SessionID(), sibling = SessionID()
        let sessions = InMemorySessionStore([
            makePersistedSessionDescriptor(id: parent, workingDirectory: "/tmp", projectID: project.id, startedAt: Date(timeIntervalSince1970: 1)),
            makePersistedSessionDescriptor(id: sibling, workingDirectory: "/tmp", projectID: project.id, startedAt: Date(timeIntervalSince1970: 2)),
            makePersistedSessionDescriptor(id: child, workingDirectory: "/tmp", projectID: project.id, startedAt: Date(timeIntervalSince1970: 3), parentSessionID: parent, launchContext: .orchestration)
        ])
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() }, projects: projects, sessions: sessions))
        await dashboard.start()
        let forest = dashboard.sessionForest(in: project.id)
        let sidebar = SessionTreeViewModel()
        sidebar.toggleExpansion(for: parent, in: forest)
        let chats = sidebar.rows(from: forest).map { ProjectTab.chat($0.id) }
        #expect(chats.count == 3)
        #expect(dashboard.chatTabs(in: project.id) == chats)
        let router = AppRouter()
        router.selectedProjectID = project.id
        router.openChildTab(.changes)
        #expect(dashboard.numberedTabs(router: router) == chats + [.changes])
        router.cycleChildTab(by: 1, chats: chats)
        #expect(router.tabs.layout(for: project.id).selected == chats.first)
        await dashboard.removeProject(project.id)
        #expect(dashboard.chatTabs(in: project.id).isEmpty)
        #expect(dashboard.sessionNodes.isEmpty)
    }

    @Test func projectDeletionDropsItemsAndOwnedResourcesOnlyForThatProject() async throws {
        let project = ProjectID(), other = ProjectID()
        let first = TerminalTabID(), second = TerminalTabID(), kept = TerminalTabID()
        let pty = MockPTYManager()
        let terminals = ProjectTerminalStore { path in
            TerminalPanelSession(controller: UserTerminalController(pty: pty, shellPath: "/bin/sh", workingDirectory: path, environment: ["PATH": "/usr/bin:/bin"]))
        }
        let a = terminals.terminal(for: first, projectID: project, workingDirectory: "/project")
        let b = terminals.terminal(for: second, projectID: project, workingDirectory: "/project")
        let c = terminals.terminal(for: kept, projectID: other, workingDirectory: "/other")
        #expect(a !== b)
        await a.ensureStarted()
        await b.ensureStarted()
        await c.ensureStarted()
        let router = AppRouter()
        router.selectedProjectID = other
        router.openChildTab(.browser)
        let keptBrowser = router.browsers[other]
        router.selectedProjectID = project
        router.openChildTab(.browser)
        router.tabs.updateLayout(for: project) { $0.open(.terminal(first)); $0.open(.terminal(second)); $0.open(.file("a.txt")) }
        let hub = SimulatorHub()
        hub.requestMenuFocus(for: project)
        hub.requestMenuFocus(for: other)
        let files = FileTabDocuments()
        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        FileTabDocumentRegistry.shared.register(files: files, window: window)
        defer { window.close() }
        let discarded = files.document(for: project, path: "a.txt", root: "/project")
        let keptDocument = files.document(for: other, path: "a.txt", root: "/other")
        await router.forgetProject(project, terminals: terminals, simulatorHub: hub)
        #expect(router.tabs.snapshot.projects[project] == nil)
        #expect(router.browsers[project] == nil)
        #expect(router.browsers[other] === keptBrowser)
        #expect(terminals.existing(first) == nil)
        #expect(terminals.existing(second) == nil)
        #expect(terminals.existing(kept) === c)
        #expect(!a.controller.isRunning && !b.controller.isRunning)
        #expect(c.controller.isRunning)
        #expect(hub.menuFocusRevision(for: project) == 0)
        #expect(hub.menuFocusRevision(for: other) == 1)
        #expect(files.existing(for: project, path: "a.txt") == nil)
        #expect(discarded.invalidated)
        #expect(files.existing(for: other, path: "a.txt") === keptDocument)
        #expect(!keptDocument.invalidated)
        await terminals.shutdownAll()
        router.closeBrowser(for: other)
    }

    @Test func changingChatDoesNotChangeProjectItemsOrBrowser() {
        let project = ProjectID(), first = SessionID(), second = SessionID()
        let router = AppRouter(selectedSession: first)
        router.selectedProjectID = project
        router.openChildTab(.browser)
        let model = router.browsers[project]
        router.selectTab(.chat(second), in: project)
        #expect(router.tabs.layout(for: project).items == [.browser])
        #expect(router.browsers[project] === model)
        #expect(router.selectedSession == second)
        router.closeBrowser(for: project)
    }

    @Test func selectingChatLeavesTheNewChatDestinationForLater() {
        let project = ProjectID(), session = SessionID()
        let router = AppRouter()
        router.showNewChat(projectID: project)
        router.selectTab(.chat(session), in: project)
        #expect(router.tabs.layout(for: project).items.isEmpty)
        #expect(router.selectedSession == session)
        router.showNewChat(projectID: nil)
        #expect(router.selectedSession == nil)
        #expect(router.newChatProjectID == project)
    }
    @Test func closeTargetRoutesChatItemsAndGrid() {
        let project = ProjectID(), session = SessionID()
        let store = ProjectTabStore()
        store.updateLayout(for: project) { $0.open(.chat(session)) }
        #expect(store.closeTarget(projectID: project, selectedSession: session, viewMode: .single) == .session(session))
        for tab in [ProjectTab.newChat, .terminal(TerminalTabID()), .file("a.txt"), .changes, .browser, .simulator] {
            store.updateLayout(for: project) { $0.open(tab) }
            #expect(store.closeTarget(projectID: project, selectedSession: nil, viewMode: .single) == .tab(tab))
        }
        #expect(store.closeTarget(projectID: project, selectedSession: session, viewMode: .grid) == .gridTile(session))
        #expect(store.closeTarget(projectID: project, selectedSession: nil, viewMode: .grid) == nil)
    }

    @Test func newChatStartsAndBecomesChatWithoutLosingOtherItems() {
        let project = ProjectID(), session = SessionID()
        let router = AppRouter()
        router.selectedProjectID = project
        router.openChildTab(.changes)
        router.showNewChat(projectID: project)
        router.showNewChat(projectID: project)
        #expect(router.tabs.layout(for: project).items == [.changes])
        #expect(router.selectedSession == nil)
        router.completeNewChat(sessionID: session, projectID: project)
        #expect(router.tabs.layout(for: project).items == [.changes])
        #expect(router.tabs.layout(for: project).selected == .chat(session))
        #expect(router.selectedSession == session)
    }
}
