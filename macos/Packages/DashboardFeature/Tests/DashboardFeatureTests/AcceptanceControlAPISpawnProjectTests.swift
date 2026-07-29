import Foundation
import Testing
import AgentDomain
import HookServer
import PTYKit
@testable import DashboardFeature
@testable import SessionFeature

/// task-1 受け入れテスト（PM 著・凍結。アサーションの変更は禁止。ハーネス欠陥を
/// 発見した場合は PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
///
/// バグ: iOS から作成したセッションが macOS サイドバーの「その他」に落ちる。
/// 「その他」は `unassignedSessionNodes`（`projectID == nil`）で決まるのに、Control API 経由の
/// spawn には projectID を渡す口が無く必ず nil になっていた。
///
/// 契約（tasks/wire-contract.md §2）: `spawnNewSessionFromControlAPI` が `projectID` を受け取り、
///  - 指定されたプロジェクトの配下にセッションを作る（「その他」に出ない）
///  - CWD をそのプロジェクトの directoryPath にする
///  - 存在しない projectID は `AgentSpawnError.unknownProject` を throw する（→ 422）
///  - projectID 省略時は従来どおり未所属（後方互換）

@Test("Control API 経由 spawn は指定 projectID のプロジェクト配下に作る")
@MainActor
func controlAPISpawn_withProjectID_assignsToThatProject() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("gardenia", isDirectory: true)
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
        dashboard.addProject(name: "Gardenia", directoryPath: projectURL.path)
    )

    let spawnedID = try await dashboard.spawnNewSessionFromControlAPI(
        ref: .builtin(.claudeCode),
        requester: nil,
        backend: .pty,
        workingDirectory: nil,
        projectID: projectID
    )

    let spawned = try #require(dashboard.sessionNode(id: spawnedID))
    #expect(spawned.projectID == projectID)
    #expect(
        dashboard.unassignedSessionNodes.contains { $0.id == spawnedID } == false,
        "projectID 指定で作ったセッションがサイドバーの「その他」に出ている"
    )
    #expect(
        spawned.workspaceName == "gardenia",
        "CWD がプロジェクトの directoryPath から解決されていない"
    )
}

@Test("projectID 省略時は従来どおり未所属で作る（後方互換）")
@MainActor
func controlAPISpawn_withoutProjectID_staysUnassigned() async throws {
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream
        )
    )
    await dashboard.start()

    let spawnedID = try await dashboard.spawnNewSessionFromControlAPI(
        ref: .builtin(.claudeCode),
        requester: nil,
        backend: .pty,
        workingDirectory: nil,
        projectID: nil
    )

    let spawned = try #require(dashboard.sessionNode(id: spawnedID))
    #expect(spawned.projectID == nil)
}

@Test("存在しない projectID は unknownProject を投げ、セッションを作らない")
@MainActor
func controlAPISpawn_withUnknownProjectID_throwsAndCreatesNothing() async throws {
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let dashboard = DashboardViewModel(
        environment: makeTestEnvironment(
            pty: MockPTYManager(),
            hookStream: hookStream
        )
    )
    await dashboard.start()

    let countBefore = dashboard.sessionNodes.count

    await #expect(throws: AgentSpawnError.unknownProject) {
        _ = try await dashboard.spawnNewSessionFromControlAPI(
            ref: .builtin(.claudeCode),
            requester: nil,
            backend: .pty,
            workingDirectory: nil,
            projectID: ProjectID()
        )
    }

    #expect(dashboard.sessionNodes.count == countBefore, "拒否したのにセッションが作られている")
}

@Test("workingDirectory を明示したときはそちらを CWD に使い、所属だけ projectID で決める")
@MainActor
func controlAPISpawn_workingDirectoryTakesPrecedenceOverProjectDirectory() async throws {
    let workspaceURL = try makeTemporaryWorkspaceRoot()
    defer { cleanupTemporaryWorkspaceRoot(workspaceURL) }

    let projectURL = workspaceURL.appendingPathComponent("gardenia", isDirectory: true)
    let overrideURL = workspaceURL.appendingPathComponent("override-cwd", isDirectory: true)
    try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: overrideURL, withIntermediateDirectories: true)

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
        dashboard.addProject(name: "Gardenia", directoryPath: projectURL.path)
    )

    let spawnedID = try await dashboard.spawnNewSessionFromControlAPI(
        ref: .builtin(.claudeCode),
        requester: nil,
        backend: .pty,
        workingDirectory: overrideURL.path,
        projectID: projectID
    )

    let spawned = try #require(dashboard.sessionNode(id: spawnedID))
    #expect(spawned.projectID == projectID)
    #expect(spawned.workspaceName == "override-cwd")
}
