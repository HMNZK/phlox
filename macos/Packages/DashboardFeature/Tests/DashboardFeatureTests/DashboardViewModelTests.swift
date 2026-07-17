import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import HookServer
import MessageStore
import PTYKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - Mock Hook Server

struct MockHookServer: HookServerProtocol {
    let events: AsyncStream<(SessionID, HookEvent)>
    let deliveries: AsyncStream<HookDelivery>

    init(events: AsyncStream<(SessionID, HookEvent)>) {
        self.events = events
        self.deliveries = AsyncStream { continuation in
            Task {
                for await (sessionID, event) in events {
                    continuation.yield(HookDelivery(sessionID: sessionID, event: event))
                }
                continuation.finish()
            }
        }
    }

    init(deliveries: AsyncStream<HookDelivery>) {
        self.events = AsyncStream { _ in }
        self.deliveries = deliveries
    }

    func start() async throws -> Int { 0 }
}

actor InMemorySessionStore: SessionStoreProtocol {
    private var stored: [PersistedSessionDescriptor]
    private(set) var saveCount = 0

    init(_ sessions: [PersistedSessionDescriptor] = []) {
        self.stored = sessions
    }

    func load() async -> [PersistedSessionDescriptor] {
        stored
    }

    func save(_ sessions: [PersistedSessionDescriptor]) async throws {
        stored = sessions
        saveCount += 1
    }
}

final class StructuredClientSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var clients: [any StructuredAgentClient]

    init(_ clients: [any StructuredAgentClient]) {
        self.clients = clients
    }

    func next() throws -> any StructuredAgentClient {
        lock.lock()
        defer { lock.unlock() }
        guard !clients.isEmpty else {
            throw AgentSpawnError.unsupportedBackend
        }
        return clients.removeFirst()
    }
}

// MARK: - Test helpers

@MainActor
func makeTestEnvironment(
    pty: any PTYManagerProtocol,
    hookStream: AsyncStream<(SessionID, HookEvent)>,
    messages: MockMessageStore = MockMessageStore(),
    projects: any ProjectStoreProtocol = NoOpProjectStore(),
    sessions: any SessionStoreProtocol = NoOpSessionStore(),
    workspaceDirectory: URL = URL(fileURLWithPath: "/tmp/agent-dashboard-test-workspace"),
    codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex", isDirectory: true),
    agentBinaryPaths: [AgentKind: String] = [:],
    customAgentBinaryPaths: [String: String] = [:],
    agentCatalog: AgentCatalog = .builtins,
    transcriptStore: any TranscriptStore = NoOpTranscriptStore(),
    appServerClientFactory: AppEnvironment.AppServerClientFactory? = nil
) -> AppEnvironment {
    AppEnvironment(
        pty: pty,
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        codexHome: codexHome,
        workspaceDirectory: workspaceDirectory,
        agentBinaryPaths: agentBinaryPaths,
        customAgentBinaryPaths: customAgentBinaryPaths,
        agentCatalog: agentCatalog,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: messages,
        projects: projects,
        sessions: sessions,
        transcriptStore: transcriptStore,
        cliPath: "/tmp/agent-dashboard-test-cli",
        appServerClientFactory: appServerClientFactory
    )
}

@Test
@MainActor
func appEnvironment_defaultTranscriptStoreIsNoOp() async throws {
    let environment = makeTestEnvironment(
        pty: MockPTYManager(),
        hookStream: AsyncStream { $0.finish() }
    )
    let sessionID = SessionID()

    #expect(environment.transcriptStore is NoOpTranscriptStore)
    try await environment.transcriptStore.upsertTranscriptItems(
        [.userMessage(id: "user-1", text: "must not persist", timestamp: fixedChatItemTimestamp())],
        for: sessionID
    )
    #expect(try await environment.transcriptStore.loadTranscript(for: sessionID) == [])
}

func makePersistedSessionDescriptor(
    id: SessionID = SessionID(),
    kind: AgentKind = .claudeCode,
    workingDirectory: String,
    name: String? = nil,
    projectID: ProjectID? = nil,
    startedAt: Date = Date(),
    resumeID: String? = nil,
    parentSessionID: SessionID? = nil,
    launchContext: SessionLaunchContext = .interactive
) -> PersistedSessionDescriptor {
    PersistedSessionDescriptor(
        id: id,
        kind: kind,
        workingDirectory: workingDirectory,
        name: name ?? kind.displayName,
        projectID: projectID,
        startedAt: startedAt,
        command: "/usr/local/bin/\(kind.binaryName)",
        args: [],
        env: [:],
        token: "token-\(id.rawValue.uuidString)",
        resumeID: resumeID,
        parentSessionID: parentSessionID,
        launchContext: launchContext
    )
}

func makeCustomAgentDescriptor(
    id: String = "aider",
    baseArgs: [String] = ["--model", "sonnet"],
    bypassArgs: [String] = ["--yes-always"]
) -> AgentDescriptor {
    AgentDescriptor(
        ref: .custom(id),
        displayName: "Aider",
        binaryName: "aider",
        symbolName: "wrench.and.screwdriver",
        colorRGB: AgentRGB(0xE5, 0xA5, 0x3F),
        bypassKey: "phlox.bypass.\(id)",
        launchSpec: AgentLaunchSpec(
            baseArgs: baseArgs,
            bypassArgs: bypassArgs,
            statusBootstrap: .idleOnSpawnComplete
        )
    )
}

func makeTemporaryWorkspaceRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func cleanupTemporaryWorkspaceRoot(_ url: URL) {
    guard FileManager.default.fileExists(atPath: url.path) else { return }
    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        Issue.record("Failed to cleanup temporary workspace \(url.path): \(error)")
    }
}

func assertNoGuideFiles(in workspace: URL, sourceLocation: SourceLocation = #_sourceLocation) {
    let guideFileURLs = [
        workspace
            .appendingPathComponent(".cursor", isDirectory: true)
            .appendingPathComponent("rules", isDirectory: true)
            .appendingPathComponent("phlox.mdc"),
        workspace.appendingPathComponent("AGENTS.md"),
    ]
    for url in guideFileURLs {
        #expect(!FileManager.default.fileExists(atPath: url.path), sourceLocation: sourceLocation)
    }
}

// MARK: - Tests

@Test @MainActor
func removeSession_killsPTYAndRemovesFromList() async throws {
    let ptyManager = MockPTYManager()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    #expect(dashboard.sessions.count == 1)
    let sessionID = dashboard.sessions[0].id

    dashboard.sessions[0].terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    await dashboard.removeSession(sessionID)

    #expect(dashboard.sessions.isEmpty)

    let killedIDs = ptyManager.killedIDs
    #expect(killedIDs == [sessionID])
}

@Test @MainActor
func removeSession_cascadesToAllDescendantsAndKeepsOutsideSessions() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let grandparent = try await dashboard.spawnNewSession(kind: .claudeCode)
    let parent = try await dashboard.spawnNewSession(kind: .claudeCode, from: grandparent)
    let child = try await dashboard.spawnNewSession(kind: .claudeCode, from: parent)
    let grandchild = try await dashboard.spawnNewSession(kind: .claudeCode, from: child)
    let sibling = try await dashboard.spawnNewSession(kind: .claudeCode, from: grandparent)

    try await waitUntil { ptyManager.spawnCalls.count == 5 }
    #expect(dashboard.descendantCount(of: grandparent) == 4)
    #expect(dashboard.descendantCount(of: parent) == 2)

    #expect(await dashboard.removeSession(parent))

    let remainingIDs = Set(dashboard.sessionNodes.map(\.id))
    #expect(remainingIDs.contains(grandparent))
    #expect(remainingIDs.contains(sibling))
    #expect(!remainingIDs.contains(parent))
    #expect(!remainingIDs.contains(child))
    #expect(!remainingIDs.contains(grandchild))

    let killedIDs = ptyManager.killedIDs
    #expect(killedIDs.count == 3)
    #expect(Set(killedIDs) == Set([parent, child, grandchild]))

    try await waitUntil {
        let storedIDs = Set(await sessionStore.load().map(\.id))
        return storedIDs == Set([grandparent, sibling])
    }
}

@Test @MainActor
func spawnNewClaudeCodeSession_eagerlySpawnsWithoutView() async throws {
    // eager spawn: View（SwiftTerm の sizeChanged）を待たず、spawnNewSession の時点で
    // PTY が起動する。これが Phase 1 の本質（API 経由・非表示セッションでも起動する）。
    let ptyManager = MockPTYManager()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()

    #expect(dashboard.sessions.count == 1)
    // onResize を呼ばずとも spawn 済み（eager）。
    #expect(ptyManager.spawnCalls.count == 1)
    let call = try #require(ptyManager.spawnCalls.first)
    #expect(call.id == dashboard.sessions[0].id)
    // 既定 winsize（暫定グリッド or フォールバック 80x24）の正の値で起動する。
    let size = try #require(call.initialSize)
    #expect(size.cols > 0)
    #expect(size.rows > 0)
}

@Test @MainActor
func renameSession_updatesSessionName() async throws {
    let ptyManager = MockPTYManager()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    dashboard.renameSession(sessionID, to: "Backend")

    #expect(dashboard.sessions[0].name == "Backend")
}

@Test @MainActor
func unseenCompletionCountCountsOnlyUnseenCompletions() async throws {
    let ptyManager = MockPTYManager()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    var observedCounts: [Int] = []
    dashboard.unseenCompletionCountDidChange = { observedCounts.append($0) }

    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()

    #expect(dashboard.unseenCompletionCount == 0)

    dashboard.sessions[0].hasUnseenCompletion = true
    #expect(dashboard.unseenCompletionCount == 1)

    dashboard.sessions[1].hasUnseenCompletion = true
    #expect(dashboard.unseenCompletionCount == 2)

    dashboard.sessions[0].markCompletionSeen()
    #expect(dashboard.unseenCompletionCount == 1)
    #expect(observedCounts == [1, 2, 1])
}

// Chat（app-server）種別の未確認停止が Dock バッジ集計に載る経路の回帰ガード。
// 集計を sessions(PTY 専用) から sessionNodes(両種別) へ変え、appServer 追加時にも
// observeUnseenCompletion を結線した経路を検証する（PTY 専用テストでは立たない値）。
@Test @MainActor
func unseenCompletionCount_includesAppServerChatSession() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"],
        appServerClientFactory: { _, _, _, _, _ in
            EventYieldingStructuredClient()
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    var observedCounts: [Int] = []
    dashboard.unseenCompletionCountDidChange = { observedCounts.append($0) }

    let sessionID = try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
    let chat = try #require(dashboard.sessionNodes.first(where: { $0.id == sessionID })?.appServer)
    #expect(dashboard.unseenCompletionCount == 0)

    // 承認待ちへ入ると status.didSet でラッチ→observeUnseenCompletion 経由で集計が更新される。
    chat.enterAwaitingApproval(prompt: "Approve?")
    #expect(dashboard.unseenCompletionCount == 1)

    chat.markCompletionSeen()
    #expect(dashboard.unseenCompletionCount == 0)
    #expect(observedCounts == [1, 0])
}

@Test @MainActor
func spawnInProject_autoNamesWithFlowerName() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectFolder = workspaceURL.appendingPathComponent("naming-backend", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(
        dashboard.addProject(name: "Naming Backend", directoryPath: projectFolder.path)
    )
    try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

    #expect(dashboard.sessions[0].projectID == projectID)
    #expect(FlowerNameGenerator.names.contains(dashboard.sessions[0].name))
    #expect(dashboard.sessions[0].name != "Naming Backend")
}

@Test @MainActor
func spawnNewSession_autoNamesWithFlowerName() async throws {
    let ptyManager = MockPTYManager()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()

    #expect(FlowerNameGenerator.names.contains(dashboard.sessions[0].name))
}

@Test @MainActor
func spawnNewSession_assignsUniqueFlowerNames() async throws {
    let ptyManager = MockPTYManager()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    // 既存セッション名を avoiding に渡す配線が壊れると花名が重複し得る。
    // 連番サフィックスに入らない範囲(花名は30個)で複数 spawn し、一意性を担保する。
    for _ in 0..<10 {
        try await dashboard.spawnNewClaudeCodeSession()
    }

    let names = dashboard.sessions.map(\.name)
    #expect(names.allSatisfy { FlowerNameGenerator.names.contains($0) })
    let normalized = Set(names.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
    #expect(normalized.count == names.count)
}

@Test @MainActor
func spawnNewSession_persistsFlowerName() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let name = dashboard.sessions[0].name
    let sessionID = dashboard.sessions[0].id

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.name == name
    }

    let saved = try #require(await sessionStore.load().first { $0.id == sessionID })
    #expect(FlowerNameGenerator.names.contains(saved.name))
}

@Test @MainActor
func customSession_spawnPersistRestoreLaunchAndCompletionDoesNotRequireBuiltinKind() async throws {
    let descriptor = makeCustomAgentDescriptor()
    let catalog = AgentCatalog(customDescriptors: [descriptor])
    let binaryPath = "/opt/homebrew/bin/aider"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let sessionStore = InMemorySessionStore()

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        customAgentBinaryPaths: [descriptor.ref.id: binaryPath],
        agentCatalog: catalog
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(ref: descriptor.ref)

    try await waitUntil { (await sessionStore.load()).contains { $0.id == sessionID } }
    let saved = try #require(await sessionStore.load().first { $0.id == sessionID })
    #expect(saved.agentRef == .custom("aider"))
    #expect(ptyManager.spawnCalls.first?.command == binaryPath)
    #expect(ptyManager.spawnCalls.first?.args == ["--model", "sonnet", "--yes-always"])

    let restoredPTYManager = MockPTYManager()
    let (restoreHookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let restoreEnvironment = makeTestEnvironment(
        pty: restoredPTYManager,
        hookStream: restoreHookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        customAgentBinaryPaths: [descriptor.ref.id: binaryPath],
        agentCatalog: catalog
    )
    let restoredDashboard = DashboardViewModel(environment: restoreEnvironment)
    await restoredDashboard.start()

    try await waitUntil { restoredPTYManager.spawnCalls.count == 1 }
    let restoredCall = try #require(restoredPTYManager.spawnCalls.first)
    #expect(restoredCall.id == sessionID)
    #expect(restoredCall.command == binaryPath)
    #expect(restoredDashboard.sessions.first?.agentRef == .custom("aider"))

    restoredPTYManager.emitExit(for: sessionID, code: 0)

    try await waitUntil { restoredDashboard.sessions.first?.status == .completed(exitCode: 0) }
}

@Test @MainActor
func renameSession_persistsName() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    dashboard.renameSession(sessionID, to: "Backend")

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.name == "Backend"
    }
}

@Test @MainActor
func spawnThenRename_persistsFinalName() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id
    dashboard.renameSession(sessionID, to: "Final Name")

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.name == "Final Name"
    }
    #expect(await sessionStore.load().count == 1)
}

@Test @MainActor
func renameSession_multipleRenamesPersistLastName() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    dashboard.renameSession(sessionID, to: "First")
    dashboard.renameSession(sessionID, to: "Second")
    dashboard.renameSession(sessionID, to: "Last")

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.name == "Last"
    }
    #expect(dashboard.sessions[0].name == "Last")
}

@Test @MainActor
func reorderSession_swapsTwoSessionsAndPersistsOrder() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()
    let initialOrder = dashboard.sessions.map(\.id)

    dashboard.reorderSession(initialOrder[0], with: initialOrder[2])
    let expectedOrder = [initialOrder[2], initialOrder[1], initialOrder[0]]

    #expect(dashboard.sessions.map(\.id) == expectedOrder)
    try await waitUntil {
        await sessionStore.load().map(\.id) == expectedOrder
    }
}

@Test @MainActor
func reorderSession_swapIsSymmetricForReversedArguments() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()
    let initialOrder = dashboard.sessions.map(\.id)

    dashboard.reorderSession(initialOrder[2], with: initialOrder[0])
    let expectedOrder = [initialOrder[2], initialOrder[1], initialOrder[0]]

    #expect(dashboard.sessions.map(\.id) == expectedOrder)
    try await waitUntil {
        await sessionStore.load().map(\.id) == expectedOrder
    }
}

@Test @MainActor
func reorderSession_swapKeepsInterveningSessionsFixed() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()
    let initialOrder = dashboard.sessions.map(\.id)

    // 両端(先頭と末尾)だけを入れ替え、間の2枚は動かないこと。
    // remove+insert(挿入)へ退行すると間がずれるため、その回帰を防ぐ。
    dashboard.reorderSession(initialOrder[3], with: initialOrder[0])
    let expectedOrder = [initialOrder[3], initialOrder[1], initialOrder[2], initialOrder[0]]

    #expect(dashboard.sessions.map(\.id) == expectedOrder)
    try await waitUntil {
        await sessionStore.load().map(\.id) == expectedOrder
    }
}

@Test @MainActor
func restorePersistedSessions_preservesPersistedOrder() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let first = SessionID()
    let second = SessionID()
    let third = SessionID()
    let firstFolder = workspaceURL.appendingPathComponent("first", isDirectory: true)
    let secondFolder = workspaceURL.appendingPathComponent("second", isDirectory: true)
    let thirdFolder = workspaceURL.appendingPathComponent("third", isDirectory: true)
    try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: thirdFolder, withIntermediateDirectories: true)

    let sessionStore = InMemorySessionStore([
        makePersistedSessionDescriptor(id: second, workingDirectory: secondFolder.path, name: "Second"),
        makePersistedSessionDescriptor(id: third, workingDirectory: thirdFolder.path, name: "Third"),
        makePersistedSessionDescriptor(id: first, workingDirectory: firstFolder.path, name: "First"),
    ])

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    #expect(dashboard.sessions.map(\.id) == [second, third, first])
}

@Test @MainActor
func renameSession_emptyNamePersistsAndRestoresShortID() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id
    dashboard.renameSession(sessionID, to: "   ")

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.name == ""
    }

    let restoredPTYManager = MockPTYManager()
    let (restoreHookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let restoreEnvironment = makeTestEnvironment(
        pty: restoredPTYManager,
        hookStream: restoreHookStream,
        sessions: sessionStore
    )
    let restoredDashboard = DashboardViewModel(environment: restoreEnvironment)
    await restoredDashboard.start()

    #expect(restoredDashboard.sessions[0].name == "")
    #expect(restoredDashboard.sessions[0].displayName == SessionViewModel.shortID(for: sessionID))
}

@Test @MainActor
func reorderAndCodexResumeIDPersistWithoutClobberingOrderNameOrResumeID() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let sessionStore = InMemorySessionStore()
    let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(deliveries: deliveryStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.codex: codexPath],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: sessionStore,
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    try await dashboard.spawnNewSession(kind: .codex)
    try await dashboard.spawnNewSession(kind: .codex)
    let initialOrder = dashboard.sessions.map(\.id)
    try await waitUntil { await sessionStore.load().map(\.id) == initialOrder }

    dashboard.renameSession(initialOrder[1], to: "Middle")
    dashboard.reorderSession(initialOrder[2], with: initialOrder[0])

    let nativeID = "019e9177-d565-78e2-95b9-174015ba898e"
    deliveryContinuation.yield(HookDelivery(
        sessionID: initialOrder[1],
        event: .userPromptSubmit(turnId: "turn-1"),
        nativeSessionId: nativeID
    ))

    let expectedOrder = [initialOrder[2], initialOrder[1], initialOrder[0]]
    try await waitUntil {
        let saved = await sessionStore.load()
        return saved.map(\.id) == expectedOrder
            && saved.first(where: { $0.id == initialOrder[1] })?.name == "Middle"
            && saved.first(where: { $0.id == initialOrder[1] })?.resumeID == nativeID
    }
}

@Test @MainActor
func persistSessionWorkspace_preservesCodexSettingsAndAllOtherDescriptorFields() async throws {
    let sessionID = SessionID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
    let projectID = ProjectID(rawValue: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!)
    let parentID = SessionID(rawValue: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!)
    let codexSettings = CodexAppServerSessionSettings(
        selectedModel: "gpt-5-codex",
        selectedEffort: "high",
        selectedPermissionProfile: ":workspace",
        isPlanMode: true
    )
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: "/tmp/old",
        name: "Codex Chat",
        projectID: projectID,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/codex",
        args: ["app-server"],
        env: ["KEY": "VALUE"],
        backend: .appServer,
        codexThreadId: "thread-1",
        chatNativeSessionId: "thread-1",
        appServerUserAgent: "codex-test/1",
        codexSettings: codexSettings,
        token: "token",
        resumeID: "resume-1",
        parentSessionID: parentID,
        launchContext: .orchestration
    )
    let sessionStore = InMemorySessionStore([descriptor])
    let coordinator = SessionPersistenceCoordinator(
        sessionStore: sessionStore,
        projectStore: NoOpProjectStore(),
        logError: { _, _ in }
    )
    let newProjectID = ProjectID(rawValue: UUID(uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd")!)

    coordinator.persistSessionWorkspace(id: sessionID, workingDirectory: "/tmp/new", projectID: newProjectID)

    try await waitUntil {
        await sessionStore.load().first?.workingDirectory == "/tmp/new"
    }
    let saved = try #require(await sessionStore.load().first)
    #expect(saved.id == descriptor.id)
    #expect(saved.agentRef == descriptor.agentRef)
    #expect(saved.name == descriptor.name)
    #expect(saved.projectID == newProjectID)
    #expect(saved.startedAt == descriptor.startedAt)
    #expect(saved.command == descriptor.command)
    #expect(saved.args == descriptor.args)
    #expect(saved.env == descriptor.env)
    #expect(saved.backend == descriptor.backend)
    #expect(saved.codexThreadId == descriptor.codexThreadId)
    #expect(saved.chatNativeSessionId == descriptor.chatNativeSessionId)
    #expect(saved.appServerUserAgent == descriptor.appServerUserAgent)
    #expect(saved.codexSettings == codexSettings)
    #expect(saved.token == descriptor.token)
    #expect(saved.resumeID == descriptor.resumeID)
    #expect(saved.parentSessionID == descriptor.parentSessionID)
    #expect(saved.launchContext == .orchestration)
}

@Test @MainActor
func spawnNewCodexAppServerSessionInjectsTranscriptStore() async throws {
    let ptyManager = MockPTYManager()
    let transcriptStore = RecordingTranscriptStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"],
        transcriptStore: transcriptStore,
        appServerClientFactory: { _, _, _, _, _ in
            EventYieldingStructuredClient()
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
    let chat = try #require(dashboard.sessionNodes.first(where: { $0.id == sessionID })?.appServer)
    try await chat.sendText("hi", submit: true)

    try await waitUntil {
        guard let stored = try? await transcriptStore.loadTranscript(for: sessionID) else { return false }
        return stored.contains { item in
            if case .userMessage(_, "hi", _, _) = item { return true }
            return false
        }
    }
    #expect(ptyManager.spawnCalls.isEmpty)
}

@Test @MainActor
func spawnNewSession_allowsClaudeAndCursorStructuredChatWithoutPTYSpawn() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.cursor: "/usr/local/bin/cursor-agent"]
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let claudeID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    let cursorID = try await dashboard.spawnNewSession(kind: .cursor, backend: .appServer)

    #expect(ptyManager.spawnCalls.isEmpty)
    #expect(dashboard.sessionNodes.count == 2)
    #expect(dashboard.sessionNodes.first(where: { $0.id == claudeID })?.agentRef == .builtin(.claudeCode))
    #expect(dashboard.sessionNodes.first(where: { $0.id == cursorID })?.agentRef == .builtin(.cursor))
    #expect(dashboard.sessionNodes.allSatisfy { $0.appServer != nil })
}

@Test @MainActor
func spawnNewSession_doesNotWriteGuideFiles() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [
            .codex: "/usr/local/bin/codex",
            .cursor: "/usr/local/bin/cursor-agent",
        ]
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    for kind in AgentKind.allCases {
        let sessionID = try await dashboard.spawnNewSession(kind: kind, backend: .pty)
        assertNoGuideFiles(in: environment.sessionWorkspaceDirectory(for: sessionID))
    }

    let claudeChatID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    let cursorChatID = try await dashboard.spawnNewSession(kind: .cursor, backend: .appServer)
    assertNoGuideFiles(in: environment.sessionWorkspaceDirectory(for: claudeChatID))
    assertNoGuideFiles(in: environment.sessionWorkspaceDirectory(for: cursorChatID))
}

// MARK: - spawn 時の backend 継承（チャット親 → チャット子）

// チャット（appServer）セッションから spawn した子は、chat 対応 kind なら appServer で立つ。
@Test @MainActor
func spawnNewSession_fromChatParent_inheritsAppServerBackend() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.cursor: "/usr/local/bin/cursor-agent"]
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let parentID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    // backend 未指定（既定 .pty）でも、親がチャットかつ子が chat 対応(cursor)なので appServer へ昇格。
    let childID = try await dashboard.spawnNewSession(kind: .cursor, from: parentID)

    #expect(dashboard.sessionNode(id: childID)?.appServer != nil)
    #expect(dashboard.sessionNode(id: childID)?.pty == nil)
    #expect(ptyManager.spawnCalls.isEmpty)
}

// ターミナル（pty）親から spawn した子は pty のまま（昇格しない）。
@Test @MainActor
func spawnNewSession_fromTerminalParent_staysPTY() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex", .cursor: "/usr/local/bin/cursor-agent"]
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let parentID = try await dashboard.spawnNewSession(kind: .codex, backend: .pty)
    let childID = try await dashboard.spawnNewSession(kind: .cursor, from: parentID)

    #expect(dashboard.sessionNode(id: childID)?.pty != nil)
    #expect(dashboard.sessionNode(id: childID)?.appServer == nil)
}

// 親なし（from=nil、UI 起動等）は要求どおりの backend（既定 pty）で不変。
@Test @MainActor
func spawnNewSession_withoutParent_usesRequestedBackend() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let childID = try await dashboard.spawnNewSession(kind: .codex) // from=nil, 既定 .pty

    #expect(dashboard.sessionNode(id: childID)?.pty != nil)
    #expect(dashboard.sessionNode(id: childID)?.appServer == nil)
}

@Test @MainActor
func cursorAppServerSession_persistsNativeSessionIDAndRestoresWithIt() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()
    let spawnClient = CountingResumeStructuredClient()
    let restoreClient = CountingResumeStructuredClient()
    let clients = StructuredClientSequence([spawnClient, restoreClient])
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        agentBinaryPaths: [.cursor: "/bin/echo"],
        appServerClientFactory: { _, _, _, _, _ in
            try clients.next()
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .cursor, backend: .appServer)
    try await waitUntil {
        await sessionStore.load().contains { $0.id == sessionID }
    }
    spawnClient.yield(.turnCompleted(nativeSessionId: "cursor-native-after-turn"))

    try await waitUntil {
        await sessionStore.load()
            .first(where: { $0.id == sessionID })?
            .chatNativeSessionId == "cursor-native-after-turn"
    }
    let saved = try #require(await sessionStore.load().first { $0.id == sessionID })
    #expect(saved.resumeID == "create-chat")
    #expect(saved.chatNativeSessionId == "cursor-native-after-turn")

    let restoredDashboard = DashboardViewModel(environment: environment)
    await restoredDashboard.start()

    try await waitUntil {
        restoreClient.resumes == ["cursor-native-after-turn"]
    }
    let restored = try #require(restoredDashboard.sessionNodes.first { $0.id == sessionID }?.appServer)
    #expect(restored.chatNativeSessionId == "cursor-native-after-turn")
}

@Test @MainActor
func persistChatNativeSessionID_ignoresNonCursorDescriptors() async throws {
    let claudeID = SessionID()
    let codexID = SessionID()
    let descriptors = [
        PersistedSessionDescriptor(
            id: claudeID,
            kind: .claudeCode,
            workingDirectory: "/tmp/claude",
            name: "Claude",
            projectID: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            command: "/usr/local/bin/claude",
            args: [],
            env: [:],
            backend: .appServer,
            token: "claude-token",
            resumeID: claudeID.rawValue.uuidString.lowercased()
        ),
        PersistedSessionDescriptor(
            id: codexID,
            kind: .codex,
            workingDirectory: "/tmp/codex",
            name: "Codex",
            projectID: nil,
            startedAt: Date(timeIntervalSince1970: 1_700_000_001),
            command: "/usr/local/bin/codex",
            args: [],
            env: [:],
            backend: .appServer,
            token: "codex-token",
            resumeID: "codex-resume"
        ),
    ]
    let sessionStore = InMemorySessionStore(descriptors)
    let coordinator = SessionPersistenceCoordinator(
        sessionStore: sessionStore,
        projectStore: NoOpProjectStore(),
        logError: { _, _ in }
    )

    descriptors.forEach { coordinator.persistSession($0) }
    coordinator.persistChatNativeSessionID(sessionID: claudeID, nativeSessionId: "claude-native-after-turn")
    coordinator.persistChatNativeSessionID(sessionID: codexID, nativeSessionId: "codex-native-after-turn")
    coordinator.persistSessionName(id: claudeID, name: "Claude Renamed")
    coordinator.persistSessionName(id: codexID, name: "Codex Renamed")

    try await waitUntil {
        let saved = await sessionStore.load()
        return saved.first(where: { $0.id == claudeID })?.name == "Claude Renamed"
            && saved.first(where: { $0.id == codexID })?.name == "Codex Renamed"
    }
    let saved = await sessionStore.load()
    let claude = try #require(saved.first { $0.id == claudeID })
    let codex = try #require(saved.first { $0.id == codexID })
    #expect(claude.chatNativeSessionId == nil)
    #expect(claude.resumeID == claudeID.rawValue.uuidString.lowercased())
    #expect(codex.chatNativeSessionId == nil)
    #expect(codex.resumeID == "codex-resume")
}

@Test @MainActor
func cursorAppServerSessionWithNilChatNativeSessionID_restoresWithResumeID() async throws {
    let sessionID = SessionID()
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .cursor,
        workingDirectory: "/tmp/cursor",
        name: "Cursor",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/cursor-agent",
        args: [],
        env: [:],
        backend: .appServer,
        token: "cursor-token",
        resumeID: "cursor-create-chat"
    )
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore([descriptor])
    let restoreClient = CountingResumeStructuredClient()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        agentBinaryPaths: [.cursor: "/bin/echo"],
        appServerClientFactory: { _, _, _, _, _ in restoreClient }
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await waitUntil {
        restoreClient.resumes == ["cursor-create-chat"]
    }
    let restored = try #require(dashboard.sessionNodes.first { $0.id == sessionID }?.appServer)
    #expect(restored.chatNativeSessionId == "cursor-create-chat")
}

@Test @MainActor
func claudeAppServerNativeSessionIDChange_restoresWithResumeID() async throws {
    let ptyManager = MockPTYManager()
    let sessionStore = InMemorySessionStore()
    let spawnClient = CountingResumeStructuredClient()
    let restoreClient = CountingResumeStructuredClient()
    let clients = StructuredClientSequence([spawnClient, restoreClient])
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        agentBinaryPaths: [.claudeCode: "/bin/echo"],
        appServerClientFactory: { _, _, _, _, _ in
            try clients.next()
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    let resumeID = sessionID.rawValue.uuidString.lowercased()
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == resumeID
    }
    spawnClient.yield(.turnCompleted(nativeSessionId: "claude-native-after-turn"))
    try await Task.sleep(for: .milliseconds(100))

    let saved = try #require(await sessionStore.load().first { $0.id == sessionID })
    #expect(saved.resumeID == resumeID)
    #expect(saved.chatNativeSessionId == nil)

    let restoredDashboard = DashboardViewModel(environment: environment)
    await restoredDashboard.start()

    try await waitUntil {
        restoreClient.resumes == [resumeID]
    }
}

@Test @MainActor
func renameSession_trimsWhitespace() async throws {
    let ptyManager = MockPTYManager()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    dashboard.renameSession(sessionID, to: "   Backend   ")
    #expect(dashboard.sessions[0].name == "Backend")

    dashboard.renameSession(sessionID, to: "   ")
    #expect(dashboard.sessions[0].name == "")
}

@Test @MainActor
func spawnNewClaudeCodeSession_passesSessionIDAndHookURLToEnv() async throws {
    let ptyManager = MockPTYManager()
    let hookURL = URL(string: "http://127.0.0.1:54321/hook")!
    let settingsURL = URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json")
    let claudePath = "/usr/local/bin/claude"
    let pathEnv = "/usr/local/bin:/usr/bin:/bin"

    let workspaceURL = URL(fileURLWithPath: "/tmp/agent-dashboard-test-workspace")
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: hookURL,
        claudeSettingsURL: settingsURL,
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: claudePath,
        pathEnvironment: pathEnv,
        workspaceDirectory: workspaceURL,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    // eager spawn: View を待たず即 spawn。
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let vm = dashboard.sessions[0]
    let calls = ptyManager.spawnCalls
    #expect(calls.count == 1)
    let call = try #require(calls.first)

    let spawnedID = try #require(call.id)
    #expect(vm.id == spawnedID)

    // claude を直接 spawn（login shell を経由しない）
    #expect(call.command == claudePath)
    #expect(call.args == [
        "--settings",
        settingsURL.path,
        "--session-id",
        spawnedID.rawValue.uuidString.lowercased(),
    ])

    // 子プロセスへの環境変数で SessionID と HookURL を渡す
    #expect(call.env["PHLOX_SESSION_ID"] == spawnedID.rawValue.uuidString)
    #expect(call.env["CLAUDE_HOOKS_URL"] == hookURL.absoluteString)
    #expect(call.env["TERM"] == "xterm-256color")
    #expect(call.env["PATH"] == pathEnv)

    // 既定 winsize で eager 起動（正の値）。View 出現後の確定サイズは resize で反映する。
    let size = try #require(call.initialSize)
    #expect(size.cols > 0)
    #expect(size.rows > 0)

    // CWD が AppSupport ワークスペース配下のセッション専用ディレクトリに明示されている。
    #expect(call.workingDirectory == environment.sessionWorkspaceDirectory(for: spawnedID).path)

    // View 出現後の sizeChanged は spawn ではなく resize として実サイズへ反映される。
    vm.terminalCoordinator.onResize(120, 40)
    try await waitUntil { ptyManager.resizeCalls.contains { $0.cols == 120 && $0.rows == 40 } }
    #expect(ptyManager.spawnCalls.count == 1)
}

@Test @MainActor
func spawnNewClaudeCodeSession_eagerSpawnThenResizesOnSizeChanged() async throws {
    let ptyManager = MockPTYManager()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    try await dashboard.spawnNewClaudeCodeSession()

    // eager spawn 済み。
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let vm = dashboard.sessions[0]
    // View 出現後の sizeChanged は spawn ではなく resize として反映される。
    vm.terminalCoordinator.onResize(100, 30)
    try await waitUntil { ptyManager.resizeCalls.contains { $0.cols == 100 && $0.rows == 30 } }

    vm.terminalCoordinator.onResize(120, 35)
    try await waitUntil { ptyManager.resizeCalls.contains { $0.cols == 120 && $0.rows == 35 } }

    // 追加 spawn は起きない（spawn は eager の 1 回のみ）。
    #expect(ptyManager.spawnCalls.count == 1)
    let last = try #require(ptyManager.resizeCalls.last)
    #expect(last.id == vm.id)
    #expect(last.cols == 120)
    #expect(last.rows == 35)
}

@Test @MainActor
func hookMultiplex_routesEventToCorrectSession() async throws {
    let ptyManager = MockPTYManager()

    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    // 2 つのセッションを spawn（DashboardViewModel が内部で SessionID を生成して spawn に渡す）
    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()

    #expect(dashboard.sessions.count == 2)
    let vmA = dashboard.sessions[0]
    let vmB = dashboard.sessions[1]
    let idA = vmA.id
    let idB = vmB.id
    #expect(idA != idB)

    // セッション A に approval イベントを送信
    hookContinuation.yield((idA, .notification(message: "Allow this?")))

    // hook の伝播を待つ（ポーリング）
    for _ in 0..<30 {
        if case .awaitingApproval = vmA.status { break }
        try await Task.sleep(for: .milliseconds(20))
    }

    // A だけが承認待ち、B は影響を受けない
    if case .awaitingApproval = vmA.status {} else {
        Issue.record("vmA should be awaitingApproval but is \(vmA.status)")
    }
    if case .starting = vmB.status {} else if case .idle = vmB.status {} else if case .running = vmB.status {} else {
        Issue.record("vmB should remain in starting/idle/running but is \(vmB.status)")
    }

    // セッション B: Stop フックは idle へ戻し、PTY 終了で completed
    hookContinuation.yield((idB, .stop(turnId: nil)))
    // フック伝播を固定 sleep でなくポーリングで待つ（vmA と同じ決定的待機。実時計依存の除去）。
    try await waitUntil {
        if case .idle = vmB.status { return true }
        return false
    }
    if case .idle = vmB.status {} else {
        Issue.record("vmB should become idle after stop hook but is \(vmB.status)")
    }

    // initialSpawnDebounce(150ms) があるため、onResize 直後に emitExit すると
    // exitContinuations[idB] 未登録で yield が捨てられる。spawn 完了を待ってから
    // exit を発火する。
    vmB.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.contains(where: { $0.id == idB }) }

    ptyManager.emitExit(for: idB, code: 0)
    for _ in 0..<30 {
        if case .completed = vmB.status { break }
        try await Task.sleep(for: .milliseconds(20))
    }
    if case .completed(let code) = vmB.status {
        #expect(code == 0)
    } else {
        Issue.record("vmB should be completed after PTY exit but is \(vmB.status)")
    }

    // A は承認待ちのまま
    if case .awaitingApproval = vmA.status {} else {
        Issue.record("vmA should still be awaitingApproval but is \(vmA.status)")
    }
}

@Test @MainActor
func spawnNewSession_codex_usesCodexBinaryAndHookURLWithoutSettings() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let dispatcherPath = "/tmp/agent-dashboard-test-dispatcher.sh"

    let hookURL = URL(string: "http://127.0.0.1:8080/hook")!
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: hookURL,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: dispatcherPath,
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.codex: codexPath],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    #expect(dashboard.sessions.count == 1)
    let sessionID = dashboard.sessions[0].id
    #expect(dashboard.sessions[0].agentKind == .codex)

    let sessionWorkspaceURL = environment.sessionWorkspaceDirectory(for: sessionID)
    let hooksURL = CodexHooksManager.hooksFileURL(in: sessionWorkspaceURL)
    #expect(FileManager.default.fileExists(atPath: hooksURL.path))

    let hooksData = try Data(contentsOf: hooksURL)
    let hooksJSON = try JSONSerialization.jsonObject(with: hooksData) as? [String: Any]
    let hooks = try #require(hooksJSON?["hooks"] as? [String: Any])
    let stopEntries = try #require(hooks["Stop"] as? [[String: Any]])
    let stopHooks = try #require(stopEntries.first?["hooks"] as? [[String: Any]])
    let stopCommand = try #require(stopHooks.first?["command"] as? String)
    #expect(stopCommand == "'\(dispatcherPath)' stop")
    #expect(!stopCommand.contains("PHLOX_SESSION_ID="))
    #expect(!stopCommand.contains("CLAUDE_HOOKS_URL="))

    dashboard.sessions[0].terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let call = try #require(ptyManager.spawnCalls.first)
    #expect(call.command == codexPath)
    #expect(call.args == ["--dangerously-bypass-approvals-and-sandbox", "--dangerously-bypass-hook-trust"])
    #expect(call.workingDirectory == sessionWorkspaceURL.path)
    #expect(call.env["PHLOX_SESSION_ID"] != nil)
    #expect(call.env["CLAUDE_HOOKS_URL"] == hookURL.absoluteString)
    #expect(!call.args.contains("--settings"))

    await dashboard.removeSession(sessionID)
    #expect(!FileManager.default.fileExists(atPath: hooksURL.path))
}

@Test @MainActor
func spawnNewSession_codex_userHooksEnabled_skipsSessionHooksAndHookTrustBypass() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.codex: codexPath],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(
        environment: environment,
        codexUserHooksEnabledProvider: { true }
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    #expect(dashboard.sessions.count == 1)
    let sessionID = dashboard.sessions[0].id
    let sessionWorkspaceURL = environment.sessionWorkspaceDirectory(for: sessionID)
    let hooksURL = CodexHooksManager.hooksFileURL(in: sessionWorkspaceURL)
    #expect(!FileManager.default.fileExists(atPath: hooksURL.path))

    dashboard.sessions[0].terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let call = try #require(ptyManager.spawnCalls.first)
    #expect(call.command == codexPath)
    #expect(call.args == ["--dangerously-bypass-approvals-and-sandbox"])
    #expect(call.workingDirectory == sessionWorkspaceURL.path)
    #expect(call.env["PHLOX_SESSION_ID"] != nil)
    #expect(call.env["CLAUDE_HOOKS_URL"] == environment.hookURL.absoluteString)

    await dashboard.removeSession(sessionID)
}

@Test @MainActor
func codexHookNativeSessionId_persistsResumeIDOnce() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let sessionStore = InMemorySessionStore()
    let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(deliveries: deliveryStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.codex: codexPath],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: sessionStore,
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let sessionID = try #require(dashboard.sessions.first?.id)
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == nil
    }

    let nativeID = "019e9177-d565-78e2-95b9-174015ba898e"
    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .userPromptSubmit(turnId: "turn-1"),
        nativeSessionId: nativeID
    ))

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == nativeID
    }

    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .stop(turnId: "turn-1"),
        nativeSessionId: "different-native-id"
    ))
    try await Task.sleep(for: .milliseconds(50))

    let saved = await sessionStore.load().first { $0.id == sessionID }
    #expect(saved?.resumeID == nativeID)
}

@MainActor
private func makeClaudeCodeDeliveryTestEnvironment(
    ptyManager: MockPTYManager,
    sessionStore: InMemorySessionStore,
    deliveryStream: AsyncStream<HookDelivery>,
    workspaceURL: URL
) -> AppEnvironment {
    let claudePath = "/usr/local/bin/claude"
    return AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(deliveries: deliveryStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: claudePath,
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.claudeCode: claudePath],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: sessionStore,
        cliPath: "/tmp/agent-dashboard-test-cli"
    )
}

@Test @MainActor
func claudeCodeHookNativeSessionId_followsResumeIDOnChange() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let sessionStore = InMemorySessionStore()
    let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
    let environment = makeClaudeCodeDeliveryTestEnvironment(
        ptyManager: ptyManager,
        sessionStore: sessionStore,
        deliveryStream: deliveryStream,
        workspaceURL: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = try #require(dashboard.sessions.first?.id)
    let launchUUID = sessionID.rawValue.uuidString.lowercased()

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == launchUUID
    }

    let newID1 = "11111111-1111-1111-1111-111111111111"
    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .userPromptSubmit(turnId: "turn-1"),
        nativeSessionId: newID1
    ))
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == newID1
    }

    let newID2 = "22222222-2222-2222-2222-222222222222"
    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .stop(turnId: "turn-1"),
        nativeSessionId: newID2
    ))
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == newID2
    }
}

@Test @MainActor
func claudeCodeHookNativeSessionId_noOpWhenMatchesLaunchUUID() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let sessionStore = InMemorySessionStore()
    let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
    let environment = makeClaudeCodeDeliveryTestEnvironment(
        ptyManager: ptyManager,
        sessionStore: sessionStore,
        deliveryStream: deliveryStream,
        workspaceURL: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = try #require(dashboard.sessions.first?.id)
    let launchUUID = sessionID.rawValue.uuidString.lowercased()

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == launchUUID
    }
    let savesBeforeHook = await sessionStore.saveCount

    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .userPromptSubmit(turnId: "turn-1"),
        nativeSessionId: launchUUID
    ))
    try await Task.sleep(for: .milliseconds(50))

    let saved = await sessionStore.load().first { $0.id == sessionID }
    #expect(saved?.resumeID == launchUUID)
    #expect(await sessionStore.saveCount == savesBeforeHook)
}

@Test @MainActor
func claudeCodeHookNativeSessionId_ignoresInvalidNativeSessionId() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let sessionStore = InMemorySessionStore()
    let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
    let environment = makeClaudeCodeDeliveryTestEnvironment(
        ptyManager: ptyManager,
        sessionStore: sessionStore,
        deliveryStream: deliveryStream,
        workspaceURL: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = try #require(dashboard.sessions.first?.id)
    let launchUUID = sessionID.rawValue.uuidString.lowercased()

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == launchUUID
    }
    let savesBeforeHook = await sessionStore.saveCount

    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .userPromptSubmit(turnId: "turn-1"),
        nativeSessionId: ""
    ))
    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .stop(turnId: "turn-1"),
        nativeSessionId: "not-a-valid-uuid"
    ))
    try await Task.sleep(for: .milliseconds(50))

    let saved = await sessionStore.load().first { $0.id == sessionID }
    #expect(saved?.resumeID == launchUUID)
    #expect(await sessionStore.saveCount == savesBeforeHook)
}

@Test @MainActor
func claudeCodeHookNativeSessionId_noOpWhenNormalizedUUIDMatches() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let sessionStore = InMemorySessionStore()
    let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
    let environment = makeClaudeCodeDeliveryTestEnvironment(
        ptyManager: ptyManager,
        sessionStore: sessionStore,
        deliveryStream: deliveryStream,
        workspaceURL: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = try #require(dashboard.sessions.first?.id)
    let launchUUID = sessionID.rawValue.uuidString.lowercased()

    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == launchUUID
    }
    let savesBeforeHook = await sessionStore.saveCount

    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .userPromptSubmit(turnId: "turn-1"),
        nativeSessionId: launchUUID.uppercased()
    ))
    try await Task.sleep(for: .milliseconds(50))

    let saved = await sessionStore.load().first { $0.id == sessionID }
    #expect(saved?.resumeID == launchUUID)
    #expect(await sessionStore.saveCount == savesBeforeHook)
}

@Test @MainActor
func claudeCodeHookNativeSessionId_restoreUsesFollowedResumeID() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let sessionStore = InMemorySessionStore()
    let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
    let environment = makeClaudeCodeDeliveryTestEnvironment(
        ptyManager: ptyManager,
        sessionStore: sessionStore,
        deliveryStream: deliveryStream,
        workspaceURL: workspaceURL
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = try #require(dashboard.sessions.first?.id)

    let followedResumeID = "44444444-4444-4444-4444-444444444444"
    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .userPromptSubmit(turnId: "turn-1"),
        nativeSessionId: followedResumeID
    ))
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == followedResumeID
    }

    let restoredPTYManager = MockPTYManager()
    let (restoreDeliveryStream, _) = AsyncStream<HookDelivery>.makeStream()
    let restoreEnvironment = makeClaudeCodeDeliveryTestEnvironment(
        ptyManager: restoredPTYManager,
        sessionStore: sessionStore,
        deliveryStream: restoreDeliveryStream,
        workspaceURL: workspaceURL
    )
    let restoredDashboard = DashboardViewModel(environment: restoreEnvironment)
    await restoredDashboard.start()

    try await waitUntil { restoredPTYManager.spawnCalls.count == 1 }
    let restoredCall = try #require(restoredPTYManager.spawnCalls.first)
    #expect(restoredCall.id == sessionID)
    #expect(restoredCall.args.contains("--resume"))
    #expect(restoredCall.args.contains(followedResumeID))
    #expect(!restoredCall.args.contains("--session-id"))
}

private func makeTemporaryCodexHomeForDashboardTests() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-codex-vm-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func cleanupTemporaryCodexHomeForDashboardTests(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func fixedDateForDashboardTests(_ date: Date) -> @Sendable () -> Date {
    { date }
}

private func codexRolloutISOTimestamp(for date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func writeCodexRolloutForDashboardTests(
    codexHome: URL,
    date: Date,
    sessionID: String,
    cwd: String,
    timestamp: Date
) throws {
    let dayDirectory = CodexSessionDiscovery.dayDirectory(
        for: date,
        under: codexHome.appendingPathComponent("sessions", isDirectory: true)
    )
    try FileManager.default.createDirectory(at: dayDirectory, withIntermediateDirectories: true)
    let filenameTimestamp = codexRolloutISOTimestamp(for: timestamp).replacingOccurrences(of: ":", with: "-")
    let filename = "rollout-\(filenameTimestamp)-\(sessionID.lowercased()).jsonl"
    let line = """
    {"type":"session_meta","payload":{"id":"\(sessionID)","cwd":"\(cwd)","timestamp":"\(codexRolloutISOTimestamp(for: timestamp))"}}
    """
    try line.write(to: dayDirectory.appendingPathComponent(filename), atomically: true, encoding: .utf8)
}

@Test @MainActor
func codexRolloutDiscovery_persistsResumeIDAfterSpawn() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForDashboardTests()
    defer { cleanupTemporaryCodexHomeForDashboardTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let spawnTime = Date(timeIntervalSince1970: 1_740_000_100)
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        codexHome: codexHome,
        agentBinaryPaths: [.codex: codexPath]
    )

    let dashboard = DashboardViewModel(
        environment: environment,
        codexDiscoveryRetryInterval: .milliseconds(50),
        codexDiscoveryMaxRetryDuration: .seconds(2),
        codexDiscoveryNow: fixedDateForDashboardTests(spawnTime)
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let sessionID = try #require(dashboard.sessions.first?.id)
    let workingDirectory = environment.sessionWorkspaceDirectory(for: sessionID).path

    let nativeID = "55555555-5555-5555-5555-555555555555"
    try writeCodexRolloutForDashboardTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: nativeID,
        cwd: workingDirectory,
        timestamp: spawnTime
    )

    try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == nativeID
    }
}

@Test @MainActor
func codexRolloutDiscovery_doesNotOverwriteHookPersistedResumeID() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForDashboardTests()
    defer { cleanupTemporaryCodexHomeForDashboardTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
    let spawnTime = Date(timeIntervalSince1970: 1_740_000_200)
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(deliveries: deliveryStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        codexHome: codexHome,
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.codex: codexPath],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: sessionStore,
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(
        environment: environment,
        codexDiscoveryRetryInterval: .milliseconds(50),
        codexDiscoveryMaxRetryDuration: .seconds(2),
        codexDiscoveryNow: fixedDateForDashboardTests(spawnTime)
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let sessionID = try #require(dashboard.sessions.first?.id)
    let workingDirectory = environment.sessionWorkspaceDirectory(for: sessionID).path

    let hookNativeID = "66666666-6666-6666-6666-666666666666"
    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .userPromptSubmit(turnId: "turn-1"),
        nativeSessionId: hookNativeID
    ))
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == hookNativeID
    }

    try writeCodexRolloutForDashboardTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: "77777777-7777-7777-7777-777777777777",
        cwd: workingDirectory,
        timestamp: spawnTime
    )
    try await Task.sleep(for: .milliseconds(200))

    let saved = await sessionStore.load().first { $0.id == sessionID }
    #expect(saved?.resumeID == hookNativeID)
}

@Test @MainActor
func codexRolloutDiscovery_skipsPersistWhenSessionRemoved() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForDashboardTests()
    defer { cleanupTemporaryCodexHomeForDashboardTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let spawnTime = Date(timeIntervalSince1970: 1_740_000_300)
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        codexHome: codexHome,
        agentBinaryPaths: [.codex: codexPath]
    )

    let dashboard = DashboardViewModel(
        environment: environment,
        codexDiscoveryRetryInterval: .milliseconds(50),
        codexDiscoveryMaxRetryDuration: .seconds(2),
        codexDiscoveryNow: fixedDateForDashboardTests(spawnTime)
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let sessionID = try #require(dashboard.sessions.first?.id)
    let workingDirectory = environment.sessionWorkspaceDirectory(for: sessionID).path
    await dashboard.removeSession(sessionID)

    let nativeID = "88888888-8888-8888-8888-888888888888"
    try writeCodexRolloutForDashboardTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: nativeID,
        cwd: workingDirectory,
        timestamp: spawnTime
    )
    // 削除の enqueue を確定的にドレインしてから検証する（任意 sleep の実時計依存を排除）。
    // 削除済みセッションは firstIndex ガードで再永続化されないため、ドレイン後の状態が最終状態。
    await dashboard.waitForPendingPersistenceWritesForTesting()

    #expect(await sessionStore.load().contains(where: { $0.id == sessionID }) == false)
}

@Test @MainActor
func codexRolloutDiscovery_retriesAfterFirstInputWhenRolloutAppearsLate() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForDashboardTests()
    defer { cleanupTemporaryCodexHomeForDashboardTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let spawnTime = Date(timeIntervalSince1970: 1_740_000_350)
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        codexHome: codexHome,
        agentBinaryPaths: [.codex: codexPath]
    )

    let dashboard = DashboardViewModel(
        environment: environment,
        codexDiscoveryRetryInterval: .milliseconds(50),
        codexDiscoveryMaxRetryDuration: .milliseconds(150),
        codexDiscoveryNow: fixedDateForDashboardTests(spawnTime)
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let session = try #require(dashboard.sessions.first)
    let sessionID = session.id
    let workingDirectory = environment.sessionWorkspaceDirectory(for: sessionID).path

    try await waitUntil {
        dashboard.codexDiscoveryTaskCountForTesting == 0
    }

    session.markInputSubmitted()
    try await waitUntil {
        dashboard.codexDiscoveryTaskCountForTesting == 1
    }

    let nativeID = "12121212-1212-1212-1212-121212121212"
    try writeCodexRolloutForDashboardTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: nativeID,
        cwd: workingDirectory,
        timestamp: spawnTime
    )

    try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == nativeID
    }
}

@Test @MainActor
func codexRolloutDiscovery_inputRetriggerDoesNotStartMultipleTasks() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForDashboardTests()
    defer { cleanupTemporaryCodexHomeForDashboardTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let spawnTime = Date(timeIntervalSince1970: 1_740_000_360)
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        codexHome: codexHome,
        agentBinaryPaths: [.codex: codexPath]
    )

    let dashboard = DashboardViewModel(
        environment: environment,
        codexDiscoveryRetryInterval: .milliseconds(50),
        codexDiscoveryMaxRetryDuration: .milliseconds(500),
        codexDiscoveryNow: fixedDateForDashboardTests(spawnTime)
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let session = try #require(dashboard.sessions.first)
    let sessionID = session.id
    let workingDirectory = environment.sessionWorkspaceDirectory(for: sessionID).path

    try await waitUntil {
        dashboard.codexDiscoveryTaskCountForTesting == 1
    }
    session.markInputSubmitted()
    session.markInputSubmitted()
    session.markInputSubmitted()
    #expect(dashboard.codexDiscoveryTaskCountForTesting == 1)

    let nativeID = "34343434-3434-3434-3434-343434343434"
    try writeCodexRolloutForDashboardTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: nativeID,
        cwd: workingDirectory,
        timestamp: spawnTime
    )

    try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == nativeID
    }
}

@Test @MainActor
func codexRolloutDiscovery_removedSessionClearsInputRetrigger() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForDashboardTests()
    defer { cleanupTemporaryCodexHomeForDashboardTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let spawnTime = Date(timeIntervalSince1970: 1_740_000_370)
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        codexHome: codexHome,
        agentBinaryPaths: [.codex: codexPath]
    )

    let dashboard = DashboardViewModel(
        environment: environment,
        codexDiscoveryRetryInterval: .milliseconds(50),
        codexDiscoveryMaxRetryDuration: .milliseconds(150),
        codexDiscoveryNow: fixedDateForDashboardTests(spawnTime)
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let session = try #require(dashboard.sessions.first)
    let sessionID = session.id
    let workingDirectory = environment.sessionWorkspaceDirectory(for: sessionID).path

    try await waitUntil {
        dashboard.codexDiscoveryTaskCountForTesting == 0
    }
    await dashboard.removeSession(sessionID)

    try writeCodexRolloutForDashboardTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: "56565656-5656-5656-5656-565656565656",
        cwd: workingDirectory,
        timestamp: spawnTime
    )
    session.markInputSubmitted()
    try await Task.sleep(for: .milliseconds(200))

    #expect(dashboard.codexDiscoveryTaskCountForTesting == 0)
    #expect(await sessionStore.load().contains(where: { $0.id == sessionID }) == false)
}

@Test @MainActor
func codexRolloutDiscovery_inputRetriggerDoesNotOverwriteHookResumeID() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForDashboardTests()
    defer { cleanupTemporaryCodexHomeForDashboardTests(codexHome) }

    let sessionStore = InMemorySessionStore()
    let (deliveryStream, deliveryContinuation) = AsyncStream<HookDelivery>.makeStream()
    let spawnTime = Date(timeIntervalSince1970: 1_740_000_380)
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(deliveries: deliveryStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        codexHome: codexHome,
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.codex: codexPath],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: sessionStore,
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(
        environment: environment,
        codexDiscoveryRetryInterval: .milliseconds(50),
        codexDiscoveryMaxRetryDuration: .milliseconds(500),
        codexDiscoveryNow: fixedDateForDashboardTests(spawnTime)
    )
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    let session = try #require(dashboard.sessions.first)
    let sessionID = session.id
    let workingDirectory = environment.sessionWorkspaceDirectory(for: sessionID).path

    let hookNativeID = "78787878-7878-7878-7878-787878787878"
    deliveryContinuation.yield(HookDelivery(
        sessionID: sessionID,
        event: .userPromptSubmit(turnId: "turn-1"),
        nativeSessionId: hookNativeID
    ))
    try await waitUntil {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == hookNativeID
    }
    try await waitUntil {
        dashboard.codexDiscoveryTaskCountForTesting == 0
    }

    try writeCodexRolloutForDashboardTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: "90909090-9090-9090-9090-909090909090",
        cwd: workingDirectory,
        timestamp: spawnTime
    )
    session.markInputSubmitted()
    try await Task.sleep(for: .milliseconds(200))

    let saved = await sessionStore.load().first { $0.id == sessionID }
    #expect(saved?.resumeID == hookNativeID)
    #expect(dashboard.codexDiscoveryTaskCountForTesting == 0)
}

@Test @MainActor
func restoreSession_codexWithoutResumeID_runsRolloutDiscovery() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
    let codexHome = try makeTemporaryCodexHomeForDashboardTests()
    defer { cleanupTemporaryCodexHomeForDashboardTests(codexHome) }

    let sessionID = SessionID()
    let workingDirectory = workspaceURL
        .appendingPathComponent(sessionID.rawValue.uuidString, isDirectory: true)
        .path
    try FileManager.default.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)

    let spawnTime = Date(timeIntervalSince1970: 1_740_000_400)
    let sessionStore = InMemorySessionStore([
        makePersistedSessionDescriptor(
            id: sessionID,
            kind: .codex,
            workingDirectory: workingDirectory,
            startedAt: spawnTime
        )
    ])

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        codexHome: codexHome,
        agentBinaryPaths: [.codex: codexPath]
    )

    let dashboard = DashboardViewModel(
        environment: environment,
        codexDiscoveryRetryInterval: .milliseconds(50),
        codexDiscoveryMaxRetryDuration: .seconds(2),
        codexDiscoveryNow: fixedDateForDashboardTests(spawnTime)
    )
    await dashboard.start()

    let nativeID = "99999999-9999-9999-9999-999999999999"
    try writeCodexRolloutForDashboardTests(
        codexHome: codexHome,
        date: spawnTime,
        sessionID: nativeID,
        cwd: workingDirectory,
        timestamp: spawnTime
    )

    try await waitUntil(timeoutNanoseconds: 2_000_000_000) {
        await sessionStore.load().first(where: { $0.id == sessionID })?.resumeID == nativeID
    }
}

@Test @MainActor
func spawnNewSession_codex_installsHooksInSeparatePerSessionDirectories() async throws {
    let ptyManager = MockPTYManager()
    let codexPath = "/usr/local/bin/codex"
    let dispatcherPath = "/tmp/agent-dashboard-test-dispatcher.sh"
    let hookURL = URL(string: "http://127.0.0.1:8080/hook")!
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: hookURL,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: dispatcherPath,
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.codex: codexPath],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .codex)
    try await dashboard.spawnNewSession(kind: .codex)

    let firstID = dashboard.sessions[0].id
    let secondID = dashboard.sessions[1].id
    #expect(firstID != secondID)

    let firstWorkspace = environment.sessionWorkspaceDirectory(for: firstID)
    let secondWorkspace = environment.sessionWorkspaceDirectory(for: secondID)
    #expect(firstWorkspace != secondWorkspace)

    let firstHooksURL = CodexHooksManager.hooksFileURL(in: firstWorkspace)
    let secondHooksURL = CodexHooksManager.hooksFileURL(in: secondWorkspace)
    #expect(FileManager.default.fileExists(atPath: firstHooksURL.path))
    #expect(FileManager.default.fileExists(atPath: secondHooksURL.path))
    #expect(!FileManager.default.fileExists(atPath: CodexHooksManager.hooksFileURL(in: workspaceURL).path))

    let firstHooksData = try Data(contentsOf: firstHooksURL)
    let secondHooksData = try Data(contentsOf: secondHooksURL)
    let firstHooksJSON = try JSONSerialization.jsonObject(with: firstHooksData) as? [String: Any]
    let secondHooksJSON = try JSONSerialization.jsonObject(with: secondHooksData) as? [String: Any]
    let firstHooks = try #require(firstHooksJSON?["hooks"] as? [String: Any])
    let secondHooks = try #require(secondHooksJSON?["hooks"] as? [String: Any])
    let firstStopEntries = try #require(firstHooks["Stop"] as? [[String: Any]])
    let secondStopEntries = try #require(secondHooks["Stop"] as? [[String: Any]])
    let firstStopHooks = try #require(firstStopEntries.first?["hooks"] as? [[String: Any]])
    let secondStopHooks = try #require(secondStopEntries.first?["hooks"] as? [[String: Any]])
    let firstStopCommand = try #require(firstStopHooks.first?["command"] as? String)
    let secondStopCommand = try #require(secondStopHooks.first?["command"] as? String)

    #expect(firstStopCommand == "'\(dispatcherPath)' stop")
    #expect(secondStopCommand == "'\(dispatcherPath)' stop")
    #expect(!firstStopCommand.contains("PHLOX_SESSION_ID="))
    #expect(!secondStopCommand.contains("PHLOX_SESSION_ID="))
}

@Test @MainActor
func removeSession_removesOwnedPerSessionWorkspaceDirectory() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id
    let sessionWorkspaceURL = environment.sessionWorkspaceDirectory(for: sessionID)
    #expect(FileManager.default.fileExists(atPath: sessionWorkspaceURL.path))

    let artifactURL = sessionWorkspaceURL.appendingPathComponent("artifact.txt")
    try Data("session output".utf8).write(to: artifactURL)
    #expect(FileManager.default.fileExists(atPath: artifactURL.path))

    await dashboard.removeSession(sessionID)

    #expect(!FileManager.default.fileExists(atPath: sessionWorkspaceURL.path))
    #expect(FileManager.default.fileExists(atPath: workspaceURL.path))
}

@Test @MainActor
func spawnNewSession_cursor_usesCursorBinaryAndHookURLWithoutSettings() async throws {
    let ptyManager = MockPTYManager()
    let cursorPath = "/usr/local/bin/cursor-agent"
    let dispatcherPath = "/tmp/agent-dashboard-test-dispatcher.sh"

    let hookURL = URL(string: "http://127.0.0.1:8080/hook")!
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: hookURL,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: dispatcherPath,
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceURL,
        agentBinaryPaths: [.cursor: cursorPath],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewSession(kind: .cursor)
    #expect(dashboard.sessions.count == 1)
    let sessionID = dashboard.sessions[0].id
    #expect(dashboard.sessions[0].agentKind == .cursor)

    let sessionWorkspaceURL = environment.sessionWorkspaceDirectory(for: sessionID)
    let hooksURL = CursorHooksManager.hooksFileURL(in: sessionWorkspaceURL)
    #expect(FileManager.default.fileExists(atPath: hooksURL.path))

    let hooksData = try Data(contentsOf: hooksURL)
    let hooksJSON = try JSONSerialization.jsonObject(with: hooksData) as? [String: Any]
    #expect(hooksJSON?["version"] as? Int == 1)
    let hooks = try #require(hooksJSON?["hooks"] as? [String: Any])
    let beforeShellEntries = try #require(hooks["beforeShellExecution"] as? [[String: Any]])
    let beforeShellCommand = try #require(beforeShellEntries.first?["command"] as? String)
    #expect(beforeShellCommand == "'\(dispatcherPath)' preToolUse")
    #expect(!beforeShellCommand.contains("PHLOX_SESSION_ID="))
    #expect(!beforeShellCommand.contains("CLAUDE_HOOKS_URL="))

    dashboard.sessions[0].terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let call = try #require(ptyManager.spawnCalls.first)
    #expect(call.command == cursorPath)
    #expect(call.args == ["--force", "--sandbox", "disabled"])
    #expect(call.workingDirectory == sessionWorkspaceURL.path)
    #expect(!call.args.contains("--settings"))
    #expect(!call.args.contains("--dangerously-bypass-hook-trust"))
    #expect(call.env["PHLOX_SESSION_ID"] != nil)
    #expect(call.env["CLAUDE_HOOKS_URL"] == hookURL.absoluteString)

    await dashboard.removeSession(sessionID)
    #expect(!FileManager.default.fileExists(atPath: hooksURL.path))
}

@Test @MainActor
func availableAgentKinds_includesResolvedOptionalCLIs() {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()

    let envWithCodex = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: URL(fileURLWithPath: "/tmp/agent-dashboard-test-workspace"),
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )
    let dashboardWithCodex = DashboardViewModel(environment: envWithCodex)
    #expect(dashboardWithCodex.availableAgentKinds.first == .claudeCode)
    #expect(dashboardWithCodex.availableAgentKinds == [.claudeCode, .codex])

    let envWithCursor = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: URL(fileURLWithPath: "/tmp/agent-dashboard-test-workspace"),
        agentBinaryPaths: [.cursor: "/usr/local/bin/cursor-agent"],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )
    let dashboardWithCursor = DashboardViewModel(environment: envWithCursor)
    #expect(dashboardWithCursor.availableAgentKinds.first == .claudeCode)
    #expect(dashboardWithCursor.availableAgentKinds == [.claudeCode, .cursor])

    let envEmpty = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboardEmpty = DashboardViewModel(environment: envEmpty)
    #expect(dashboardEmpty.availableAgentKinds == [.claudeCode])

    // 両オプション CLI が解決済みなら、メニュー表示順は claudeCode → codex → cursor で固定。
    let envBoth = AppEnvironment(
        pty: ptyManager,
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: URL(fileURLWithPath: "/tmp/agent-dashboard-test-workspace"),
        agentBinaryPaths: [.codex: "/usr/local/bin/codex", .cursor: "/usr/local/bin/cursor-agent"],
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/agent-dashboard-test-cli"
    )
    let dashboardBoth = DashboardViewModel(environment: envBoth)
    #expect(dashboardBoth.availableAgentKinds.first == .claudeCode)
    #expect(dashboardBoth.availableAgentKinds == [.claudeCode, .codex, .cursor])
}

@Test @MainActor
func spawnNewSession_missingBinary_throws() async {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)

    await #expect(throws: AgentSpawnError.self) {
        try await dashboard.spawnNewSession(kind: .cursor)
    }
}

@Test @MainActor
func restorePersistedSessions_publishesRecentSessionSelectionAndExpandedProjects() async throws {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let firstProjectFolder = workspaceURL.appendingPathComponent("first", isDirectory: true)
    let secondProjectFolder = workspaceURL.appendingPathComponent("second", isDirectory: true)
    try FileManager.default.createDirectory(at: firstProjectFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: secondProjectFolder, withIntermediateDirectories: true)

    let olderProject = Project(
        name: "First",
        directoryPath: firstProjectFolder.path,
        createdAt: Date(timeIntervalSince1970: 1),
        isManagedDirectory: false
    )
    let newerProject = Project(
        name: "Second",
        directoryPath: secondProjectFolder.path,
        createdAt: Date(timeIntervalSince1970: 2),
        isManagedDirectory: false
    )
    let projectStore = InMemoryProjectStore()
    try await projectStore.save([olderProject, newerProject])

    let olderID = SessionID()
    let newerID = SessionID()
    let sessionStore = InMemorySessionStore([
        makePersistedSessionDescriptor(
            id: olderID,
            workingDirectory: firstProjectFolder.path,
            projectID: olderProject.id,
            startedAt: Date(timeIntervalSince1970: 10),
            resumeID: "older-resume"
        ),
        makePersistedSessionDescriptor(
            id: newerID,
            workingDirectory: secondProjectFolder.path,
            projectID: newerProject.id,
            startedAt: Date(timeIntervalSince1970: 20),
            resumeID: "newer-resume"
        ),
    ])

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        projects: projectStore,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    #expect(dashboard.sessions.map(\.id) == [olderID, newerID])
    let presentation = try #require(dashboard.restoredSessionPresentation)
    #expect(presentation.selectedSessionID == newerID)
    #expect(presentation.expandedProjectIDs == Set([olderProject.id, newerProject.id]))
}

// MARK: - Sidebar navigation

@MainActor
private func makeDashboardForSidebarNavigationTests() async throws -> (
    dashboard: DashboardViewModel,
    orderedIDs: [SessionID]
) {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let folderA = workspaceURL.appendingPathComponent("project-a", isDirectory: true)
    let folderB = workspaceURL.appendingPathComponent("project-b", isDirectory: true)
    let unassignedFolder = workspaceURL.appendingPathComponent("unassigned", isDirectory: true)
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: unassignedFolder, withIntermediateDirectories: true)

    let projectA = Project(
        name: "Project A",
        directoryPath: folderA.path,
        createdAt: Date(timeIntervalSince1970: 1),
        isManagedDirectory: false
    )
    let projectB = Project(
        name: "Project B",
        directoryPath: folderB.path,
        createdAt: Date(timeIntervalSince1970: 2),
        isManagedDirectory: false
    )
    let projectStore = InMemoryProjectStore()
    try await projectStore.save([projectA, projectB])

    let sessionA1 = SessionID()
    let sessionA2 = SessionID()
    let sessionB1 = SessionID()
    let unassignedID = SessionID()
    let sessionStore = InMemorySessionStore([
        makePersistedSessionDescriptor(
            id: sessionA1,
            workingDirectory: folderA.path,
            projectID: projectA.id,
            startedAt: Date(timeIntervalSince1970: 10)
        ),
        makePersistedSessionDescriptor(
            id: sessionA2,
            workingDirectory: folderA.path,
            projectID: projectA.id,
            startedAt: Date(timeIntervalSince1970: 11)
        ),
        makePersistedSessionDescriptor(
            id: sessionB1,
            workingDirectory: folderB.path,
            projectID: projectB.id,
            startedAt: Date(timeIntervalSince1970: 20)
        ),
        makePersistedSessionDescriptor(
            id: unassignedID,
            workingDirectory: unassignedFolder.path,
            projectID: nil,
            startedAt: Date(timeIntervalSince1970: 30)
        ),
    ])

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        projects: projectStore,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let orderedIDs = [sessionA1, sessionA2, sessionB1, unassignedID]
    return (dashboard, orderedIDs)
}

@Test @MainActor
func sidebarOrderedSessionIDs_ordersByProjectThenUnassigned() async throws {
    let (dashboard, orderedIDs) = try await makeDashboardForSidebarNavigationTests()
    #expect(dashboard.sidebarOrderedSessionIDs == orderedIDs)
}

@Test @MainActor
func adjacentSessionID_forwardReturnsNext() async throws {
    let (dashboard, orderedIDs) = try await makeDashboardForSidebarNavigationTests()
    #expect(dashboard.adjacentSessionID(from: orderedIDs[0], forward: true) == orderedIDs[1])
    #expect(dashboard.adjacentSessionID(from: orderedIDs[2], forward: true) == orderedIDs[3])
}

@Test @MainActor
func adjacentSessionID_backwardReturnsPrevious() async throws {
    let (dashboard, orderedIDs) = try await makeDashboardForSidebarNavigationTests()
    #expect(dashboard.adjacentSessionID(from: orderedIDs[1], forward: false) == orderedIDs[0])
    #expect(dashboard.adjacentSessionID(from: orderedIDs[3], forward: false) == orderedIDs[2])
}

@Test @MainActor
func adjacentSessionID_stopsAtEnds() async throws {
    let (dashboard, orderedIDs) = try await makeDashboardForSidebarNavigationTests()
    let first = try #require(orderedIDs.first)
    let last = try #require(orderedIDs.last)
    #expect(dashboard.adjacentSessionID(from: first, forward: false) == first)
    #expect(dashboard.adjacentSessionID(from: last, forward: true) == last)
}

@Test @MainActor
func adjacentSessionID_nilSelectsFirstOrLast() async throws {
    let (dashboard, orderedIDs) = try await makeDashboardForSidebarNavigationTests()
    let first = try #require(orderedIDs.first)
    let last = try #require(orderedIDs.last)
    #expect(dashboard.adjacentSessionID(from: nil, forward: true) == first)
    #expect(dashboard.adjacentSessionID(from: nil, forward: false) == last)
}

@Test @MainActor
func adjacentSessionID_unknownIDFallsBackToEdge() async throws {
    let (dashboard, orderedIDs) = try await makeDashboardForSidebarNavigationTests()
    let unknown = SessionID()
    let first = try #require(orderedIDs.first)
    let last = try #require(orderedIDs.last)
    #expect(dashboard.adjacentSessionID(from: unknown, forward: true) == first)
    #expect(dashboard.adjacentSessionID(from: unknown, forward: false) == last)
}

@Test @MainActor
func adjacentSessionID_emptySessionsReturnsNil() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    #expect(dashboard.sidebarOrderedSessionIDs.isEmpty)
    #expect(dashboard.adjacentSessionID(from: nil, forward: true) == nil)
    #expect(dashboard.adjacentSessionID(from: nil, forward: false) == nil)
    #expect(dashboard.adjacentSessionID(from: SessionID(), forward: true) == nil)
}

// MARK: - changeWorkspace

@Test @MainActor
func changeWorkspace_swapsHookStreamAndRoutesNewEvents() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let vm = dashboard.sessions[0]
    let sessionID = vm.id
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    await dashboard.changeWorkspace(sessionID, to: URL(fileURLWithPath: "/new/workspace"))
    try await waitUntil { ptyManager.spawnCalls.count == 2 }
    #expect(ptyManager.spawnCalls.last?.workingDirectory == "/new/workspace")

    // 再起動後に hook を流すと、新 stream 経由（multiplex の dictionary lookup）で status が更新される。
    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: nil)))
    try await waitUntil { vm.status == .running }
    #expect(vm.status == .running)
}

@Test @MainActor
func changeWorkspace_preservesNameAcrossRestart() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let vm = dashboard.sessions[0]
    vm.name = "My"
    vm.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    await dashboard.changeWorkspace(vm.id, to: URL(fileURLWithPath: "/new/workspace"))
    try await waitUntil { ptyManager.spawnCalls.count == 2 }

    #expect(vm.name == "My")
    #expect(dashboard.sessions[0] === vm)
}

@Test @MainActor
func changeWorkspace_doesNotAffectOtherSessions() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    try await dashboard.spawnNewClaudeCodeSession()
    let vmA = dashboard.sessions[0]
    let vmB = dashboard.sessions[1]

    vmA.terminalCoordinator.onResize(80, 24)
    vmB.terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 2 }

    let bSpawnsBefore = ptyManager.spawnCalls.filter { $0.id == vmB.id }.count
    let bStatusBefore = vmB.status

    await dashboard.changeWorkspace(vmA.id, to: URL(fileURLWithPath: "/new/workspace"))
    try await waitUntil { ptyManager.spawnCalls.filter { $0.id == vmA.id }.count == 2 }

    // B の spawn 回数・status・kill 状況が変化しないこと。
    #expect(ptyManager.spawnCalls.filter { $0.id == vmB.id }.count == bSpawnsBefore)
    #expect(vmB.status == bStatusBefore)
    #expect(ptyManager.killedIDs == [vmA.id])
}

@Test @MainActor
func changeWorkspace_unknownID_isNoOp() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    dashboard.sessions[0].terminalCoordinator.onResize(80, 24)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    await dashboard.changeWorkspace(SessionID(), to: URL(fileURLWithPath: "/new/workspace"))

    // crash せず、kill / spawn が増えない。
    try await Task.sleep(nanoseconds: 50_000_000)
    #expect(ptyManager.spawnCalls.count == 1)
    #expect(ptyManager.killedIDs.isEmpty)
}

// MARK: - sessionOutput

@Test @MainActor
func sessionOutput_returnsVisibleTerminalTextForKnownSession() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let vm = dashboard.sessions[0]
    vm.terminalCoordinator.feed(Data("PONG".utf8))

    let output = dashboard.sessionOutput(for: vm.id)
    let text = try #require(output)
    #expect(text.contains("PONG"))
}

@Test @MainActor
func sessionOutput_returnsNilForUnknownSession() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()

    #expect(dashboard.sessionOutput(for: SessionID()) == nil)
}

// MARK: - waitUntilReady

@Test @MainActor
func waitUntilReady_claudeCode_readyAfterSessionStartAndSettledOutput() async throws {
    // claudeCode は初回出力だけでは ready にならず、SessionStart フック受信 +
    // 出力静止（settle）で初めて ready になる（TUI 起動完了前の send 消失バグの回帰防止）。
    let ptyManager = MockPTYManager()
    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    // 出力のみ（SessionStart 未受信）では settle 時間が経過しても ready にならない。
    ptyManager.emitOutput(for: sessionID, data: Data("banner\n".utf8))
    let prematureResult = await dashboard.waitUntilReady(for: sessionID, timeout: .milliseconds(600))
    #expect(prematureResult == .timedOut)

    // SessionStart 受信後、出力静止を待って ready になる。
    hookContinuation.yield((sessionID, .sessionStart))
    let result = await dashboard.waitUntilReady(for: sessionID, timeout: .seconds(2))
    #expect(result == .ready)
}

@Test @MainActor
func waitUntilReady_returnsTimedOutWithoutOutput() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let result = await dashboard.waitUntilReady(
        for: dashboard.sessions[0].id,
        timeout: .milliseconds(30)
    )

    #expect(result == .timedOut)
}

@Test @MainActor
func waitUntilReady_returnsNotFoundForUnknownSession() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let result = await dashboard.waitUntilReady(for: SessionID(), timeout: .milliseconds(30))

    #expect(result == .notFound)
}

// MARK: - waitUntilDone

@Test @MainActor
func waitUntilDone_doesNotTreatPreexistingStopAsDone() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    hookContinuation.yield((sessionID, .stop(turnId: nil)))
    try await waitUntil { dashboard.sessions[0].completedTurnSeq == 1 }

    let result = await dashboard.waitUntilDone(
        for: sessionID,
        timeout: .milliseconds(30),
        sentinel: nil
    )

    if case .timedOut = result {} else {
        Issue.record("Expected timedOut, got \(result)")
    }
}

@Test @MainActor
func waitUntilDone_returnsDoneForStopAfterWaitStarts() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    let waitTask = Task { @MainActor in
        await dashboard.waitUntilDone(
            for: sessionID,
            timeout: .milliseconds(500),
            sentinel: nil
        )
    }

    try await Task.sleep(for: .milliseconds(20))
    hookContinuation.yield((sessionID, .stop(turnId: nil)))

    let result = await waitTask.value
    if case .done(let output) = result {
        #expect(output == dashboard.sessionOutput(for: sessionID))
    } else {
        Issue.record("Expected done, got \(result)")
    }
}

@Test @MainActor
func waitUntilDone_returnsDoneForNonHookSessionWithoutSentinel() async throws {
    // 回帰テスト: stop フックを持たない codex/cursor セッションでは、出力静止による
    // running→idle フォールバックが turn 完了になる。sentinel なしの wait が
    // タイムアウトせず done を返すこと。
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .codex)
    let sessionVM = try #require(dashboard.sessions.first(where: { $0.id == sessionID }))
    try await waitUntil { sessionVM.status == .idle }

    // send 相当: 入力送信で running になり、以後の wait はこの turn の完了を待つ。
    sessionVM.markInputSubmitted()
    #expect(sessionVM.status == .running)

    let waitTask = Task { @MainActor in
        await dashboard.waitUntilDone(
            for: sessionID,
            timeout: .seconds(3),
            sentinel: nil
        )
    }

    try await Task.sleep(for: .milliseconds(20))
    ptyManager.emitOutput(for: sessionID, data: Data("task finished\n".utf8))

    let result = await waitTask.value
    if case .done = result {} else {
        Issue.record("Expected done, got \(result)")
    }
}

@Test @MainActor
func waitUntilDone_returnsDoneWhenSentinelAppears() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    let waitTask = Task { @MainActor in
        await dashboard.waitUntilDone(
            for: sessionID,
            timeout: .milliseconds(500),
            sentinel: "DONE"
        )
    }

    try await Task.sleep(for: .milliseconds(20))
    // 本番同様に PTY 出力経由で画面を更新する（lastOutputAt 更新を伴う）。
    ptyManager.emitOutput(for: sessionID, data: Data("task DONE\n".utf8))

    let result = await waitTask.value
    if case .done(let output) = result {
        #expect(output.contains("DONE"))
    } else {
        Issue.record("Expected done, got \(result)")
    }
}

@Test @MainActor
func waitUntilDone_returnsTimedOutWithoutCompletionSignal() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    let result = await dashboard.waitUntilDone(
        for: sessionID,
        timeout: .milliseconds(30),
        sentinel: nil
    )

    if case .timedOut(let output) = result {
        #expect(output == dashboard.sessionOutput(for: sessionID))
    } else {
        Issue.record("Expected timedOut, got \(result)")
    }
}

@Test @MainActor
func waitUntilDone_returnsNotFoundForUnknownSession() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let result = await dashboard.waitUntilDone(
        for: SessionID(),
        timeout: .milliseconds(30),
        sentinel: nil
    )

    #expect(result == .notFound)
}

@Test @MainActor
func waitUntilDone_returnsDoneForMatchingTurnIdStop() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: "T2")))

    let waitTask = Task { @MainActor in
        await dashboard.waitUntilDone(
            for: sessionID,
            timeout: .milliseconds(500),
            sentinel: nil
        )
    }

    try await Task.sleep(for: .milliseconds(20))
    hookContinuation.yield((sessionID, .stop(turnId: "T2")))

    let result = await waitTask.value
    if case .done = result {} else {
        Issue.record("Expected done, got \(result)")
    }
}

@Test @MainActor
func waitUntilDone_doesNotCompleteOnStaleTurnIdStop() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    hookContinuation.yield((sessionID, .userPromptSubmit(turnId: "T2")))
    try await waitUntil { dashboard.sessions[0].activeTurnId == "T2" }

    let waitTask = Task { @MainActor in
        await dashboard.waitUntilDone(
            for: sessionID,
            timeout: .milliseconds(80),
            sentinel: nil
        )
    }

    try await Task.sleep(for: .milliseconds(20))
    hookContinuation.yield((sessionID, .stop(turnId: "T1")))

    let result = await waitTask.value
    if case .timedOut = result {} else {
        Issue.record("Expected timedOut on stale turn stop, got \(result)")
    }
    #expect(dashboard.sessions[0].completedTurnSeq == 0)
}

@Test @MainActor
func waitUntilDone_returnsDoneForStopWithoutTurnId() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, hookContinuation) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id

    let waitTask = Task { @MainActor in
        await dashboard.waitUntilDone(
            for: sessionID,
            timeout: .milliseconds(500),
            sentinel: nil
        )
    }

    try await Task.sleep(for: .milliseconds(20))
    hookContinuation.yield((sessionID, .stop(turnId: nil)))

    let result = await waitTask.value
    if case .done = result {} else {
        Issue.record("Expected done for turnId-less stop, got \(result)")
    }
}

// MARK: - Grid session visibility

@Test
func isVisibleInGrid_interactive_returnsTrue() {
    #expect(DashboardViewModel.isVisibleInGrid(launchContext: .interactive))
}

@Test
func isVisibleInGrid_orchestration_returnsFalse() {
    #expect(!DashboardViewModel.isVisibleInGrid(launchContext: .orchestration))
}

@Test @MainActor
func orchestrationSession_isExcludedFromGridVisibleSessionNodes() async throws {
    let (dashboard, projectID) = try await makeDashboardWithProjectForOrchestrationTests()

    let interactiveID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .interactive
    )
    let orchestrationID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .orchestration
    )

    #expect(dashboard.sessionNodes.map(\.id).contains(orchestrationID))
    #expect(dashboard.gridVisibleSessionNodes.map(\.id) == [interactiveID])
    #expect(!dashboard.gridVisibleSessionNodes.map(\.id).contains(orchestrationID))
}

@Test @MainActor
func orchestrationUnassignedSession_isExcludedFromGridVisibleSessionNodes() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let interactiveID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        launchContext: .interactive
    )
    let orchestrationID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        launchContext: .orchestration
    )

    #expect(dashboard.gridVisibleSessionNodes.map(\.id) == [interactiveID])
    #expect(dashboard.sessionNode(id: orchestrationID)?.launchContext == .orchestration)
}

// MARK: - Orchestration session sidebar visibility

@MainActor
private func makeDashboardWithProjectForOrchestrationTests() async throws -> (
    dashboard: DashboardViewModel,
    projectID: ProjectID
) {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()

    let projectFolder = workspaceURL.appendingPathComponent("orchestration-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(
        dashboard.addProject(name: "Orchestration Project", directoryPath: projectFolder.path)
    )
    return (dashboard, projectID)
}

@Test @MainActor
func orchestrationSession_isExcludedFromSidebarSessionLists() async throws {
    let (dashboard, projectID) = try await makeDashboardWithProjectForOrchestrationTests()

    let interactiveID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .interactive
    )
    let orchestrationID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .orchestration
    )

    #expect(dashboard.sessionNodes.map(\.id).contains(orchestrationID))
    #expect(dashboard.sessionNodes(in: projectID).map(\.id) == [interactiveID])
    #expect(dashboard.unassignedSessionNodes.isEmpty)
    #expect(dashboard.sidebarOrderedSessionIDs == [interactiveID])
}

@Test @MainActor
func orchestrationSession_remainsInternallyAccessible() async throws {
    let (dashboard, projectID) = try await makeDashboardWithProjectForOrchestrationTests()

    let orchestrationID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .orchestration
    )

    let node = try #require(dashboard.sessionNode(id: orchestrationID))
    #expect(node.launchContext == .orchestration)
    #expect(node.projectID == projectID)
    #expect(dashboard.sessionNodes.contains { $0.id == orchestrationID })
}

@Test @MainActor
func orchestrationUnassignedSession_isExcludedFromUnassignedSidebarList() async throws {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let interactiveID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        launchContext: .interactive
    )
    let orchestrationID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        launchContext: .orchestration
    )

    #expect(dashboard.unassignedSessionNodes.map(\.id) == [interactiveID])
    #expect(dashboard.sessionNode(id: orchestrationID)?.launchContext == .orchestration)
    #expect(dashboard.sidebarOrderedSessionIDs == [interactiveID])
}

@Test @MainActor
func restorePersistedOrchestrationSession_keepsSidebarExclusion() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectFolder = workspaceURL.appendingPathComponent("restore-orchestration", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let project = Project(
        name: "Restore Orchestration",
        directoryPath: projectFolder.path,
        createdAt: Date(),
        isManagedDirectory: false
    )
    let projectStore = InMemoryProjectStore()
    try await projectStore.save([project])

    let interactiveID = SessionID()
    let orchestrationID = SessionID()
    let sessionStore = InMemorySessionStore([
        makePersistedSessionDescriptor(
            id: interactiveID,
            workingDirectory: projectFolder.path,
            projectID: project.id,
            startedAt: Date(timeIntervalSince1970: 10)
        ),
        makePersistedSessionDescriptor(
            id: orchestrationID,
            workingDirectory: projectFolder.path,
            projectID: project.id,
            startedAt: Date(timeIntervalSince1970: 20),
            launchContext: .orchestration
        ),
    ])

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        projects: projectStore,
        sessions: sessionStore
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    #expect(dashboard.sessionNodes.map(\.id).contains(orchestrationID))
    #expect(dashboard.sessionNodes(in: project.id).map(\.id) == [interactiveID])
    #expect(dashboard.sessionNode(id: orchestrationID)?.launchContext == .orchestration)
    #expect(dashboard.sidebarOrderedSessionIDs == [interactiveID])
}

@Test @MainActor
func restoreFailedSession_marksErrorStatusAndSkipsSpawn() async throws {
    let descriptor = makeCustomAgentDescriptor()
    let catalog = AgentCatalog(customDescriptors: [descriptor])
    let sessionID = SessionID()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let sessionStore = InMemorySessionStore([
        PersistedSessionDescriptor(
            id: sessionID,
            agentRef: descriptor.ref,
            workingDirectory: workspaceURL.path,
            name: "Broken Restore",
            projectID: nil,
            startedAt: Date(),
            command: "/opt/homebrew/bin/aider",
            args: ["--model", "sonnet"],
            env: [:],
            token: "token-\(sessionID.rawValue.uuidString)"
        )
    ])

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore,
        workspaceDirectory: workspaceURL,
        customAgentBinaryPaths: [:],
        agentCatalog: catalog
    )

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    #expect(dashboard.sessions.count == 1)
    let vm = try #require(dashboard.sessions.first)
    #expect(vm.id == sessionID)
    if case .error(let message) = vm.status {
        #expect(message.contains("restore failed"))
    } else {
        Issue.record("Expected error status after restore failure, got \(vm.status)")
    }
    #expect(ptyManager.spawnCalls.isEmpty)
}

// MARK: - task-12: Cursor `cursor-agent models` provider wiring

@Test
func parseCursorModelList_parsesRealCursorAgentOutput() {
    let raw = """
    Available models

    auto - Auto
    gpt-5.3-codex - Codex 5.3
    composer-2.5 - Composer 2.5 (current)
    claude-opus-4-8-thinking-high - Opus 4.8 1M Thinking
    """
    let ids = DashboardViewModel.parseCursorModelList(raw)
    #expect(ids == [
        "auto",
        "gpt-5.3-codex",
        "composer-2.5",
        "claude-opus-4-8-thinking-high"
    ])
}

@Test
func parseCursorModelList_excludesHeaderBlankAndMalformedLines() {
    let raw = """
    Available models

    auto - Auto

    garbage-line-without-separator
    gpt-5.3-codex - Codex 5.3
    ...
    """
    let ids = DashboardViewModel.parseCursorModelList(raw)
    // ヘッダ・空行・区切り無し行・"..." を全て除外し、実 ID のみを返す。
    #expect(ids == ["auto", "gpt-5.3-codex"])
}

@Test
func parseCursorModelList_emptyStringReturnsEmpty() {
    #expect(DashboardViewModel.parseCursorModelList("").isEmpty)
}

@Test
func makeSpawnAgentModelsProvider_injectsOnlyForCursor() {
    let runner: DashboardViewModel.CursorModelListRunner = { _, _, _, _ in "auto - Auto" }
    #expect(DashboardViewModel.makeSpawnAgentModelsProvider(
        ref: .builtin(.cursor),
        command: "/usr/local/bin/cursor-agent",
        env: [:],
        workingDirectory: nil,
        runner: runner
    ) != nil)
    #expect(DashboardViewModel.makeSpawnAgentModelsProvider(
        ref: .builtin(.claudeCode),
        command: "claude",
        env: [:],
        workingDirectory: nil,
        runner: runner
    ) == nil)
    #expect(DashboardViewModel.makeSpawnAgentModelsProvider(
        ref: .builtin(.codex),
        command: "codex",
        env: [:],
        workingDirectory: nil,
        runner: runner
    ) == nil)
}

@Test
func cursorProvider_runsModelsSubcommandAndReturnsParsedIDs() async {
    let capturedArgs = LockedBox<[String]?>(nil)
    let runner: DashboardViewModel.CursorModelListRunner = { command, args, _, _ in
        capturedArgs.value = args
        #expect(command == "/usr/local/bin/cursor-agent")
        return "Available models\n\nauto - Auto\ncomposer-2.5 - Composer 2.5 (current)\n"
    }
    let provider = DashboardViewModel.makeSpawnAgentModelsProvider(
        ref: .builtin(.cursor),
        command: "/usr/local/bin/cursor-agent",
        env: [:],
        workingDirectory: nil,
        runner: runner
    )
    let models = await provider?()
    #expect(capturedArgs.value == ["models"])
    #expect(models == ["auto", "composer-2.5"])
}

@Test
func cursorProvider_processFailureReturnsEmptyWithoutThrowing() async {
    let runner: DashboardViewModel.CursorModelListRunner = { _, _, _, _ in nil }
    let provider = DashboardViewModel.makeSpawnAgentModelsProvider(
        ref: .builtin(.cursor),
        command: "cursor-agent",
        env: [:],
        workingDirectory: nil,
        runner: runner
    )
    #expect(await provider?() == [])
}

@Test
func cursorProvider_emptyOutputReturnsEmpty() async {
    let runner: DashboardViewModel.CursorModelListRunner = { _, _, _, _ in "" }
    let provider = DashboardViewModel.makeSpawnAgentModelsProvider(
        ref: .builtin(.cursor),
        command: "cursor-agent",
        env: [:],
        workingDirectory: nil,
        runner: runner
    )
    #expect(await provider?() == [])
}

// task-7: 新規チャット作成時に last-used を startNew へ渡す。
@Test @MainActor
func spawnNewSession_appliesLastUsedModelAndEffortFromStore() async throws {
    let suiteName = "phlox-dashboard-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = LastUsedChatSettingsStore(defaults: defaults)
    store.record(agentID: AgentKind.claudeCode.rawValue, model: "sonnet", effort: "max")

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.claudeCode: "/usr/local/bin/claude"]
    )
    let dashboard = DashboardViewModel(environment: environment)
    dashboard.lastUsedChatSettingsStoreForTesting = store
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .claudeCode, backend: .appServer)
    let chat = try #require(dashboard.sessionNodes.first(where: { $0.id == sessionID })?.appServer)
    #expect(chat.selectedModel == "sonnet")
    #expect(chat.selectedEffort == "max")
}

// task-7: codexSettingsDidChange 経由で model/effort を agent ごとに記録する。
@Test @MainActor
func spawnNewSession_codexSettingsDidChangeRecordsLastUsedSettings() async throws {
    let suiteName = "phlox-dashboard-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = LastUsedChatSettingsStore(defaults: defaults)

    let transport = ScriptedAppServerTransport()
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"],
        appServerClientFactory: { _, _, _, _, handler in
            let client = CodexAppServerClient(transport: transport, serverRequestHandler: handler)
            return CodexStructuredAgentClient(client: client)
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    dashboard.lastUsedChatSettingsStoreForTesting = store
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(kind: .codex, backend: .appServer)
    let chat = try #require(dashboard.sessionNodes.first(where: { $0.id == sessionID })?.appServer)

    try await chat.setModel(model: "gpt-5-codex", effort: "medium")

    #expect(store.lastUsed(agentID: AgentKind.codex.rawValue) == LastUsedChatSettings(model: "gpt-5-codex", effort: "medium"))
    #expect(store.lastUsed(agentID: AgentKind.claudeCode.rawValue) == nil)
    #expect(chat.selectedModel == "gpt-5-codex")
    #expect(chat.selectedEffort == "medium")
}

/// テスト用の Sendable な可変ボックス（クロージャ内で捕捉するため）。
private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); defer { lock.unlock() }; stored = newValue }
    }
}
