import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

private actor LivePIDSpawnGate {
    private var isEnabled = false
    private var observedSessionID: SessionID?
    private var observationContinuation: CheckedContinuation<SessionID, Never>?
    private var resumeContinuation: CheckedContinuation<Void, Never>?

    func enable() {
        isEnabled = true
    }

    func providePID(for sessionID: SessionID) async -> pid_t? {
        guard isEnabled else { return nil }

        if let observationContinuation {
            self.observationContinuation = nil
            observationContinuation.resume(returning: sessionID)
        } else {
            observedSessionID = sessionID
        }

        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
        return nil
    }

    func nextObservedSessionID() async -> SessionID {
        if let observedSessionID {
            self.observedSessionID = nil
            return observedSessionID
        }
        return await withCheckedContinuation { continuation in
            observationContinuation = continuation
        }
    }

    func resume() {
        let continuation = resumeContinuation
        resumeContinuation = nil
        continuation?.resume()
    }
}

@Test
@MainActor
func controlAPISpawn_existingRequesterInheritsParentProject() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            workspaceDirectory: workspaceURL
        )
    )
    await dashboard.start()

    let projectID = try #require(
        dashboard.addProject(name: "Project", directoryPath: projectURL.path)
    )
    let parentID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID
    )
    let childID = try await dashboard.spawnNewSessionFromControlAPI(
        ref: .builtin(.claudeCode),
        requester: parentID,
        backend: .pty,
        workingDirectory: nil,
        projectID: nil
    )

    let child = try #require(dashboard.sessionNode(id: childID))
    #expect(child.projectID == projectID)
    #expect(child.controllable.parentSessionID == parentID)
    #expect(child.launchContext == .orchestration)
}

@Test
@MainActor
func controlAPISpawn_nilRequesterStillUsesSharedRateLimit() async throws {
    let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream
        ),
        rateLimitNow: { fixedNow }
    )
    await dashboard.start()

    for _ in 0..<DashboardViewModel.maxAPISpawnCountPerSecond {
        _ = try await dashboard.spawnNewSessionFromControlAPI(
            ref: .builtin(.claudeCode),
            requester: nil,
            backend: .pty,
            workingDirectory: nil,
            projectID: nil
        )
    }

    await #expect(throws: AgentSpawnError.spawnRateLimited) {
        _ = try await dashboard.spawnNewSessionFromControlAPI(
            ref: .builtin(.claudeCode),
            requester: nil,
            backend: .pty,
            workingDirectory: nil,
            projectID: nil
        )
    }
}

@Test
@MainActor
func controlAPISpawn_requesterRemovedAfterOriginResolutionFallsBackToVisibleRoot() async throws {
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream
        )
    )
    await dashboard.start()

    let requester = try await dashboard.spawnNewSession(kind: .claudeCode)
    let (originResolved, originResolvedContinuation) = AsyncStream<Void>.makeStream()
    let (resumeSpawn, resumeSpawnContinuation) = AsyncStream<Void>.makeStream()
    var originResolvedIterator = originResolved.makeAsyncIterator()

    let spawnTask = Task { @MainActor in
        try await dashboard.spawnNewSessionFromControlAPI(
            ref: .builtin(.claudeCode),
            requester: requester,
            backend: .pty,
            workingDirectory: nil,
            projectID: nil,
            afterOriginResolution: {
                originResolvedContinuation.yield()
                var resumeSpawnIterator = resumeSpawn.makeAsyncIterator()
                _ = await resumeSpawnIterator.next()
            }
        )
    }

    _ = await originResolvedIterator.next()
    #expect(await dashboard.removeSession(requester))
    resumeSpawnContinuation.yield()
    let spawnedID = try await spawnTask.value

    let spawned = try #require(dashboard.sessionNode(id: spawnedID))
    #expect(spawned.controllable.parentSessionID == nil)
    #expect(spawned.launchContext == .remoteUser)
}

@Test
@MainActor
func ptySpawn_removedDuringFinalAwaitDoesNotReturnToPersistence() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let store = InMemorySessionStore()
    let gate = LivePIDSpawnGate()
    let pty = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: pty,
            hookStream: hookStream,
            sessions: store,
            workspaceDirectory: workspaceURL
        ),
        livePIDProvider: { sessionID in
            await gate.providePID(for: sessionID)
        }
    )
    await dashboard.start()

    let parentID = try await dashboard.spawnNewSession(kind: .claudeCode)
    await gate.enable()

    let spawnTask = Task { @MainActor in
        try await dashboard.spawnNewSession(
            kind: .claudeCode,
            from: parentID,
            launchContext: .orchestration
        )
    }

    let childID = await gate.nextObservedSessionID()
    #expect(dashboard.sessionNode(id: childID) != nil)
    #expect(await dashboard.removeSession(parentID))
    await gate.resume()

    await #expect(throws: CancellationError.self) {
        _ = try await spawnTask.value
    }
    let stayedRemoved = await waitUntil(timeoutNanoseconds: 5_000_000_000) {
        let persistedIDs = Set(await store.load().map(\.id))
        return !persistedIDs.contains(parentID) && !persistedIDs.contains(childID)
    }
    #expect(stayedRemoved, "最後の await 後に削除済み子セッションが永続化へ復活した")
    #expect(
        pty.killedIDs.filter { $0 == childID }.count == 2,
        "削除処理と spawn 後ガードの両方で停止し、起動競合後のプロセスを残さない"
    )
}

@Test
@MainActor
func appServerSpawn_removedDuringFinalAwaitDoesNotReturnToPersistence() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let store = InMemorySessionStore()
    let gate = LivePIDSpawnGate()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream,
            sessions: store,
            workspaceDirectory: workspaceURL,
            agentBinaryPaths: [.codex: "/usr/local/bin/codex"],
            appServerClientFactory: { _, _, _, _, _ in
                EventYieldingStructuredClient()
            }
        ),
        livePIDProvider: { sessionID in
            await gate.providePID(for: sessionID)
        }
    )
    await dashboard.start()

    let parentID = try await dashboard.spawnNewSession(kind: .claudeCode)
    await gate.enable()

    let spawnTask = Task { @MainActor in
        try await dashboard.spawnNewSession(
            kind: .codex,
            from: parentID,
            backend: .appServer,
            launchContext: .orchestration
        )
    }

    let childID = await gate.nextObservedSessionID()
    #expect(dashboard.sessionNode(id: childID)?.appServer != nil)
    #expect(await dashboard.removeSession(parentID))
    await gate.resume()

    await #expect(throws: CancellationError.self) {
        _ = try await spawnTask.value
    }
    let stayedRemoved = await waitUntil(timeoutNanoseconds: 5_000_000_000) {
        let persistedIDs = Set(await store.load().map(\.id))
        return !persistedIDs.contains(parentID) && !persistedIDs.contains(childID)
    }
    #expect(stayedRemoved, "appServer 子が最後の await 後に永続化へ復活した")
}
