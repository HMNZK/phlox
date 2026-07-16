import Foundation
import Testing
import AgentDomain
import PTYKit
@testable import DashboardFeature

// MARK: - 受け入れテスト（loopflow task-1・PM 著・実装役は編集不可）
//
// 契約: グリッドビューでワークスペース（Project）を押して絞り込んだとき、
// そのワークスペースに属するサブセッション（.orchestration）も含めた全セッションを
// グリッドへ渡す。未選択（トップレベル）グリッドとサイドバー経路は従来どおり
// サブセッションを除外し続ける（非退行）。
//
// 検証対象は ViewModel の集合算出ロジック（`gridSessionNodes(in:)`）。
// View（DashboardView.filteredGridSessions）がこれを使うことは E2E/runtime で担保する。

@MainActor
private func makeDashboardWithWorkspace() async throws -> (
    dashboard: DashboardViewModel,
    projectID: ProjectID
) {
    let ptyManager = MockPTYManager()
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    let projectFolder = workspaceURL.appendingPathComponent("ws-project", isDirectory: true)
    try FileManager.default.createDirectory(at: projectFolder, withIntermediateDirectories: true)

    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(pty: ptyManager, hookStream: hookStream)

    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let projectID = try #require(
        dashboard.addProject(name: "Workspace Project", directoryPath: projectFolder.path)
    )
    return (dashboard, projectID)
}

@Test @MainActor
func gridSessionNodesInWorkspace_includesOrchestrationSubsessionSpawnedFromParent() async throws {
    let (dashboard, projectID) = try await makeDashboardWithWorkspace()

    // メイン（対話）セッションをワークスペースに作る。
    let parentID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        projectID: projectID,
        launchContext: .interactive
    )
    // メインから spawn したサブセッション。projectID は明示せず親から継承させる
    // （= 実運用で「メインからスポーンされたサブセッション」が同一ワークスペースに入る経路）。
    let subID = try await dashboard.spawnNewSession(
        kind: .claudeCode,
        from: parentID,
        launchContext: .orchestration
    )

    // 前提: サブセッションは親のワークスペースを継承し、.orchestration である。
    try #require(dashboard.sessionNode(id: subID)?.projectID == projectID)
    try #require(dashboard.sessionNode(id: subID)?.launchContext == .orchestration)

    // 事後条件: ワークスペースを押したときのグリッド集合は親とサブの両方を含む。
    let gridIDs = dashboard.gridSessionNodes(in: projectID).map(\.id)
    #expect(gridIDs.contains(parentID))
    #expect(gridIDs.contains(subID))
}

@Test @MainActor
func gridSessionNodesInWorkspace_doesNotChangeUnfilteredGridOrSidebar() async throws {
    let (dashboard, projectID) = try await makeDashboardWithWorkspace()

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

    // 非退行: 未選択（トップレベル）グリッドはサブセッションを除外し続ける。
    #expect(dashboard.gridVisibleSessionNodes.map(\.id).contains(parentID))
    #expect(!dashboard.gridVisibleSessionNodes.map(\.id).contains(subID))

    // 非退行: サイドバー・削除・ナビ用の sessionNodes(in:) はサブセッションを除外し続ける。
    #expect(dashboard.sessionNodes(in: projectID).map(\.id).contains(parentID))
    #expect(!dashboard.sessionNodes(in: projectID).map(\.id).contains(subID))
}

@Test @MainActor
func gridSessionNodesInWorkspace_scopesToTheSelectedWorkspaceOnly() async throws {
    let (dashboard, projectAID) = try await makeDashboardWithWorkspace()

    // 別ワークスペース B を追加。
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    let folderB = workspaceURL.appendingPathComponent("ws-project-b", isDirectory: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
    let projectBID = try #require(
        dashboard.addProject(name: "Workspace B", directoryPath: folderB.path)
    )

    // A に親＋サブ、B に親を作る。
    let parentA = try await dashboard.spawnNewSession(
        kind: .claudeCode, projectID: projectAID, launchContext: .interactive
    )
    let subA = try await dashboard.spawnNewSession(
        kind: .claudeCode, from: parentA, launchContext: .orchestration
    )
    let parentB = try await dashboard.spawnNewSession(
        kind: .claudeCode, projectID: projectBID, launchContext: .interactive
    )

    // A を押したときのグリッド集合は A の親＋サブのみ。B のセッションは混ざらない。
    let idsA = dashboard.gridSessionNodes(in: projectAID).map(\.id)
    #expect(idsA.contains(parentA))
    #expect(idsA.contains(subA))
    #expect(!idsA.contains(parentB))
}
