import Foundation
import Testing
import AgentDomain
import MessageStore
import StructuredChatKit
import CodexAppServerKit
@testable import DashboardFeature
@testable import SessionFeature

private actor HistoryResumeClient: StructuredAgentClient, SpawnAgentSettingsControlling {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var resumed: [String] = []

    init() { (events, continuation) = AsyncStream.makeStream() }
    func start() async throws {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws { resumed.append(sessionRef) }
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {}
}

@Suite(.serialized) @MainActor
struct SessionResumeHistoryTests {
    private func fixture() throws -> URL {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        let directory = root.appendingPathComponent(".verification/session-resume-history/fixtures/\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("Codex session-resume-history。履歴取得と名前保存のテストデータ。起動プロセスなし。".utf8)
            .write(to: directory.appendingPathComponent("OWNER.md"))
        return directory
    }

    private func dashboard(directory: URL, namesURL: URL? = nil, client: HistoryResumeClient = HistoryResumeClient()) -> DashboardViewModel {
        let environment = AppEnvironment(
            pty: MockPTYManager(), hook: MockHookServer(events: AsyncStream { $0.finish() }),
            hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
            claudeSettingsURL: directory.appendingPathComponent("hooks.json"),
            hookDispatcherPath: directory.appendingPathComponent("dispatcher.sh").path,
            claudeBinaryPath: "/bin/echo", pathEnvironment: "/usr/bin:/bin",
            codexHome: directory.appendingPathComponent("codex"),
            workspaceDirectory: directory.appendingPathComponent("workspaces"),
            agentBinaryPaths: [.codex: "/bin/echo"], controlURL: URL(string: "http://127.0.0.1:9999")!,
            tokenStore: SessionTokenStore(), messages: MockMessageStore(),
            sessions: JSONSessionStore(fileURL: directory.appendingPathComponent("sessions.json")),
            sessionHistoryNames: JSONSessionHistoryNameStore(fileURL: namesURL ?? directory.appendingPathComponent("history-names.json")),
            cliPath: directory.appendingPathComponent("phlox").path,
            fullAccessProvider: { _ in true }, appServerClientFactory: { _, _, _, _, _ in client }
        )
        let result = DashboardViewModel(environment: environment, paneLayoutStore: nil)
        result.addProject(name: "History", directoryPath: directory.path)
        return result
    }

    private func entry(_ id: String, title: String = "元の依頼") -> ClaudeSessionHistoryEntry {
        ClaudeSessionHistoryEntry(sessionID: id, preview: title, firstUserAt: nil, lastModified: Date(),
            gitBranch: nil, fileURL: URL(fileURLWithPath: "/unread-history.jsonl"), titleUserMessages: [title])
    }

    @Test(arguments: [AgentKind.claudeCode, .codex])
    func deletionNameSurvivesReopeningStore(kind: AgentKind) async throws {
        let directory = try fixture()
        let dashboard = dashboard(directory: directory)
        let project = try #require(dashboard.projects.first)
        let id = try await dashboard.spawnNewSession(kind: kind, projectID: project.id)
        let node = try #require(dashboard.sessionNode(id: id))
        node.pty?.nativeSessionID = "deleted-conversation"
        let name = "削除した時の名前。長い手動名も自動の32文字制限で切り詰めずそのまま引き継ぐ"
        dashboard.renameSession(id, to: name)
        #expect(await dashboard.removeSession(id))
        await dashboard.waitForPendingPersistenceWritesForTesting()
        let reopened = self.dashboard(directory: directory)
        let reopenedProject = try #require(reopened.projects.first)
        let original = entry("deleted-conversation")
        let history = try await DashboardViewModel.$newChatHistoryLoader.withValue({ [original] }) {
            try await reopened.newChatHistoryEntries(projectID: reopenedProject.id, agentRef: .builtin(kind))
        }
        let result = try #require(history.first)
        #expect(result.savedTitle == name)
        #expect(HistoryEntryPresentation(entry: result, workingDirectory: directory.path).title == name)
        #expect(await JSONSessionStore(fileURL: directory.appendingPathComponent("sessions.json")).load().isEmpty)
    }

    @Test func namesAreSeparatedByHarnessAndLastDeletionWins() async throws {
        let directory = try fixture()
        let url = directory.appendingPathComponent("names.json")
        let store = JSONSessionHistoryNameStore(fileURL: url)
        let claude = SessionHistoryKey(agentRef: .builtin(.claudeCode), nativeSessionID: "same-id")
        let codex = SessionHistoryKey(agentRef: .builtin(.codex), nativeSessionID: "same-id")
        try await store.record(key: claude, name: "Claudeの名前")
        try await store.record(key: codex, name: "Codexの古い名前")
        try await store.record(key: codex, name: "Codexの削除時名")
        let names = await JSONSessionHistoryNameStore(fileURL: url).names()
        #expect(names[claude] == "Claudeの名前")
        #expect(names[codex] == "Codexの削除時名")
        #expect(names.count == 2)
    }

    @Test func productionHistoryReplacesExcludedRowsBeforeTwentyEntryLimit() async throws {
        let directory = try fixture()
        let sessions = directory.appendingPathComponent("codex/sessions/2026/10/23")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        var identifiers: [String] = []
        for index in 0..<21 {
            let id = UUID().uuidString.lowercased()
            identifiers.append(id)
            let url = sessions.appendingPathComponent("rollout-\(id).jsonl")
            let records: [[String: Any]] = [
                ["type": "session_meta", "payload": ["id": id, "cwd": directory.path]],
                ["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "依頼\(index)"]]]],
            ]
            let text = try records.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n")
            try text.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(1000 - index))], ofItemAtPath: url.path)
        }
        let dashboard = dashboard(directory: directory)
        let project = try #require(dashboard.projects.first)
        let openID = try await dashboard.spawnNewSession(kind: .codex, projectID: project.id)
        dashboard.sessionNode(id: openID)?.pty?.nativeSessionID = identifiers[0]
        let history = try await dashboard.newChatHistoryEntries(projectID: project.id, agentRef: .builtin(.codex))
        #expect(history.map(\.sessionID) == Array(identifiers.dropFirst()))
        #expect(await dashboard.removeSession(openID))
    }

    @Test func openConversationsAreExcludedAcrossProjectsAndStates() async throws {
        let directory = try fixture()
        let dashboard = dashboard(directory: directory)
        let project = try #require(dashboard.projects.first)
        dashboard.addProject(name: "Other", directoryPath: directory.appendingPathComponent("other").path)
        let other = try #require(dashboard.projects.last)
        let claudeID = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: other.id)
        let codexID = try await dashboard.spawnNewSession(kind: .codex, projectID: project.id)
        dashboard.sessionNode(id: claudeID)?.pty?.nativeSessionID = "open-id"
        dashboard.sessionNode(id: codexID)?.pty?.nativeSessionID = "other-harness-id"
        await dashboard.sessionNode(id: claudeID)?.pty?.kill()
        let rows = [entry("open-id"), entry("other-harness-id"), entry("different-id")]
        let history = try await DashboardViewModel.$newChatHistoryLoader.withValue({ rows }) {
            try await dashboard.newChatHistoryEntries(projectID: project.id, agentRef: .builtin(.claudeCode))
        }
        #expect(history.map(\.sessionID) == ["other-harness-id", "different-id"])
        #expect(await dashboard.removeSession(claudeID))
        #expect(await dashboard.removeSession(codexID))
    }

    @Test func liveChatConversationIsExcludedWhileIdleAndRunning() async throws {
        let directory = try fixture()
        let client = HistoryResumeClient()
        let dashboard = dashboard(directory: directory, client: client)
        let project = try #require(dashboard.projects.first)
        let id = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: project.id, backend: .appServer)
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        client.continuation.yield(.turnCompleted(nativeSessionId: "live-chat"))
        let deadline = ContinuousClock.now + .seconds(3)
        while vm.threadId != "live-chat", ContinuousClock.now < deadline { await Task.yield() }
        #expect(vm.threadId == "live-chat")
        #expect(vm.status == .idle)
        let rows = [entry("live-chat"), entry("same-title-other-conversation")]
        let idle = try await DashboardViewModel.$newChatHistoryLoader.withValue({ rows }) {
            try await dashboard.newChatHistoryEntries(projectID: project.id, agentRef: .builtin(.claudeCode))
        }
        #expect(idle.map(\.sessionID) == ["same-title-other-conversation"])
        client.continuation.yield(.turnStarted)
        while vm.status != .running, ContinuousClock.now < deadline { await Task.yield() }
        #expect(vm.status == .running)
        #expect(dashboard.availableHistoryEntries(rows, agentRef: .builtin(.claudeCode)).map(\.sessionID) == ["same-title-other-conversation"])
        #expect(await dashboard.removeSession(id))
    }

    @Test func conversationOpenedDuringLoadingIsExcluded() async throws {
        let directory = try fixture()
        let dashboard = dashboard(directory: directory)
        let project = try #require(dashboard.projects.first)
        let id = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: project.id)
        let row = entry("opened-during-load")
        let (started, continuation) = AsyncStream<Void>.makeStream()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); continuation.finish() }
        let loading = Task {
            try await DashboardViewModel.$newChatHistoryLoader.withValue({ continuation.yield(()); gate.wait(); return [row] }) {
                try await dashboard.newChatHistoryEntries(projectID: project.id, agentRef: .builtin(.claudeCode))
            }
        }
        for await _ in started { break }
        dashboard.sessionNode(id: id)?.pty?.nativeSessionID = row.sessionID
        gate.signal()
        #expect(try await loading.value.isEmpty)
        #expect(await dashboard.removeSession(id))
    }

    @Test func nameWriteFailureRetainsSessionAndWorkspace() async throws {
        let directory = try fixture()
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blocker)
        let dashboard = dashboard(directory: directory, namesURL: blocker.appendingPathComponent("names.json"))
        let project = try #require(dashboard.projects.first)
        let id = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: project.id)
        dashboard.sessionNode(id: id)?.pty?.nativeSessionID = "cannot-save-name"
        dashboard.renameSession(id, to: "失われてはいけない名前")
        #expect(!(await dashboard.removeSession(id)))
        #expect(dashboard.sessionNode(id: id)?.displayName == "失われてはいけない名前")
        #expect(dashboard.runtimeCommandError?.contains("履歴の名前を保存できなかった") == true)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        await dashboard.removeProject(project.id)
        #expect(dashboard.projects.contains { $0.id == project.id })
        #expect(dashboard.sessionNode(id: id) != nil)
        let workspaceID = try await dashboard.spawnNewSession(kind: .claudeCode)
        let workspace = directory.appendingPathComponent("workspaces/\(workspaceID.rawValue.uuidString)")
        dashboard.sessionNode(id: workspaceID)?.pty?.nativeSessionID = "owned-workspace-history"
        #expect(FileManager.default.fileExists(atPath: workspace.path))
        #expect(!(await dashboard.removeSession(workspaceID)))
        #expect(FileManager.default.fileExists(atPath: workspace.path))
        await dashboard.sessionNode(id: id)?.pty?.kill()
        await dashboard.sessionNode(id: workspaceID)?.pty?.kill()
    }

    @Test func runtimeNameWriteFailureReachesSessionRemovalCaller() async throws {
        let directory = try fixture()
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blocker)
        let host = dashboard(directory: directory, namesURL: blocker.appendingPathComponent("names.json"))
        let project = try #require(host.projects.first)
        let id = try await host.spawnNewSession(kind: .claudeCode, projectID: project.id)
        host.sessionNode(id: id)?.pty?.nativeSessionID = "runtime-cannot-save-name"
        host.renameSession(id, to: "失敗時に残す名前")
        let projection = try DashboardViewModel(projection: host.makeRuntimeSnapshot()) {
            try await host.performRuntimeCommand($0)
        }

        #expect(!(await projection.removeSession(id)))
        #expect(projection.runtimeCommandError?.contains("履歴の名前を保存できなかった") == true)
        #expect(host.sessionNode(id: id)?.displayName == "失敗時に残す名前")

        let nextProjection = try DashboardViewModel(projection: host.makeRuntimeSnapshot()) {
            try await host.performRuntimeCommand($0)
        }
        #expect(!(await nextProjection.removeSession(SessionID())))
        #expect(nextProjection.runtimeCommandError == nil)
        await host.sessionNode(id: id)?.pty?.kill()
    }

    @Test func runtimeNameWriteFailureReachesProjectRemovalCaller() async throws {
        let directory = try fixture()
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("block".utf8).write(to: blocker)
        let host = dashboard(directory: directory, namesURL: blocker.appendingPathComponent("names.json"))
        let project = try #require(host.projects.first)
        let id = try await host.spawnNewSession(kind: .claudeCode, projectID: project.id)
        host.sessionNode(id: id)?.pty?.nativeSessionID = "runtime-project-cannot-save-name"
        let projection = try DashboardViewModel(projection: host.makeRuntimeSnapshot()) {
            try await host.performRuntimeCommand($0)
        }

        await projection.removeProject(project.id)
        #expect(projection.runtimeCommandError?.contains("履歴の名前を保存できなかった") == true)
        #expect(host.projects.contains { $0.id == project.id })
        #expect(host.sessionNode(id: id) != nil)
        await host.sessionNode(id: id)?.pty?.kill()
    }

    @Test func savedTitleSurvivesWireAndLocationAndLegacyDataKeepsFallback() throws {
        var row = entry("stored")
        row.savedTitle = "<手動で付けた名前>"
        let decoded = try JSONDecoder().decode(ClaudeSessionHistoryEntry.self, from: JSONEncoder().encode(row))
        let located = decoded.located(in: "/project")
        #expect(HistoryEntryPresentation(entry: located, workingDirectory: "/project").fullTitle == "<手動で付けた名前>")
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any])
        json.removeValue(forKey: "savedTitle")
        let legacy = try JSONDecoder().decode(ClaudeSessionHistoryEntry.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.savedTitle == nil)
        #expect(HistoryEntryPresentation(entry: legacy, workingDirectory: "/project").title == "元の依頼")
    }

    @Test func legacyHistoryUsesSharedNamesAndFiltersCachedEntries() async throws {
        let directory = try fixture()
        let client = HistoryResumeClient()
        let dashboard = dashboard(directory: directory, client: client)
        let project = try #require(dashboard.projects.first)
        let row = entry("old-history")
        let sessions = directory.appendingPathComponent("codex/sessions/2026/10/23")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let meta = try JSONSerialization.data(withJSONObject: ["type": "session_meta", "payload": ["id": row.sessionID, "cwd": directory.path]])
        let message = try JSONSerialization.data(withJSONObject: ["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": row.preview]]]])
        try (String(decoding: meta, as: UTF8.self) + "\n" + String(decoding: message, as: UTF8.self))
            .write(to: sessions.appendingPathComponent("rollout-\(UUID().uuidString).jsonl"), atomically: true, encoding: .utf8)
        try await JSONSessionHistoryNameStore(fileURL: directory.appendingPathComponent("history-names.json"))
            .record(key: SessionHistoryKey(agentRef: .builtin(.codex), nativeSessionID: row.sessionID), name: "履歴の保存名")
        let id = try await dashboard.spawnNewSession(kind: .codex, projectID: project.id, backend: .appServer)
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        #expect(vm.historyEntries.first?.savedTitle == "履歴の保存名")
        #expect(vm.shouldOfferHistoryStart)
        let ptyID = try await dashboard.spawnNewSession(kind: .codex, projectID: project.id)
        dashboard.sessionNode(id: ptyID)?.pty?.nativeSessionID = row.sessionID
        #expect(vm.historyEntries.isEmpty)
        #expect(!vm.shouldOfferHistoryStart)
        await vm.startFromHistory(row)
        #expect(await client.resumed.isEmpty)
        #expect(await dashboard.removeSession(ptyID))
        var saved = row
        saved.savedTitle = "履歴の保存名"
        await vm.startFromHistory(saved)
        #expect(vm.displayName == "履歴の保存名")
        #expect(await client.resumed == [row.sessionID])
        #expect(await dashboard.removeSession(id))
    }

    @Test func runtimeHistoryPreservesNamesAndNativePTYIdentity() async throws {
        let directory = try fixture()
        let host = dashboard(directory: directory)
        let project = try #require(host.projects.first)
        let id = try await host.spawnNewSession(kind: .claudeCode, projectID: project.id)
        host.sessionNode(id: id)?.pty?.nativeSessionID = "runtime-open"
        var saved = entry("runtime-closed")
        saved.savedTitle = "削除時の名前"
        let rows = [entry("runtime-open"), saved]
        let snapshot = try JSONDecoder().decode(DashboardRuntimeSnapshot.self, from: JSONEncoder().encode(host.makeRuntimeSnapshot()))
        let projection = try DashboardViewModel(projection: snapshot) { command in
            guard case .history(let projectID, let ref) = command else { return .none }
            return .history(try await host.newChatHistoryEntries(projectID: projectID, agentRef: ref))
        }
        let history = try await DashboardViewModel.$newChatHistoryLoader.withValue({ rows }) {
            try await projection.newChatHistoryEntries(projectID: project.id, agentRef: .builtin(.claudeCode))
        }
        #expect(projection.sessionNode(id: id)?.pty?.nativeSessionID == "runtime-open")
        #expect(history.map(\.sessionID) == ["runtime-closed"])
        #expect(history.first?.savedTitle == "削除時の名前")
        #expect(await host.removeSession(id))
    }
}
