import Foundation
import Testing
import AgentDomain
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

// 契約: ワークスペース（Project）で絞り込んだグリッドは、そのワークスペースの
// .orchestration サブセッション（CLI spawn の子）もタイルとして描く。
// GridWorkspaceSubsessionAcceptanceTests は集合算出（gridSessionNodes(in:)）だけを見ていたため、
// 描画経路（filteredGridSessionNodes / paneLayoutForDisplay）で再度除外されても検出できなかった。
// ここは描画経路そのものを凍結する。

@Suite("ワークスペース絞り込みグリッドの描画経路（サブセッション）")
struct GridWorkspaceSubsessionPaneAcceptanceTests {

    @MainActor
    private func makeDashboard() async throws -> (DashboardViewModel, ProjectID, URL, String) {
        let workspaceURL = try makeTemporaryWorkspaceRoot()
        let projectFolder = workspaceURL.appendingPathComponent("ws-project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let suiteName = "phlox.test.gridSubsessionPane.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                workspaceDirectory: workspaceURL
            ),
            paneLayoutStore: PaneLayoutStore(userDefaults: defaults)
        )
        await dashboard.start()
        let projectID = try #require(
            dashboard.addProject(name: "Workspace Project", directoryPath: projectFolder.path)
        )
        return (dashboard, projectID, workspaceURL, suiteName)
    }

    @Test @MainActor
    func filteredGrid_showsOrchestrationSubsessionAsTile() async throws {
        let (dashboard, projectID, workspace, suiteName) = try await makeDashboard()
        defer {
            cleanupTemporaryWorkspaceRoot(workspace)
            UserDefaults().removePersistentDomain(forName: suiteName)
        }

        let parentID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )
        let subID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            from: parentID,
            launchContext: .orchestration
        )
        try #require(dashboard.sessionNode(id: subID)?.launchContext == .orchestration)

        // ワークスペース絞り込み中: 一覧にもペイン木（＝描画されるタイル）にも子が居る。
        dashboard.gridSessionFilterProjectID = projectID
        let filtered = dashboard.filteredGridSessionNodes(projectID: projectID).map(\.id)
        #expect(filtered.contains(parentID))
        #expect(filtered.contains(subID))

        let panes = dashboard.paneLayoutForDisplay().sessions
        #expect(panes.contains(parentID))
        #expect(panes.contains(subID))
    }

    @Test @MainActor
    func unfilteredGrid_stillHidesOrchestrationSubsession() async throws {
        let (dashboard, projectID, workspace, suiteName) = try await makeDashboard()
        defer {
            cleanupTemporaryWorkspaceRoot(workspace)
            UserDefaults().removePersistentDomain(forName: suiteName)
        }

        let parentID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            projectID: projectID,
            launchContext: .interactive
        )
        let subID = try await dashboard.spawnNewSession(
            kind: .claudeCode,
            from: parentID,
            launchContext: .orchestration
        )

        dashboard.gridSessionFilterProjectID = nil
        let filtered = dashboard.filteredGridSessionNodes(projectID: nil).map(\.id)
        #expect(filtered.contains(parentID))
        #expect(!filtered.contains(subID))

        let panes = dashboard.paneLayoutForDisplay().sessions
        #expect(panes.contains(parentID))
        #expect(!panes.contains(subID))
    }
}
