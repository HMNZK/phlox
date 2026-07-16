import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("GridArrangement VM white-box")
struct GridArrangementVMWhiteboxTests {
    private struct EncodedArrangement: Encodable {
        let size: Int
        let placements: [SessionID: SessionGridArrangement.Region]
    }

    private func isolatedStore(_ name: String) throws -> (GridArrangementStore, UserDefaults, String) {
        let suite = "grid-arrangement-whitebox-\(name)-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (GridArrangementStore(userDefaults: defaults), defaults, suite)
    }

    @Test func store_rejectsOutOfBoundsPersistedRegion() throws {
        let (store, defaults, suite) = try isolatedStore("invalid-region")
        defer { defaults.removePersistentDomain(forName: suite) }
        let id = SessionID(rawValue: UUID())
        let invalid = EncodedArrangement(
            size: 2,
            placements: [id: .init(anchor: 4, rowSpan: 1, colSpan: 1)]
        )
        defaults.set(
            try JSONEncoder().encode(invalid),
            forKey: "phlox.grid.arrangement.2"
        )

        #expect(store.load(size: 2) == nil)
    }

    @Test @MainActor func actionPersistsOnlyItsGridSize() async throws {
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let (store, defaults, suite) = try isolatedStore("vm-action")
        defer { defaults.removePersistentDomain(forName: suite) }
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                workspaceDirectory: workspaceURL
            ),
            gridArrangementStore: store
        )
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
        let id = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

        dashboard.handleGridAction(.moveToCell(id, cell: 3), size: 2)

        #expect(try #require(store.load(size: 2)?.placement(at: 3)).id == id)
        #expect(store.load(size: 3)?.placement(at: 3)?.id != id)
    }

    @Test @MainActor func selectionChangeReconcilesBeforeRead() async throws {
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let (store, defaults, suite) = try isolatedStore("selection")
        defer { defaults.removePersistentDomain(forName: suite) }
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                workspaceDirectory: workspaceURL
            ),
            gridArrangementStore: store
        )
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
        let first = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let second = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

        dashboard.gridSessionSelection = [second]

        let arrangement = dashboard.gridArrangement(size: 2)
        #expect(arrangement.placements[first] == nil)
        #expect(arrangement.placements[second] != nil)
    }

    @Test @MainActor func allGridActionsDelegateToArrangementOperations() async throws {
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)

        let (store, defaults, suite) = try isolatedStore("all-actions")
        defer { defaults.removePersistentDomain(forName: suite) }
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                workspaceDirectory: workspaceURL
            ),
            gridArrangementStore: store
        )
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
        let first = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)
        let second = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID)

        dashboard.handleGridAction(.swap(first, second), size: 2)
        #expect(try #require(dashboard.gridArrangement(size: 2).placement(at: 0)).id == second)
        dashboard.handleGridAction(.swap(first, second), size: 2)

        dashboard.handleGridAction(.mergeRight(first), size: 2)
        #expect(dashboard.gridArrangement(size: 2).placements[first]?.colSpan == 2)
        dashboard.handleGridAction(.unmerge(first), size: 2)
        #expect(dashboard.gridArrangement(size: 2).placements[first]?.colSpan == 1)

        dashboard.handleGridAction(.mergeDown(first), size: 2)
        #expect(dashboard.gridArrangement(size: 2).placements[first]?.rowSpan == 2)
    }

    @Test @MainActor func startupDropsPersistedSessionThatNoLongerExists() async throws {
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }
        let (store, defaults, suite) = try isolatedStore("deleted-session")
        defer { defaults.removePersistentDomain(forName: suite) }
        let deletedID = SessionID(rawValue: UUID())
        store.save(
            SessionGridArrangement(size: 2).reconciled(with: [deletedID]),
            size: 2
        )
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                workspaceDirectory: workspaceURL
            ),
            gridArrangementStore: store
        )

        await dashboard.start()

        #expect(dashboard.gridArrangement(size: 2).placements[deletedID] == nil)
        #expect(store.load(size: 2)?.placements[deletedID] == nil)
    }
}
