import AgentDomain
import Foundation
import SessionFeature
import Testing
@testable import DashboardFeature

@Suite @MainActor struct DashboardRuntimeChatReadCapabilityTests {
    @Test func capabilityChangesReachExistingAndNewSnapshotSessions() throws {
        let first = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(timeIntervalSince1970: 100),
            agentRef: .builtin(.codex), workingDirectory: "/first")
        let second = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(timeIntervalSince1970: 200),
            agentRef: .builtin(.claudeCode), workingDirectory: "/second")
        let screen = try DashboardViewModel(projection: .init(projects: [], sessions: [.chat(first)],
            availableAgentKinds: [.codex, .claudeCode])) { _ in .none }

        screen.runtimeSupportsChatReadModel = true
        try screen.applyRuntimeSnapshot(.init(projects: [], sessions: [.chat(first), .chat(second)],
            availableAgentKinds: [.codex, .claudeCode]))
        #expect(screen.sessionNode(id: first.id)?.appServer?.runtimeSupportsChatReadModel == true)
        #expect(screen.sessionNode(id: second.id)?.appServer?.runtimeSupportsChatReadModel == true)
        screen.runtimeSupportsChatReadModel = false
        #expect(screen.sessionNode(id: first.id)?.appServer?.runtimeSupportsChatReadModel == false)
        #expect(screen.sessionNode(id: second.id)?.appServer?.runtimeSupportsChatReadModel == false)
    }

    @Test func capabilityChangesReachExistingAndNewOverviewSessions() throws {
        let first = ChatSessionViewModel(projection: SessionRuntimeChatSnapshot(id: SessionID(),
            startedAt: Date(timeIntervalSince1970: 100), agentRef: .builtin(.codex), workingDirectory: "/first")) { _, _ in .none }
        let second = ChatSessionViewModel(projection: SessionRuntimeChatSnapshot(id: SessionID(),
            startedAt: Date(timeIntervalSince1970: 200), agentRef: .builtin(.claudeCode), workingDirectory: "/second")) { _, _ in .none }
        let screen = try DashboardViewModel(overview: .init(projects: [], sessions: [first.makeRuntimeOverview()],
            availableAgentKinds: [.codex, .claudeCode])) { _ in .none }

        screen.runtimeSupportsChatReadModel = true
        try screen.applyRuntimeOverview(.init(projects: [], sessions: [first.makeRuntimeOverview(), second.makeRuntimeOverview()],
            availableAgentKinds: [.codex, .claudeCode]))
        #expect(screen.sessionNode(id: first.id)?.appServer?.runtimeSupportsChatReadModel == true)
        #expect(screen.sessionNode(id: second.id)?.appServer?.runtimeSupportsChatReadModel == true)
        screen.runtimeSupportsChatReadModel = false
        #expect(screen.sessionNode(id: first.id)?.appServer?.runtimeSupportsChatReadModel == false)
        #expect(screen.sessionNode(id: second.id)?.appServer?.runtimeSupportsChatReadModel == false)
    }
}
