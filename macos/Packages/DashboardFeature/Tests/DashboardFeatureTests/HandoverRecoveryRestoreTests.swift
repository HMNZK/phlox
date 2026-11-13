import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

/// 計画的なホスト更新（ADR 0233）の引き継ぎに失敗したセッションは、生きている子を終了も再生成もしない。

private func makeHolderRecord(childPID: Int32) throws -> HolderRecord {
    let json = """
    {"holderID":"h-test","protocolVersion":1,"holderPID":1,"childPID":\(childPID),
     "socketPath":"/tmp/phx-none/s/h-test.sock","startedAt":"2026-11-12T00:00:00Z","metadata":{}}
    """
    return try HolderRecord.decode(Data(json.utf8))
}

@Test @MainActor
func failedAdoption_doesNotReapTheLiveChildAndIsPublishedAsRecoveryNeeded() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let childPID: pid_t = 4343
    let descriptor = PersistedSessionDescriptor(
        id: sessionID, kind: .claudeCode, workingDirectory: workspaceRoot.path, name: "adopt-fails",
        projectID: nil, startedAt: Date(), command: "/usr/local/bin/claude", args: [], env: [:],
        backend: .appServer, chatNativeSessionId: "native-1", token: "token", pid: childPID)
    let adoption = HandoverSession(
        sessionID: sessionID.rawValue.uuidString, agent: "claudeCode",
        holder: try makeHolderRecord(childPID: childPID), appliedSeq: 3, clientState: Data())

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceRoot,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: InMemorySessionStore([descriptor]),
        cliPath: "/tmp/agent-dashboard-test-cli",
        handoverAdoptions: [sessionID: adoption],
        // 採用先のholderにつなげない。
        adoptClientFactory: { _, _, _, _, _, _ in throw HandoverError.adoptionFailed("holder unreachable") })

    // 記録PIDは生きている。引き継ぎ対象なら孤児として回収してはならない。
    let reaper = MockOrphanReaper(alivePIDs: [childPID])
    let dashboard = DashboardViewModel(environment: environment, orphanReaper: reaper)

    await dashboard.start()

    #expect(reaper.reapedPIDs.isEmpty)
    #expect(dashboard.handoverRecoveryNeededSessionIDs == [sessionID])
    #expect(dashboard.handoverAdoptedSessionIDs.isEmpty)
}

@Test @MainActor
func missingDescriptor_keepsHandoverSessionInRecoveryAndDefersUpdate() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let childPID: pid_t = 4345
    let adoption = HandoverSession(
        sessionID: sessionID.rawValue.uuidString, agent: "claudeCode",
        holder: try makeHolderRecord(childPID: childPID), appliedSeq: 3, clientState: Data())
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceRoot,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: InMemorySessionStore([]),
        cliPath: "/tmp/agent-dashboard-test-cli",
        handoverAdoptions: [sessionID: adoption])
    let reaper = MockOrphanReaper(alivePIDs: [childPID])
    let dashboard = DashboardViewModel(environment: environment, orphanReaper: reaper)

    await dashboard.start()

    #expect(dashboard.handoverRecoveryNeededSessionIDs == [sessionID])
    #expect(dashboard.handoverAdoptedSessionIDs.isEmpty)
    #expect(reaper.reapedPIDs.isEmpty)
    #expect(await dashboard.handoverDeferralReasons().contains { $0.contains("復旧待ち") })
    let entry = DashboardHandoverEntry(
        sessionID: sessionID, agent: "claudeCode",
        preparation: HandoverPreparation(holder: adoption.holder, appliedSeq: 3, clientState: Data(), fence: UUID()))
    #expect(!(await dashboard.handoverDescriptorsPersisted(for: [entry])))
}

/// 採用先のクライアントの最小の代役。`completeAdoption`が進行中のターン（`turnStarted`）を流す。
/// 採用は新しい子を作らず、`resume`も`close`も呼ばない。
private final class AdoptedRunningClient: HandoverCapableClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var completed = 0
    private var resumed = 0
    private var closed = 0
    private var cancelled = 0
    private let participation: HandoverParticipation
    private let gateReason: String?
    private let yieldsTurnStarted: Bool

    init(participation: HandoverParticipation = .participant, gateReason: String? = nil, yieldsTurnStarted: Bool = true) {
        self.participation = participation
        self.gateReason = gateReason
        self.yieldsTurnStarted = yieldsTurnStarted
        var captured: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { captured = $0 }
        continuation = captured
    }

    var completeCount: Int { lock.withLock { completed } }
    var resumeCount: Int { lock.withLock { resumed } }
    var closeCount: Int { lock.withLock { closed } }
    var cancelCount: Int { lock.withLock { cancelled } }

    func start() async throws {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws { lock.withLock { resumed += 1 } }
    func interrupt() async throws {}
    func close() async { lock.withLock { closed += 1 }; continuation.finish() }
    func handoverGateReason() async -> String? { gateReason }
    func handoverParticipation() async -> HandoverParticipation { participation }
    func prepareHandover(fence: UUID) async throws -> HandoverPreparation { throw HandoverError.notReady("unused") }
    func cancelHandover() async { lock.withLock { cancelled += 1 } }
    func commitHandover(confirmedThrough: UInt64) async {}
    func completeAdoption() async throws {
        lock.withLock { completed += 1 }
        if yieldsTurnStarted { continuation.yield(.turnStarted) }
    }
}

@Test @MainActor
func successfulAdoption_restoresTheRunningTurnAndDoesNotReapTheLiveChild() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let childPID: pid_t = 4344
    let descriptor = PersistedSessionDescriptor(
        id: sessionID, kind: .claudeCode, workingDirectory: workspaceRoot.path, name: "adopt-succeeds",
        projectID: nil, startedAt: Date(), command: "/usr/local/bin/claude", args: [], env: [:],
        backend: .appServer, chatNativeSessionId: "native-2", token: "token", pid: childPID)
    let adoption = HandoverSession(
        sessionID: sessionID.rawValue.uuidString, agent: "claudeCode",
        holder: try makeHolderRecord(childPID: childPID), appliedSeq: 5, clientState: Data())
    let adopted = AdoptedRunningClient()

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceRoot,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: InMemorySessionStore([descriptor]),
        cliPath: "/tmp/agent-dashboard-test-cli",
        handoverAdoptions: [sessionID: adoption],
        adoptClientFactory: { _, _, _, _, _, _ in adopted })

    // 記録PIDは生きている。採用に成功した実行は孤児として回収してはならない。
    let reaper = MockOrphanReaper(alivePIDs: [childPID])
    let dashboard = DashboardViewModel(environment: environment, orphanReaper: reaper)

    await dashboard.start()

    let vm = try #require(dashboard.sessionNodes.compactMap(\.appServer).first { $0.id == sessionID })
    #expect(vm.restoreState == .restored)
    #expect(dashboard.handoverAdoptedSessionIDs == [sessionID])
    #expect(dashboard.handoverRecoveryNeededSessionIDs.isEmpty)
    #expect(reaper.reapedPIDs.isEmpty)
    // 進行中のターンが続きとして復元される（新しい子も、再開（resume）もしない）。
    try await waitUntil { vm.status == .running }
    #expect(vm.status == .running)
    #expect(adopted.completeCount == 1)
    #expect(adopted.resumeCount == 0)
    #expect(adopted.closeCount == 0)
}

/// 中断でCLIが終わった実行（子は既に無い）は、次の更新を延期せず、確定点にも載せない。
@Test @MainActor
func adoptedSessionWhoseChildEnded_neitherDefersNorJoinsTheNextHandover() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let childPID: pid_t = 4345
    let descriptor = PersistedSessionDescriptor(
        id: sessionID, kind: .claudeCode, workingDirectory: workspaceRoot.path, name: "child-ended",
        projectID: nil, startedAt: Date(), command: "/usr/local/bin/claude", args: [], env: [:],
        backend: .appServer, chatNativeSessionId: "native-3", token: "token", pid: childPID)
    let adoption = HandoverSession(
        sessionID: sessionID.rawValue.uuidString, agent: "claudeCode",
        holder: try makeHolderRecord(childPID: childPID), appliedSeq: 1, clientState: Data())
    // holder経由でないため、判定だけなら延期理由になる子（ただし既に終了している）。
    let adopted = AdoptedRunningClient(
        participation: .childEnded, gateReason: "Claudeの子がholder経由ではありません", yieldsTurnStarted: false)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceRoot,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: InMemorySessionStore([descriptor]),
        cliPath: "/tmp/agent-dashboard-test-cli",
        handoverAdoptions: [sessionID: adoption],
        adoptClientFactory: { _, _, _, _, _, _ in adopted })
    let dashboard = DashboardViewModel(environment: environment, orphanReaper: MockOrphanReaper(alivePIDs: []))
    await dashboard.start()
    #expect(dashboard.handoverAdoptedSessionIDs == [sessionID], "前提: 採用が成功している")

    let reasons = await dashboard.handoverDeferralReasons()
    #expect(reasons.isEmpty, "子が終了済みの実行が更新を延期している: \(reasons)")
    let entries = try await dashboard.prepareHandoverEntries()
    #expect(entries.isEmpty)
}

/// 更新の取りまとめ: 復旧待ちのセッションがあれば更新を延期し、中止は参加者全員の確定点の作成を取り消し、門は閉じて開ける。
@Test @MainActor
func dashboardCoordinatesDeferralAbortAndTheLaunchGate() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let childPID: pid_t = 4346
    let descriptor = PersistedSessionDescriptor(
        id: sessionID, kind: .claudeCode, workingDirectory: workspaceRoot.path, name: "coordinated",
        projectID: nil, startedAt: Date(), command: "/usr/local/bin/claude", args: [], env: [:],
        backend: .appServer, chatNativeSessionId: "native-4", token: "token", pid: childPID)
    let adoption = HandoverSession(
        sessionID: sessionID.rawValue.uuidString, agent: "claudeCode",
        holder: try makeHolderRecord(childPID: childPID), appliedSeq: 1, clientState: Data())
    let adopted = AdoptedRunningClient(yieldsTurnStarted: false)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceRoot,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: InMemorySessionStore([descriptor]),
        cliPath: "/tmp/agent-dashboard-test-cli",
        handoverAdoptions: [sessionID: adoption],
        adoptClientFactory: { _, _, _, _, _, _ in adopted })
    let dashboard = DashboardViewModel(environment: environment, orphanReaper: MockOrphanReaper(alivePIDs: []))
    await dashboard.start()
    #expect(dashboard.handoverAdoptedSessionIDs == [sessionID], "前提: 採用が成功している")

    // 中止: 参加者全員の確定点の作成を取り消す。
    await dashboard.cancelHandoverEntries()
    #expect(adopted.cancelCount == 1)

    // 門: 閉じると新しい起動が断られ、開けると戻る。起動中が無ければ待たずに閉じられる。
    #expect(!environment.handoverGate.isClosed)
    #expect(await dashboard.closeHandoverGateAndDrain(timeout: .seconds(2)))
    #expect(environment.handoverGate.isClosed)
    #expect(!environment.handoverGate.beginLaunch())
    dashboard.openHandoverGate()
    #expect(!environment.handoverGate.isClosed)

    // 起動が終わらないまま閉じると、期限で偽（更新を中止する）。門は閉じたまま。
    #expect(environment.handoverGate.beginLaunch())
    #expect(await dashboard.closeHandoverGateAndDrain(timeout: .milliseconds(100)) == false)
    #expect(environment.handoverGate.isClosed)
    environment.handoverGate.endLaunch()
}

@Test @MainActor
func failedAdoption_defersTheNextHandoverWithARecoveryReason() async throws {
    let workspaceRoot = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

    let sessionID = SessionID()
    let childPID: pid_t = 4347
    let descriptor = PersistedSessionDescriptor(
        id: sessionID, kind: .claudeCode, workingDirectory: workspaceRoot.path, name: "adopt-fails-2",
        projectID: nil, startedAt: Date(), command: "/usr/local/bin/claude", args: [], env: [:],
        backend: .appServer, chatNativeSessionId: "native-5", token: "token", pid: childPID)
    let adoption = HandoverSession(
        sessionID: sessionID.rawValue.uuidString, agent: "claudeCode",
        holder: try makeHolderRecord(childPID: childPID), appliedSeq: 1, clientState: Data())
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
        hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
        claudeBinaryPath: "/usr/local/bin/claude",
        pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
        workspaceDirectory: workspaceRoot,
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        sessions: InMemorySessionStore([descriptor]),
        cliPath: "/tmp/agent-dashboard-test-cli",
        handoverAdoptions: [sessionID: adoption],
        adoptClientFactory: { _, _, _, _, _, _ in throw HandoverError.adoptionFailed("holder unreachable") })
    let dashboard = DashboardViewModel(environment: environment, orphanReaper: MockOrphanReaper(alivePIDs: [childPID]))
    await dashboard.start()

    // 復旧待ちの実行があるうちは、新しい確定点で項目を失うので、更新を延期する。
    let reasons = await dashboard.handoverDeferralReasons()
    #expect(reasons.contains { $0.contains("復旧待ち") }, "復旧待ちのセッションが更新を延期しない: \(reasons)")
}

/// 引き継いだ子は旧ホストのトークンを環境に持ち続ける。新ホストは確定点のトークンを同じセッションへ登録し、
/// その子のhook/Control（どちらも`SessionTokenStore`で照合）が届くようにする。採用に失敗しても子は生きているので同じ。
@Test @MainActor
func adoption_registersTheCheckpointTokenSoTheRetainedChildStaysAuthenticated() async throws {
    for adopts in [true, false] {
        let workspaceRoot = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceRoot) }

        let sessionID = SessionID()
        let childPID: pid_t = 4346
        // sessions.jsonはトークンを持たない（`PersistedSessionDescriptor.encode`が省く）。
        let descriptor = PersistedSessionDescriptor(
            id: sessionID, kind: .claudeCode, workingDirectory: workspaceRoot.path, name: "adopt-token",
            projectID: nil, startedAt: Date(), command: "/usr/local/bin/claude", args: [], env: [:],
            backend: .appServer, chatNativeSessionId: "native-token", token: nil, pid: childPID)
        let adoption = HandoverSession(
            sessionID: sessionID.rawValue.uuidString, agent: "claudeCode",
            holder: try makeHolderRecord(childPID: childPID), appliedSeq: 1, clientState: Data(), token: "child-token")
        let adopted = AdoptedRunningClient()
        let tokenStore = SessionTokenStore()

        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let environment = AppEnvironment(
            pty: MockPTYManager(),
            hook: MockHookServer(events: hookStream),
            hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
            claudeSettingsURL: URL(fileURLWithPath: "/tmp/agent-dashboard-test-hooks.json"),
            hookDispatcherPath: "/tmp/agent-dashboard-test-dispatcher.sh",
            claudeBinaryPath: "/usr/local/bin/claude",
            pathEnvironment: "/usr/local/bin:/usr/bin:/bin",
            workspaceDirectory: workspaceRoot,
            controlURL: URL(string: "http://127.0.0.1:9999")!,
            tokenStore: tokenStore,
            messages: MockMessageStore(),
            sessions: InMemorySessionStore([descriptor]),
            cliPath: "/tmp/agent-dashboard-test-cli",
            handoverAdoptions: [sessionID: adoption],
            adoptClientFactory: { _, _, _, _, _, _ in
                guard adopts else { throw HandoverError.adoptionFailed("holder unreachable") }
                return adopted
            })
        let dashboard = DashboardViewModel(environment: environment, orphanReaper: MockOrphanReaper(alivePIDs: [childPID]))

        await dashboard.start()

        #expect(await tokenStore.session(forToken: "child-token") == sessionID, "引き継いだ子のトークンが通らない(adopts=\(adopts))")
        #expect(await tokenStore.token(for: sessionID) == "child-token")
        #expect(await tokenStore.session(forToken: "other-token") == nil)
    }
}
