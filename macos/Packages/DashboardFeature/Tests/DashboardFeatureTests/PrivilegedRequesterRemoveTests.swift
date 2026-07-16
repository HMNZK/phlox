import Foundation
import Testing
import AgentDomain
import HookServer
import MessageStore
import PTYKit
@testable import DashboardFeature

// MARK: - DashboardViewModel privileged requester wiring (MC-2b)

/// モバイルトークンの安定 requester（どの木にも属さない固定 SessionID）に
/// `setPrivilegedRequester` で特権を付与し、全 remove（cascade 含む）が通ることを検証する。

@MainActor
private func makePrivilegedDashboard(
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
func privilegedRequester_setEnablesRemovalOfNonDescendantRootAndUnknown() async throws {
    let dashboard = await makePrivilegedDashboard()

    // モバイルトークン requester は spawn された木の外側の固定 ID。
    let mobile = SessionID()
    let root = try await dashboard.spawnNewSession(kind: .claudeCode)
    let child = try await dashboard.spawnNewSession(kind: .claudeCode, from: root)
    let unknown = SessionID()

    // 設定前: 非子孫の mobile は root・child の削除を許可されない（既定挙動）。
    #expect(!dashboard.isAuthorizedToRemove(root, requester: mobile))
    #expect(!dashboard.isAuthorizedToRemove(child, requester: mobile))

    dashboard.setPrivilegedRequester(mobile)

    // 設定後: root・非子孫の任意セッション・unknown のいずれも remove 許可。
    #expect(dashboard.isAuthorizedToRemove(root, requester: mobile))
    #expect(dashboard.isAuthorizedToRemove(child, requester: mobile))
    #expect(dashboard.isAuthorizedToRemove(unknown, requester: mobile))
}

@Test @MainActor
func privilegedRequester_isLimitedToRemoveOnlyAndDoesNotElevateOthers() async throws {
    let dashboard = await makePrivilegedDashboard()

    let mobile = SessionID()
    let root = try await dashboard.spawnNewSession(kind: .claudeCode)
    let sibling = try await dashboard.spawnNewSession(kind: .claudeCode)

    dashboard.setPrivilegedRequester(mobile)

    // 特権 ID と一致しない sibling は従来どおり ancestor 範囲のみ（緩めない）。
    #expect(!dashboard.isAuthorizedToRemove(root, requester: sibling))
    // nil requester は従来どおり許可（特権設定の有無に依存しない）。
    #expect(dashboard.isAuthorizedToRemove(root, requester: nil))
}

@Test @MainActor
func privilegedRequester_cascadeDeleteActuallyRemovesDescendants() async throws {
    let sessionStore = InMemorySessionStore()
    let dashboard = await makePrivilegedDashboard(sessionStore: sessionStore)

    let mobile = SessionID()
    // mobile は木の外側。grandparent..grandchild の連鎖を作る。
    let grandparent = try await dashboard.spawnNewSession(kind: .claudeCode)
    let parent = try await dashboard.spawnNewSession(kind: .claudeCode, from: grandparent)
    let child = try await dashboard.spawnNewSession(kind: .claudeCode, from: parent)
    let grandchild = try await dashboard.spawnNewSession(kind: .claudeCode, from: child)
    let sibling = try await dashboard.spawnNewSession(kind: .claudeCode, from: grandparent)

    dashboard.setPrivilegedRequester(mobile)

    // 認可は mobile（非子孫）経由でも grandparent（root）を削除できる。
    #expect(dashboard.isAuthorizedToRemove(grandparent, requester: mobile))

    // 実際に root を cascade delete すると、子孫 parent/child/grandchild/sibling が全て消える。
    #expect(await dashboard.removeSession(grandparent))

    let remainingIDs = Set(dashboard.sessions.map(\.id))
    #expect(remainingIDs.isEmpty)

    try await waitUntil {
        let stored = await sessionStore.load()
        let storedIDs = Set(stored.map(\.id))
        return storedIDs.isDisjoint(with: Set([grandparent, parent, child, grandchild, sibling]))
            && stored.first(where: { $0.id == parent }) == nil
            && stored.first(where: { $0.id == child }) == nil
            && stored.first(where: { $0.id == grandchild }) == nil
            && stored.first(where: { $0.id == sibling }) == nil
    }
}

@Test @MainActor
func privilegedRequester_settingNilRestoresAncestorBehavior() async throws {
    let dashboard = await makePrivilegedDashboard()

    let mobile = SessionID()
    let root = try await dashboard.spawnNewSession(kind: .claudeCode)

    dashboard.setPrivilegedRequester(mobile)
    #expect(dashboard.isAuthorizedToRemove(root, requester: mobile))

    // 特権を解除すると、非子孫 mobile は再び root を削除できない（既定挙動へ復帰）。
    dashboard.setPrivilegedRequester(nil)
    #expect(!dashboard.isAuthorizedToRemove(root, requester: mobile))
}
