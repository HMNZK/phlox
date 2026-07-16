import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - Mock OrphanReaper

/// reconcile が「どの pid を生存判定し」「どの pid を reap したか」を観測するモック。
/// 実プロセスには一切触れず、`alivePIDs` で生存応答を制御する。
final class MockOrphanReaper: OrphanReaper, @unchecked Sendable {
    private let lock = NSLock()
    private var _alivePIDs: Set<pid_t>
    private(set) var isAliveQueriedPIDs: [pid_t] = []
    private(set) var reapedPIDs: [pid_t] = []

    init(alivePIDs: Set<pid_t> = []) {
        self._alivePIDs = alivePIDs
    }

    func isAlive(_ pid: pid_t) -> Bool {
        lock.lock(); defer { lock.unlock() }
        isAliveQueriedPIDs.append(pid)
        return _alivePIDs.contains(pid)
    }

    func reap(_ pid: pid_t) {
        lock.lock(); defer { lock.unlock() }
        reapedPIDs.append(pid)
    }
}

// MARK: - reconcile（restore 時の生存孤児 reap → 再 spawn）

@Test @MainActor
func restore_withLiveRecordedPid_reapsThatPidThenRespawns() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let recordedPID: pid_t = 4242
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: workspaceRoot.path,
        name: "orphan-live",
        projectID: nil,
        startedAt: Date(),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:],
        token: "token",
        pid: recordedPID
    )

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: InMemorySessionStore([descriptor]),
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
    )

    let reaper = MockOrphanReaper(alivePIDs: [recordedPID])
    let dashboard = DashboardViewModel(environment: environment, orphanReaper: reaper)

    await dashboard.start()

    // 記録 pid が生存 → その pid を reap してから再 spawn する。
    #expect(reaper.reapedPIDs == [recordedPID])
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    #expect(ptyManager.spawnCalls.first?.id == sessionID)
}

@Test @MainActor
func restore_withDeadRecordedPid_doesNotReapButStillRespawns() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let recordedPID: pid_t = 7777
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: workspaceRoot.path,
        name: "orphan-dead",
        projectID: nil,
        startedAt: Date(),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:],
        token: "token",
        pid: recordedPID
    )

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: InMemorySessionStore([descriptor]),
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
    )

    // alivePIDs を空にして「記録 pid は死亡」を表現する。
    let reaper = MockOrphanReaper(alivePIDs: [])
    let dashboard = DashboardViewModel(environment: environment, orphanReaper: reaper)

    await dashboard.start()

    // 記録 pid が死亡 → reap せず従来どおり再 spawn する。
    #expect(reaper.isAliveQueriedPIDs == [recordedPID])
    #expect(reaper.reapedPIDs.isEmpty)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    #expect(ptyManager.spawnCalls.first?.id == sessionID)
}

@Test @MainActor
func restore_withNilRecordedPid_doesNotQueryOrReapButStillRespawns() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    // 旧 descriptor 相当: pid なし。
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: workspaceRoot.path,
        name: "legacy-no-pid",
        projectID: nil,
        startedAt: Date(),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:],
        token: "token",
        pid: nil
    )

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: InMemorySessionStore([descriptor]),
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
    )

    let reaper = MockOrphanReaper(alivePIDs: [9001])
    let dashboard = DashboardViewModel(environment: environment, orphanReaper: reaper)

    await dashboard.start()

    // pid==nil → 生存判定も reap も行わず、従来挙動で再 spawn する。
    #expect(reaper.isAliveQueriedPIDs.isEmpty)
    #expect(reaper.reapedPIDs.isEmpty)
    try await waitUntil { ptyManager.spawnCalls.count == 1 }
    #expect(ptyManager.spawnCalls.first?.id == sessionID)
}

// MARK: - persistSessionWorkspace が pid を保持する

@Test @MainActor
func persistSessionWorkspace_preservesRecordedPid() async throws {
    let sessionID = SessionID()
    let recordedPID: pid_t = 5150
    let original = PersistedSessionDescriptor(
        id: sessionID,
        kind: .claudeCode,
        workingDirectory: "/tmp/old",
        name: "ws",
        projectID: nil,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        command: "/usr/local/bin/claude",
        args: [],
        env: [:],
        token: "token",
        pid: recordedPID
    )

    let store = InMemorySessionStore([original])
    let coordinator = SessionPersistenceCoordinator(
        sessionStore: store,
        projectStore: NoOpProjectStore(),
        logError: { _, _ in }
    )

    let newProjectID = ProjectID()
    coordinator.persistSessionWorkspace(
        id: sessionID,
        workingDirectory: "/tmp/new",
        projectID: newProjectID
    )

    let saved = await waitUntil(timeoutNanoseconds: 5_000_000_000) {
        let loaded = await store.load()
        return loaded.first?.workingDirectory == "/tmp/new"
    }
    #expect(saved, "workspace 変更が保存されなかった")

    let loaded = try #require(await store.load().first)
    #expect(loaded.workingDirectory == "/tmp/new")
    #expect(loaded.projectID == newProjectID)
    // descriptor 再構築でも pid を欠落させない。
    #expect(loaded.pid == recordedPID)
}

// MARK: - spawn 時に live pid を descriptor へ保存する

@Test @MainActor
func spawnNewSession_persistsLivePidFromProvider() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let store = InMemorySessionStore()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: store,
        workspaceDirectory: workspaceRoot
    )

    let providedPID: pid_t = 31337
    let dashboard = DashboardViewModel(
        environment: environment,
        livePIDProvider: { _ in providedPID }
    )
    await dashboard.start()

    try await dashboard.spawnNewClaudeCodeSession()
    let sessionID = dashboard.sessions[0].id
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    let persisted = await waitUntil(timeoutNanoseconds: 5_000_000_000) {
        let loaded = await store.load()
        return loaded.contains { $0.id == sessionID && $0.pid == providedPID }
    }
    #expect(persisted, "spawn 後に live pid が descriptor へ保存されなかった")
}

// MARK: - restore で再 spawn 後の新 live pid を store へ書き戻す（反復シナリオの孤児蓄積防止）

@Test @MainActor
func restore_respawn_persistsNewLivePidBackToStore() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let oldPID: pid_t = 4242
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: workspaceRoot.path,
        name: "orphan-live",
        projectID: nil,
        startedAt: Date(),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:],
        token: "token",
        pid: oldPID
    )

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let store = InMemorySessionStore([descriptor])
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: store,
        workspaceDirectory: workspaceRoot,
        agentBinaryPaths: [.codex: "/usr/local/bin/codex"]
    )

    // 再 spawn で得られる新世代の live pid。旧 pid とは別の値。
    let newPID: pid_t = 5151
    let reaper = MockOrphanReaper(alivePIDs: [oldPID])
    let dashboard = DashboardViewModel(
        environment: environment,
        orphanReaper: reaper,
        livePIDProvider: { _ in newPID }
    )

    await dashboard.start()

    // 記録 pid が生存 → 旧 pid を reap してから再 spawn。
    #expect(reaper.reapedPIDs == [oldPID])
    try await waitUntil { ptyManager.spawnCalls.count == 1 }

    // 再 spawn 後、descriptor.pid が新 live pid に書き戻されている（旧 pid のままにしない）。
    let rewritten = await waitUntil(timeoutNanoseconds: 5_000_000_000) {
        let loaded = await store.load()
        return loaded.first { $0.id == sessionID }?.pid == newPID
    }
    #expect(rewritten, "復元・再 spawn 後に新 live pid が書き戻されなかった（旧 pid 固定の回帰）")

    let loaded = try #require(await store.load().first { $0.id == sessionID })
    #expect(loaded.pid == newPID)
    #expect(loaded.pid != oldPID)
}

@Test @MainActor
func restore_failedRespawn_doesNotWriteBackPid() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let oldPID: pid_t = 4242
    // binary 解決不能（agentBinaryPaths 未登録）にして prepareSessionLaunch を失敗させ、
    // restore の catch 分岐（spawn 失敗）に入れる。
    let descriptor = PersistedSessionDescriptor(
        id: sessionID,
        kind: .codex,
        workingDirectory: workspaceRoot.path,
        name: "orphan-fail",
        projectID: nil,
        startedAt: Date(),
        command: "/usr/local/bin/codex",
        args: [],
        env: [:],
        token: "token",
        pid: oldPID
    )

    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let store = InMemorySessionStore([descriptor])
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: store,
        workspaceDirectory: workspaceRoot
        // agentBinaryPaths を渡さない → codex バイナリ未解決で spawn 計画が失敗する。
    )

    let newPID: pid_t = 5151
    let reaper = MockOrphanReaper(alivePIDs: [oldPID])
    let dashboard = DashboardViewModel(
        environment: environment,
        orphanReaper: reaper,
        livePIDProvider: { _ in newPID }
    )

    await dashboard.start()

    // 復元エラーセッションとして残るが PTY spawn は起きない。
    try await waitUntil { dashboard.sessions.contains { $0.id == sessionID } }
    #expect(ptyManager.spawnCalls.isEmpty)

    // spawn 失敗分岐では新 pid を書き戻さない。store の pid は旧値のまま維持される。
    let loaded = try #require(await store.load().first { $0.id == sessionID })
    #expect(loaded.pid == oldPID)
}
