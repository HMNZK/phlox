import AgentDomain
import Foundation
import HookServer
import MessageStore
import PTYKit
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@MainActor
@Suite(.serialized)
struct ControlNewChatParityAcceptanceTests {
    @Test("履歴の読取中にプロジェクトが削除されたら起動を拒否する")
    func projectRemovedDuringHistoryLoadingCreatesNothing() async throws {
        let client = ParityControlClient()
        let fixture = try await fixture(client: client)
        try git(["init", "--initial-branch=dev"], in: fixture.project)
        try git(["-c", "user.name=Parity Test", "-c", "user.email=parity@example.invalid", "commit", "--allow-empty", "-m", "Fixture"], in: fixture.project)
        let history = ClaudeSessionHistoryEntry(sessionID: "resumable-history", preview: "Earlier task",
            firstUserAt: nil, lastModified: Date(), gitBranch: "dev",
            fileURL: fixture.root.appendingPathComponent("history.jsonl"), sourceWorkingDirectory: fixture.project.path)
        let started = AsyncStream<Void>.makeStream()
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal(); started.continuation.finish() }
        let launching = Task {
            defer { started.continuation.finish() }
            return try await DashboardViewModel.$newChatHistoryLoader.withValue({
                started.continuation.yield(())
                guard gate.wait(timeout: .now() + 5) == .success else { throw HistoryGateError.timedOut }
                return [history]
            }) {
                try await fixture.dashboard.spawnNewSessionFromControlAPI(
                    ref: .builtin(.codex), requester: nil, backend: .appServer,
                    workingDirectory: nil, projectID: fixture.projectID, initialSettings: nil,
                    usesWorktree: true, resumeHistoryID: history.sessionID)
            }
        }
        var events = started.stream.makeAsyncIterator()
        let didStart: Void? = await events.next()
        try #require(didStart != nil)

        await fixture.dashboard.removeProject(fixture.projectID)
        #expect(!fixture.dashboard.projects.contains { $0.id == fixture.projectID })
        gate.signal()

        await #expect(throws: AgentSpawnError.unknownProject) { try await launching.value }
        #expect(fixture.dashboard.sessionNodes.isEmpty)
        #expect(await client.starts == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("workspaces").path))
    }

    @Test("新しい起動指定でも未知のプロジェクトを拒否する")
    func unknownProjectCreatesNoSession() async throws {
        let fixture = try await fixture()
        await #expect(throws: AgentSpawnError.unknownProject) {
            _ = try await fixture.dashboard.spawnNewSessionFromControlAPI(
                ref: .builtin(.codex), requester: nil, backend: .appServer,
                workingDirectory: nil, projectID: ProjectID(), initialSettings: nil, usesWorktree: false)
        }
        #expect(fixture.dashboard.sessionNodes.isEmpty)
    }

    @Test("存在しない起点ではセッションもworktreeも作らない")
    func unresolvedStartPointCreatesNothing() async throws {
        let fixture = try await fixture()
        try git(["init", "--initial-branch=dev"], in: fixture.project)
        try git(["-c", "user.name=Parity Test", "-c", "user.email=parity@example.invalid", "commit", "--allow-empty", "-m", "Fixture"], in: fixture.project)

        await #expect(throws: (any Error).self) {
            _ = try await fixture.dashboard.spawnNewSessionFromControlAPI(
                ref: .builtin(.codex), requester: nil, backend: .appServer,
                workingDirectory: nil, projectID: fixture.projectID, initialSettings: nil,
                usesWorktree: true, worktreeStartPoint: .localBranch("not-a-real-branch"))
        }

        #expect(fixture.dashboard.sessionNodes.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("workspaces").path))
    }

    @Test("別プロジェクトに属するCodex履歴を再開しない")
    func historyFromAnotherProjectIsRejected() async throws {
        let fixture = try await fixture()
        let historyID = UUID().uuidString.lowercased()
        let sessions = fixture.root.appendingPathComponent("codex/sessions/2026/10/25")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let records: [[String: Any]] = [
            ["type": "session_meta", "payload": ["id": historyID, "cwd": fixture.root.appendingPathComponent("other-project").path]],
            ["type": "response_item", "payload": ["type": "message", "role": "user", "content": [["type": "input_text", "text": "Other project task"]]]],
        ]
        let text = try records.map { String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }.joined(separator: "\n")
        try text.write(to: sessions.appendingPathComponent("rollout-\(historyID).jsonl"), atomically: true, encoding: .utf8)

        await #expect(throws: AgentSpawnError.historyNotFound) {
            _ = try await fixture.dashboard.spawnNewSessionFromControlAPI(
                ref: .builtin(.codex), requester: nil, backend: .appServer,
                workingDirectory: nil, projectID: fixture.projectID, initialSettings: nil,
                usesWorktree: false, resumeHistoryID: historyID)
        }
        #expect(fixture.dashboard.sessionNodes.isEmpty)
    }

    @Test("履歴非対応のエージェントへ再開指定を渡せない")
    func unsupportedAgentCannotResumeHistory() async throws {
        let fixture = try await fixture()
        await #expect(throws: AgentSpawnError.unsupportedBackend) {
            _ = try await fixture.dashboard.spawnNewSessionFromControlAPI(
                ref: .builtin(.cursor), requester: nil, backend: .appServer,
                workingDirectory: nil, projectID: fixture.projectID, initialSettings: nil,
                usesWorktree: false, resumeHistoryID: "earlier-session")
        }
        #expect(fixture.dashboard.sessionNodes.isEmpty)
    }

    @Test("新しい起動指定でも親子関係と所属を維持する")
    func newOptionsKeepControlParentRelationship() async throws {
        let fixture = try await fixture()
        let parentID = try await fixture.dashboard.spawnNewSessionFromControlAPI(
            ref: .builtin(.codex), requester: nil, backend: .appServer,
            workingDirectory: nil, projectID: fixture.projectID, initialSettings: nil, usesWorktree: false)
        let childID = try await fixture.dashboard.spawnNewSessionFromControlAPI(
            ref: .builtin(.codex), requester: parentID, backend: .appServer,
            workingDirectory: nil, projectID: fixture.projectID, initialSettings: nil, usesWorktree: false)
        let child = try #require(fixture.dashboard.sessionNode(id: childID))
        #expect(child.controllable.parentSessionID == parentID)
        #expect(child.projectID == fixture.projectID)
        #expect(child.launchContext == .orchestration)
        await fixture.dashboard.removeSession(childID)
        await fixture.dashboard.removeSession(parentID)
    }

    @Test("新しい起動指定でControlの起動頻度制限を迂回できない")
    func newOptionsKeepControlRateLimit() async throws {
        let fixture = try await fixture()
        for _ in 0..<DashboardViewModel.maxAPISpawnCountPerSecond {
            _ = try await fixture.dashboard.spawnNewSessionFromControlAPI(
                ref: .builtin(.codex), requester: nil, backend: .appServer,
                workingDirectory: nil, projectID: fixture.projectID, initialSettings: nil, usesWorktree: false)
        }
        await #expect(throws: AgentSpawnError.spawnRateLimited) {
            _ = try await fixture.dashboard.spawnNewSessionFromControlAPI(
                ref: .builtin(.codex), requester: nil, backend: .appServer,
                workingDirectory: nil, projectID: fixture.projectID, initialSettings: nil, usesWorktree: false)
        }
        #expect(fixture.dashboard.sessionNodes.count == DashboardViewModel.maxAPISpawnCountPerSecond)
        for id in fixture.dashboard.sessionNodes.map(\.id) { await fixture.dashboard.removeSession(id) }
    }

    private enum HistoryGateError: Error { case timedOut }

    private func fixture(client: ParityControlClient? = nil) async throws -> (root: URL, project: URL, dashboard: DashboardViewModel, projectID: ProjectID) {
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { repository.deleteLastPathComponent() }
        let root = repository.appendingPathComponent(".verification/mobile-parity-20261025/dashboard/\(UUID())")
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        try Data("作成者: Codex parity_acceptance_tests。新規チャットの認可・起点・履歴検査。実エージェントプロセスなし。\n".utf8)
            .write(to: root.appendingPathComponent("OWNER.md"))
        let environment = AppEnvironment(
            pty: MockPTYManager(), hook: MockHookServer(events: AsyncStream { $0.finish() }),
            hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
            claudeSettingsURL: root.appendingPathComponent("hooks.json"),
            hookDispatcherPath: root.appendingPathComponent("dispatcher.sh").path,
            claudeBinaryPath: "/bin/echo", pathEnvironment: "/usr/bin:/bin",
            claudeUsageRateLimitsURL: root.appendingPathComponent("usage.json"),
            codexHome: root.appendingPathComponent("codex"), workspaceDirectory: root.appendingPathComponent("workspaces"),
            agentBinaryPaths: [.codex: "/bin/echo"], controlURL: URL(string: "http://127.0.0.1:9999")!,
            tokenStore: SessionTokenStore(), messages: MockMessageStore(),
            sessionHistoryNames: JSONSessionHistoryNameStore(fileURL: root.appendingPathComponent("history-names.json")),
            cliPath: root.appendingPathComponent("phlox").path,
            fullAccessProvider: { _ in true }, appServerClientFactory: { _, _, _, _, _ in client ?? ParityControlClient() })
        let dashboard = DashboardViewModel(environment: environment,
                                           codexUserHooksEnabledProvider: { false },
                                           rateLimitNow: { Date(timeIntervalSince1970: 1_800_000_000) },
                                           orphanReaper: MockOrphanReaper(alivePIDs: []), paneLayoutStore: nil)
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Parity", directoryPath: project.path))
        return (root, project, dashboard, projectID)
    }

    private func git(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "ParityGitFixture", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: String(decoding: data, as: UTF8.self)])
        }
    }
}

private actor ParityControlClient: StructuredAgentClient, SpawnAgentSettingsControlling {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var starts = 0
    init() { (events, continuation) = AsyncStream.makeStream() }
    func start() async throws { starts += 1 }
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {}
}
