import AgentDomain
import Foundation
import SessionFeature
import Testing
@testable import DashboardFeature

@Suite @MainActor struct DashboardOverviewProjectionTests {
    @Test func overviewRefreshKeepsSessionAndUnsentDraft() throws {
        let sessionID = SessionID()
        var first = SessionRuntimeChatSnapshot(id: sessionID, startedAt: Date(timeIntervalSince1970: 1_000),
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        first.titleState = .legacy(name: "最初の名前")
        let firstOverview = ChatSessionViewModel(projection: first) { _, _ in .none }.makeRuntimeOverview()
        let dashboard = try DashboardViewModel(overview: DashboardRuntimeOverview(
            projects: [], sessions: [firstOverview], availableAgentKinds: [.codex])) { _ in .none }
        let original = try #require(dashboard.sessionNode(id: sessionID)?.appServer)
        original.draft = "まだ送っていない本文"
        first.titleState = .legacy(name: "更新した名前")
        let nextOverview = ChatSessionViewModel(projection: first) { _, _ in .none }.makeRuntimeOverview()

        try dashboard.applyRuntimeOverview(DashboardRuntimeOverview(
            projects: [], sessions: [nextOverview], availableAgentKinds: [.codex]))

        let attached = try #require(dashboard.sessionNode(id: sessionID)?.appServer)
        #expect(attached === original)
        #expect(attached.draft == "まだ送っていない本文")
        #expect(attached.titleState == .legacy(name: "更新した名前"))
    }

    @Test func duplicateOverviewIsRejectedWithoutChangingProjects() throws {
        let project = Project(name: "開発", directoryPath: "/workspace", createdAt: Date(timeIntervalSince1970: 1_000), isManagedDirectory: false)
        let dashboard = try DashboardViewModel(overview: DashboardRuntimeOverview(
            projects: [project], sessions: [], availableAgentKinds: [.codex])) { _ in .none }

        #expect(throws: DashboardRuntimeError.self) {
            try dashboard.applyRuntimeOverview(DashboardRuntimeOverview(
                projects: [project, project], sessions: [], availableAgentKinds: [.codex]))
        }

        #expect(dashboard.projects == [project])
    }

    @Test func overviewKeepsWorktreePathsNeededForHistory() throws {
        let project = Project(name: "開発", directoryPath: "/workspace", createdAt: Date(timeIntervalSince1970: 1_000),
            isManagedDirectory: false, worktreePaths: ["/workspace/.worktrees/previous"])
        let dashboard = try DashboardViewModel(projection: DashboardRuntimeSnapshot(
            projects: [project], sessions: [], availableAgentKinds: [.codex])) { _ in .none }

        let overview = dashboard.makeRuntimeOverview()

        #expect(overview.projects.first?.worktreePaths == ["/workspace/.worktrees/previous"])
    }

    @Test func viewedSessionsBecomeContentTargets() throws {
        let first = SessionID()
        let second = SessionID()
        let dashboard = try DashboardViewModel(overview: DashboardRuntimeOverview(
            projects: [], sessions: [], availableAgentKinds: [.codex])) { _ in .none }

        dashboard.noteSessionsViewed([first, second])

        #expect(dashboard.viewedRuntimeSessionIDs == Set([first, second]))
    }

    @Test func closingOneWindowKeepsTheOtherWindowsContentTarget() throws {
        let first = SessionID()
        let second = SessionID()
        let firstWindow = UUID(uuidString: "5B85F927-0D47-43E9-8F43-AEFC44D953C5")!
        let secondWindow = UUID(uuidString: "83C23F22-20D4-4B90-BD14-0B933404D612")!
        let dashboard = try DashboardViewModel(overview: DashboardRuntimeOverview(
            projects: [], sessions: [], availableAgentKinds: [.codex])) { _ in .none }

        dashboard.noteSessionsViewed([first], observerID: firstWindow)
        dashboard.noteSessionsViewed([second], observerID: secondWindow)
        let both = dashboard.viewedRuntimeSessionIDs
        dashboard.noteSessionsViewed([], observerID: firstWindow)

        #expect(both == Set([first, second]))
        #expect(dashboard.viewedRuntimeSessionIDs == Set([second]))
    }

    @Test func removedSessionDoesNotReturnFromAnotherWindowReport() throws {
        let first = SessionID()
        let second = SessionID()
        let firstSession = ChatSessionViewModel(projection: SessionRuntimeChatSnapshot(id: first,
            startedAt: .distantPast, agentRef: .builtin(.codex), workingDirectory: "/workspace")) { _, _ in .none }
        let secondSession = ChatSessionViewModel(projection: SessionRuntimeChatSnapshot(id: second,
            startedAt: .distantPast, agentRef: .builtin(.codex), workingDirectory: "/workspace")) { _, _ in .none }
        let dashboard = try DashboardViewModel(overview: DashboardRuntimeOverview(
            projects: [], sessions: [firstSession.makeRuntimeOverview(), secondSession.makeRuntimeOverview()],
            availableAgentKinds: [.codex])) { _ in .none }
        let firstWindow = UUID()
        let secondWindow = UUID()
        dashboard.noteSessionsViewed([first], observerID: firstWindow)
        dashboard.noteSessionsViewed([second], observerID: secondWindow)

        try dashboard.applyRuntimeOverview(DashboardRuntimeOverview(
            projects: [], sessions: [secondSession.makeRuntimeOverview()], availableAgentKinds: [.codex]))
        dashboard.noteSessionsViewed([second], observerID: secondWindow)

        #expect(dashboard.viewedRuntimeSessionIDs == Set([second]))
    }

    @Test func restoredSelectionIsLoadedWithoutWaitingForAViewReport() throws {
        let sessionID = SessionID()
        let project = Project(name: "開発", directoryPath: "/workspace", createdAt: Date(timeIntervalSince1970: 900), isManagedDirectory: false)
        var snapshot = SessionRuntimeChatSnapshot(id: sessionID, startedAt: Date(timeIntervalSince1970: 1_000),
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.projectID = project.id
        let session = ChatSessionViewModel(projection: snapshot) { _, _ in .none }.makeRuntimeOverview()
        let dashboard = try DashboardViewModel(overview: DashboardRuntimeOverview(
            projects: [project], sessions: [session], availableAgentKinds: [.codex],
            restoredSessionPresentation: .init(selectedSessionID: sessionID, expandedProjectIDs: [project.id]))) { _ in .none }

        #expect(dashboard.restoredSessionPresentation?.selectedSessionID == sessionID)
        #expect(dashboard.viewedRuntimeSessionIDs.contains(sessionID))
    }
}
