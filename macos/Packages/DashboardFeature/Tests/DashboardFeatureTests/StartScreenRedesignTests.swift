import AgentDomain
import Foundation
import Testing
@testable import DashboardFeature

// 08 空の画面と新規セッション: 起動カードの並び・権限の初期値・表の行・キー操作・衝突の確認・worktree の失敗。

@Suite("Start screen redesign (08)")
struct StartScreenRedesignTests {

    @Test func entries_keepUndetectedAgentsInCatalogOrder() {
        let descriptors = [.claudeCode, .codex, .cursor].map { AgentRegistry.descriptor(for: $0) }
        let entries = AgentStartEntries.make(descriptors: descriptors) { ref in
            ref == .builtin(.cursor) ? nil : "/usr/local/bin/\(ref.id)"
        }
        #expect(entries.map(\.descriptor.ref) == [.builtin(.claudeCode), .builtin(.codex), .builtin(.cursor)])
        #expect(entries.map(\.isDetected) == [true, true, false])
    }

    @Test func permission_isShownOnlyWhereTheAppDecidesIt() {
        #expect(AgentStartEntries.permission(ref: .builtin(.claudeCode), fullAccess: false, languageCode: "ja") == nil)
        #expect(AgentStartEntries.permission(ref: .builtin(.claudeCode), fullAccess: true, languageCode: "ja") != nil)
        #expect(AgentStartEntries.permission(ref: .builtin(.cursor), fullAccess: false, languageCode: "ja") == nil)
        let codex = AgentStartEntries.permission(ref: .builtin(.codex), fullAccess: false, languageCode: "ja")
        #expect(codex?.hasPrefix("必要時に承認を要求 · ") == true)
        #expect(AgentStartEntries.permission(ref: .custom("aider"), fullAccess: true, languageCode: "ja") == nil)
    }

    @Test func model_joinsEffortOnlyWhenModelIsKnown() {
        #expect(AgentStartEntries.model(nil) == nil)
        #expect(AgentStartEntries.model(LastUsedChatSettings(model: nil, effort: "high")) == nil)
        #expect(AgentStartEntries.model(LastUsedChatSettings(model: "gpt-6-sol", effort: "high")) == "gpt-6-sol · high")
        #expect(AgentStartEntries.model(LastUsedChatSettings(model: "opus")) == "opus")
    }

    @Test func tableRows_followTerminalOrder_andMarkChatSupport() {
        let chat = AgentRegistry.descriptor(for: .codex)
        let model = NewSessionMenuModel.make(projectName: "phlox", descriptors: [chat])
        let rows = NewSessionTableRow.rows(from: model)
        #expect(rows == [NewSessionTableRow(title: chat.displayName, ref: chat.ref, supportsChat: chat.supportsStructuredChat)])
    }

    @Test func returnKey_followsDefaultOpenMode_andOptionPicksTheOther() {
        #expect(NewSessionKeys.mode(default: .chat, option: false, supportsChat: true) == .chat)
        #expect(NewSessionKeys.mode(default: .chat, option: true, supportsChat: true) == .terminal)
        #expect(NewSessionKeys.mode(default: .terminal, option: false, supportsChat: true) == .terminal)
        #expect(NewSessionKeys.mode(default: .terminal, option: true, supportsChat: true) == .chat)
        #expect(NewSessionKeys.mode(default: .chat, option: false, supportsChat: false) == .terminal)
    }

    @Test func collisionGate_listsActiveSessionsInTheSameFolder_onlyWithoutIsolation() {
        let directory = FileManager.default.temporaryDirectory.path
        let same = SessionID(), finished = SessionID(), elsewhere = SessionID()
        let workspaces = [
            SessionWorkspace(sessionID: same, workingDirectory: directory + "/", isActive: true),
            SessionWorkspace(sessionID: finished, workingDirectory: directory, isActive: false),
            SessionWorkspace(sessionID: elsewhere, workingDirectory: "/tmp/phlox-other-\(UUID().uuidString)", isActive: true),
        ]
        var project = Project(name: "p", directoryPath: directory, createdAt: .now, isManagedDirectory: false)
        #expect(NewSessionCollisionGate.peers(project: project, among: workspaces) == [same])
        project.worktreeIsolationEnabled = true
        #expect(NewSessionCollisionGate.peers(project: project, among: workspaces).isEmpty)
    }

    @Test func worktreeFailureLog_showsGitOutput_andIgnoresOtherErrors() {
        let failed = WorktreeIsolationSpawnError.worktreeCreationFailed(path: "/w", branchName: "b", detail: "fatal: already checked out")
        #expect(NewSessionCollisionGate.worktreeFailureLog(failed) == "fatal: already checked out")
        let aborted = WorktreeIsolationSpawnError.aborted(.notAGitRepository(path: "/p"))
        #expect(NewSessionCollisionGate.worktreeFailureLog(aborted) == aborted.localizedDescription)
        #expect(NewSessionCollisionGate.worktreeFailureLog(AgentSpawnError.unsupportedBackend) == nil)
    }

    @Test func isolationOptOut_survivesPersistence_andOldDataHasNone() throws {
        let base = PersistedSessionDescriptor(
            id: SessionID(), kind: .codex, workingDirectory: "/tmp/p", name: "n",
            projectID: nil, startedAt: Date(timeIntervalSince1970: 0), command: "/bin/cat", args: [], env: [:]
        )
        let roundTrip = { (value: PersistedSessionDescriptor) in
            try JSONDecoder().decode(PersistedSessionDescriptor.self, from: JSONEncoder().encode(value))
        }
        #expect(try roundTrip(base.updating(worktreeIsolationOptOut: true)).worktreeIsolationOptOut == true)
        #expect(try roundTrip(base).worktreeIsolationOptOut == nil)
    }
}
