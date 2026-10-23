import Foundation
import Testing
import AgentDomain
import SessionFeature
@testable import DashboardFeature

@Suite @MainActor struct DashboardRuntimeProjectionTests {
    @Test func attachingAndStartingProjectionDoesNotExecuteRuntimeCommands() async throws {
        var commands = 0
        let dashboard = try DashboardViewModel(projection: .init(projects: [], sessions: [], availableAgentKinds: [.claudeCode])) { _ in
            commands += 1
            return .none
        }
        await dashboard.start()
        await dashboard.start()
        let project = Project(name: "runtime", directoryPath: "/runtime", createdAt: Date(), isManagedDirectory: false)
        try dashboard.applyRuntimeSnapshot(.init(projects: [project], sessions: [], availableAgentKinds: [.claudeCode]))
        #expect(dashboard.projects == [project])
        #expect(commands == 0)
        #expect(dashboard.isRuntimeProjection)
    }

    @Test func failedProjectCreationDoesNotPublishProjectOrSuccess() async throws {
        enum Disconnected: Error { case offline }
        let dashboard = try DashboardViewModel(projection: .init(projects: [], sessions: [], availableAgentKinds: [])) { _ in
            throw Disconnected.offline
        }
        await #expect(throws: Disconnected.self) {
            try await dashboard.addProjectFromRuntime(name: "new", directoryPath: "/new")
        }
        #expect(dashboard.projects.isEmpty)
    }

    @Test func projectionDeleteFailureRetainsExistingState() async throws {
        enum Disconnected: Error { case offline }
        let project = Project(name: "runtime", directoryPath: "/runtime", createdAt: Date(), isManagedDirectory: false)
        let dashboard = try DashboardViewModel(projection: .init(projects: [project], sessions: [], availableAgentKinds: [])) { _ in
            throw Disconnected.offline
        }
        await dashboard.removeProject(project.id)
        #expect(dashboard.projects == [project])
        #expect(dashboard.runtimeCommandError != nil)
    }

    @Test func duplicateProjectSnapshotIsRejectedAtomically() throws {
        let project = Project(name: "runtime", directoryPath: "/runtime", createdAt: Date(), isManagedDirectory: false)
        let dashboard = try DashboardViewModel(projection: .init(projects: [project], sessions: [], availableAgentKinds: [])) { _ in .none }
        #expect(throws: DashboardRuntimeError.self) {
            try dashboard.applyRuntimeSnapshot(.init(projects: [project, project], sessions: [], availableAgentKinds: []))
        }
        #expect(dashboard.projects == [project])
    }

    @Test func snapshotsKeepSessionIdentityAndLocalDraft() throws {
        var session = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(), agentRef: .builtin(.codex), workingDirectory: "/runtime")
        let dashboard = try DashboardViewModel(projection: .init(projects: [], sessions: [.chat(session)], availableAgentKinds: [.codex])) { _ in .none }
        let original = try #require(dashboard.sessionNode(id: session.id)?.appServer)
        original.draft = "送信前の下書き"
        session.titleState = .legacy(name: "実行側で変更")
        try dashboard.applyRuntimeSnapshot(.init(projects: [], sessions: [.chat(session)], availableAgentKinds: [.codex]))
        let attached = try #require(dashboard.sessionNode(id: session.id)?.appServer)
        #expect(attached === original)
        #expect(attached.draft == "送信前の下書き")
        #expect(attached.titleState == session.titleState)
    }

    @Test func invalidLaterSessionDoesNotPartiallyApplyEarlierSession() throws {
        var first = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(), agentRef: .builtin(.codex), workingDirectory: "/runtime")
        let second = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(), agentRef: .builtin(.claudeCode), workingDirectory: "/runtime")
        let dashboard = try DashboardViewModel(projection: .init(projects: [], sessions: [.chat(first), .chat(second)], availableAgentKinds: [])) { _ in .none }
        let originalTitle = try #require(dashboard.sessionNode(id: first.id)?.appServer).titleState
        first.titleState = .legacy(name: "部分適用してはいけない")
        let invalid = SessionRuntimeChatSnapshot(id: second.id, startedAt: second.startedAt.addingTimeInterval(1), agentRef: second.agentRef, workingDirectory: second.workingDirectory)
        #expect(throws: (any Error).self) {
            try dashboard.applyRuntimeSnapshot(.init(projects: [], sessions: [.chat(first), .chat(invalid)], availableAgentKinds: []))
        }
        #expect(dashboard.sessionNode(id: first.id)?.appServer?.titleState == originalTitle)
    }

    @Test func projectionCommandsPreserveInvocationOrderAcrossSuspension() async throws {
        let events = AsyncStream<Void>.makeStream()
        var iterator = events.stream.makeAsyncIterator()
        var release: CheckedContinuation<Void, Never>?
        var received: [String] = []
        let projectID = ProjectID()
        let dashboard = try DashboardViewModel(projection: .init(projects: [], sessions: [], availableAgentKinds: [])) { command in
            switch command {
            case .renameSession:
                received.append("rename")
                await withCheckedContinuation { continuation in
                    release = continuation
                    events.continuation.yield(())
                }
                return .none
            case .renameProject:
                received.append("project")
                return .none
            case .addProject:
                received.append("add")
                return .projectID(projectID)
            default: throw DashboardRuntimeError.unexpectedReply
            }
        }
        dashboard.renameSession(SessionID(), to: "first")
        await iterator.next()
        dashboard.renameProject(projectID, to: "second")
        release?.resume()
        let added = try await dashboard.addProjectFromRuntime(name: "third", directoryPath: "/third")
        #expect(added == projectID)
        #expect(received == ["rename", "project", "add"])
        events.continuation.finish()
    }

    @Test func saturatedCommandQueueRejectsMoreWorkExplicitly() async throws {
        let events = AsyncStream<Void>.makeStream()
        var iterator = events.stream.makeAsyncIterator()
        let dashboard = try DashboardViewModel(projection: .init(projects: [], sessions: [], availableAgentKinds: [])) { _ in
            events.continuation.yield(())
            return .none
        }
        for index in 0..<257 { dashboard.renameSession(SessionID(), to: String(index)) }
        #expect(dashboard.runtimeCommandError == DashboardRuntimeError.commandQueueFull.localizedDescription)
        for _ in 0..<256 { await iterator.next() }
        events.continuation.finish()
    }

    @Test func initialAttachmentRestoresSelectionOnceAndHonorsRuntimePresentation() throws {
        let project = Project(name: "runtime", directoryPath: "/runtime", createdAt: Date(), isManagedDirectory: false)
        var older = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(timeIntervalSince1970: 1), agentRef: .builtin(.codex), workingDirectory: "/runtime")
        var recent = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(timeIntervalSince1970: 2), agentRef: .builtin(.claudeCode), workingDirectory: "/runtime")
        older.projectID = project.id
        recent.projectID = project.id
        var snapshot = DashboardRuntimeSnapshot(projects: [project], sessions: [.chat(older), .chat(recent)], availableAgentKinds: [])
        let dashboard = try DashboardViewModel(projection: snapshot) { _ in .none }
        #expect(dashboard.restoredSessionPresentation?.selectedSessionID == recent.id)
        snapshot.restoredSessionPresentation = .init(selectedSessionID: older.id, expandedProjectIDs: [project.id])
        try dashboard.applyRuntimeSnapshot(snapshot)
        #expect(dashboard.restoredSessionPresentation?.selectedSessionID == recent.id)
        let reattached = try DashboardViewModel(projection: snapshot) { _ in .none }
        #expect(reattached.restoredSessionPresentation?.selectedSessionID == older.id)
    }
}
