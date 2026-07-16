import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
@testable import DashboardFeature

// MARK: - kill(remove) authorization

@MainActor
private func makeAuthorizationDashboard(
    sessionStore: any SessionStoreProtocol = NoOpSessionStore()
) async -> DashboardViewModel {
    let ptyManager = MockPTYManager()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        sessions: sessionStore
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()
    return dashboard
}

@Test @MainActor
func removeAuthorization_allowsOwnerAncestorSelfNilAndMissingTarget() async throws {
    let dashboard = await makeAuthorizationDashboard()

    let parent = try await dashboard.spawnNewSession(kind: .claudeCode)
    let child = try await dashboard.spawnNewSession(kind: .claudeCode, from: parent)
    let grandchild = try await dashboard.spawnNewSession(kind: .claudeCode, from: child)
    let sibling = try await dashboard.spawnNewSession(kind: .claudeCode)
    let missing = SessionID()

    #expect(dashboard.isAuthorizedToRemove(child, requester: parent))
    #expect(dashboard.isAuthorizedToRemove(grandchild, requester: parent))
    #expect(!dashboard.isAuthorizedToRemove(grandchild, requester: sibling))
    #expect(dashboard.isAuthorizedToRemove(grandchild, requester: grandchild))
    #expect(dashboard.isAuthorizedToRemove(grandchild, requester: nil))
    #expect(dashboard.isAuthorizedToRemove(missing, requester: sibling))
}

@Test @MainActor
func removeSession_cascadesChildrenInsteadOfReparenting() async throws {
    let sessionStore = InMemorySessionStore()
    let dashboard = await makeAuthorizationDashboard(sessionStore: sessionStore)

    let grandparent = try await dashboard.spawnNewSession(kind: .claudeCode)
    let parent = try await dashboard.spawnNewSession(kind: .claudeCode, from: grandparent)
    let child = try await dashboard.spawnNewSession(kind: .claudeCode, from: parent)
    let grandchild = try await dashboard.spawnNewSession(kind: .claudeCode, from: child)
    let sibling = try await dashboard.spawnNewSession(kind: .claudeCode, from: grandparent)

    #expect(await dashboard.removeSession(parent))

    let remainingIDs = Set(dashboard.sessions.map(\.id))
    #expect(remainingIDs == Set([grandparent, sibling]))
    #expect(dashboard.isAuthorizedToRemove(sibling, requester: grandparent))

    try await waitUntil {
        let stored = await sessionStore.load()
        let storedIDs = Set(stored.map(\.id))
        return storedIDs == Set([grandparent, sibling])
            && stored.first(where: { $0.id == sibling })?.parentSessionID == grandparent
            && stored.first(where: { $0.id == parent }) == nil
            && stored.first(where: { $0.id == child }) == nil
            && stored.first(where: { $0.id == grandchild }) == nil
    }
}

@Test @MainActor
func restorePersistedSessions_preservesParentLinksRegardlessOfOrder() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let root = SessionID()
    let child = SessionID()
    let grandchild = SessionID()
    let sibling = SessionID()
    let sessionStore = InMemorySessionStore([
        makePersistedSessionDescriptor(
            id: grandchild,
            workingDirectory: workspaceURL.appendingPathComponent("grandchild").path,
            parentSessionID: child
        ),
        makePersistedSessionDescriptor(
            id: sibling,
            workingDirectory: workspaceURL.appendingPathComponent("sibling").path
        ),
        makePersistedSessionDescriptor(
            id: root,
            workingDirectory: workspaceURL.appendingPathComponent("root").path
        ),
        makePersistedSessionDescriptor(
            id: child,
            workingDirectory: workspaceURL.appendingPathComponent("child").path,
            parentSessionID: root
        ),
    ])
    let dashboard = await makeAuthorizationDashboard(sessionStore: sessionStore)

    #expect(dashboard.sessions.first { $0.id == child }?.parentSessionID == root)
    #expect(dashboard.sessions.first { $0.id == grandchild }?.parentSessionID == child)
    #expect(dashboard.isAuthorizedToRemove(grandchild, requester: root))
    #expect(!dashboard.isAuthorizedToRemove(grandchild, requester: sibling))
}

@Test @MainActor
func restorePersistedSessions_depthLimitUsesRestoredParentChain() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let root = SessionID()
    let child = SessionID()
    let grandchild = SessionID()
    let greatGrandchild = SessionID()
    let sessionStore = InMemorySessionStore([
        makePersistedSessionDescriptor(
            id: greatGrandchild,
            workingDirectory: workspaceURL.appendingPathComponent("great-grandchild").path,
            parentSessionID: grandchild
        ),
        makePersistedSessionDescriptor(
            id: grandchild,
            workingDirectory: workspaceURL.appendingPathComponent("grandchild").path,
            parentSessionID: child
        ),
        makePersistedSessionDescriptor(
            id: child,
            workingDirectory: workspaceURL.appendingPathComponent("child").path,
            parentSessionID: root
        ),
        makePersistedSessionDescriptor(
            id: root,
            workingDirectory: workspaceURL.appendingPathComponent("root").path
        ),
    ])
    let dashboard = await makeAuthorizationDashboard(sessionStore: sessionStore)

    await #expect(throws: AgentSpawnError.depthLimitExceeded) {
        try await dashboard.spawnNewSession(kind: .claudeCode, from: greatGrandchild)
    }
}

@Test @MainActor
func renameSession_remainsOutsideRemoveAuthorizationScope() async throws {
    let dashboard = await makeAuthorizationDashboard()

    let owner = try await dashboard.spawnNewSession(kind: .claudeCode)
    let target = try await dashboard.spawnNewSession(kind: .claudeCode)

    #expect(!dashboard.isAuthorizedToRemove(target, requester: owner))

    dashboard.renameSession(target, to: "Renamed")

    #expect(dashboard.sessions.first { $0.id == target }?.name == "Renamed")
}
