// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — グリッドサイズごとの配置状態の保持・永続化・アクション処理。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// 凍結する公開面（未実装の間はコンパイル赤＝red 状態）:
// - GridArrangementStore(userDefaults:) / save(_:size:) / load(size:) -> SessionGridArrangement?
// - DashboardViewModel.gridArrangement(size:) -> SessionGridArrangement（純読み取り）
// - DashboardViewModel.handleGridAction(_:size:)（書き込み経路・no-op 安全）
//
// 永続化契約は注入 UserDefaults で分離検証し standard を汚さない。VM の配置 API は
// メモリ上の振る舞いのみ検証する（実 UserDefaults 書き込み経路は実装役の白箱に委ねる）。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("GridArrangement VM acceptance (task-3)")
struct AcceptanceGridArrangementVMTests {

    private func sid(_ n: Int) -> SessionID {
        SessionID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", n))")!)
    }

    @MainActor
    private func makeDashboardWithSessions(
        _ workspaceURL: URL,
        count: Int
    ) async throws -> (DashboardViewModel, [SessionID]) {
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
        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
        var ids: [SessionID] = []
        for _ in 0..<count {
            ids.append(try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID))
        }
        return (dashboard, ids)
    }

    // MARK: - GridArrangementStore（永続化層・注入 UserDefaults で分離）

    @Test func store_roundtripsArrangement() throws {
        let suite = "grid-arrangement-acceptance-roundtrip"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = GridArrangementStore(userDefaults: defaults)
        let arrangement = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)])
        store.save(arrangement, size: 2)
        #expect(store.load(size: 2) == arrangement)
    }

    @Test func store_sizesAreIndependent() throws {
        let suite = "grid-arrangement-acceptance-independent"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = GridArrangementStore(userDefaults: defaults)
        let arrangement = SessionGridArrangement(size: 2).reconciled(with: [sid(0), sid(1)])
        store.save(arrangement, size: 2)
        #expect(store.load(size: 3) == nil)
    }

    // MARK: - DashboardViewModel.gridArrangement（純読み取り・可視セッションで reconcile 済み）

    @Test @MainActor func gridArrangement_placesVisibleSessionsInOrder() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 2)

        let arrangement = dashboard.gridArrangement(size: 2)
        #expect(try #require(arrangement.placement(at: 0)).id == ids[0])
        #expect(try #require(arrangement.placement(at: 1)).id == ids[1])
    }

    @Test @MainActor func gridArrangement_isPureReadIdempotent() async throws {
        // 同じ入力で複数回呼んでも同一（読み取りが状態を変えない代理指標）。
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, _) = try await makeDashboardWithSessions(ws, count: 2)

        let a1 = dashboard.gridArrangement(size: 2)
        let a2 = dashboard.gridArrangement(size: 2)
        #expect(a1 == a2)
    }

    @Test @MainActor func gridArrangement_dropsRemovedSession() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 2)

        _ = await dashboard.removeSession(ids[0])
        let arrangement = dashboard.gridArrangement(size: 2)
        #expect(arrangement.placements[ids[0]] == nil)
        #expect(arrangement.placements[ids[1]] != nil)
    }

    // MARK: - DashboardViewModel.handleGridAction（書き込み経路・no-op 安全）

    @Test @MainActor func handleGridAction_moveUpdatesArrangement() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 2)

        // ids[0]=cell0, ids[1]=cell1。空きセル cell3 へ移動。
        dashboard.handleGridAction(.moveToCell(ids[0], cell: 3), size: 2)
        let arrangement = dashboard.gridArrangement(size: 2)
        #expect(try #require(arrangement.placement(at: 3)).id == ids[0])
    }

    @Test @MainActor func handleGridAction_invalidIsNoOp() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 2)

        // cell1 は ids[1] が占有。ids[0] の move は事前条件不成立で no-op（状態不変・クラッシュしない）。
        let before = dashboard.gridArrangement(size: 2)
        dashboard.handleGridAction(.moveToCell(ids[0], cell: 1), size: 2)
        #expect(dashboard.gridArrangement(size: 2) == before)
    }

    // MARK: - reconcile トリガの網羅（レビュー指摘の恒久化）

    @Test @MainActor func removingFilteredProject_reconcilesFallbackSessions() async throws {
        // フィルタ中プロジェクトを削除したら、フォールバック（全表示）のセッションが配置される。
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let projectAURL = ws.appendingPathComponent("project-a", isDirectory: true)
        let projectBURL = ws.appendingPathComponent("project-b", isDirectory: true)
        try FileManager.default.createDirectory(at: projectAURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: projectBURL, withIntermediateDirectories: true)
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                workspaceDirectory: ws
            )
        )
        await dashboard.start()
        let projectA = try #require(dashboard.addProject(name: "A", directoryPath: projectAURL.path))
        let projectB = try #require(dashboard.addProject(name: "B", directoryPath: projectBURL.path))
        _ = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA)
        let sessionB = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectB)

        dashboard.gridSessionFilterProjectID = projectA
        await dashboard.removeProject(projectA)

        #expect(dashboard.filteredGridSessionNodes(projectID: projectA).map(\.id) == [sessionB])
        #expect(dashboard.gridArrangement(size: 2).placements[sessionB] != nil)
    }

    @Test func store_rejectsSizeMismatchedArrangement() throws {
        // 破損データ（size 0 の空配置が size 2 のキーに入っている）は拒否して nil を返す。
        let suite = "grid-arrangement-acceptance-sizemismatch"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = GridArrangementStore(userDefaults: defaults)
        store.save(SessionGridArrangement(size: 0), size: 2)
        #expect(store.load(size: 2) == nil)
    }
}
