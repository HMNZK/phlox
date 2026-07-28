// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — 分割ツリーの保持・永続化・操作処理と、絞り込みとの分離。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// 凍結する公開面（未実装の間はコンパイル赤＝red 状態）:
// - PaneLayoutStore(userDefaults:) / save(_:) / load() -> PaneTree? / storageKey / reconcileBounds
// - DashboardViewModel.paneLayout（永続ツリー・読み取り）
// - DashboardViewModel.paneLayoutForDisplay() -> PaneTree（純読み取り・副作用なし）
// - DashboardViewModel.handlePaneLayoutAction(_:)（ユーザー操作の唯一の書き込み経路）
//
// この run の中核決定 D4: 絞り込み（表示セッション選択・ワークスペース絞り込み）は
// 一時的な表示制御であってレイアウト編集ではない。永続ツリーは隠れたセッションの leaf も
// 保持し、描画時に可視集合で刈り込む。ここが破れると「隠したセッションが元の位置に戻らない」。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("PaneLayout VM acceptance (task-3)")
struct AcceptancePaneLayoutVMTests {

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

    // MARK: - PaneLayoutStore（永続化層・注入 UserDefaults で分離）

    @Test func store_usesTheDedicatedKey() {
        #expect(PaneLayoutStore.storageKey == "phlox.grid.paneLayout")
    }

    @Test func store_reconcileBoundsIsAPositiveSize() {
        #expect(PaneLayoutStore.reconcileBounds.width > 0)
        #expect(PaneLayoutStore.reconcileBounds.height > 0)
    }

    @Test func store_roundtripsTree() throws {
        let suite = "pane-layout-acceptance-roundtrip"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PaneLayoutStore(userDefaults: defaults)
        let tree = PaneLayoutPreset.mainLeftStackRight.tree(for: [sid(0), sid(1), sid(2)])
        store.save(tree)
        #expect(store.load() == tree)
    }

    @Test func store_returnsNilWhenNothingSaved() throws {
        let suite = "pane-layout-acceptance-empty"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(PaneLayoutStore(userDefaults: defaults).load() == nil)
    }

    @Test func store_returnsNilForCorruptDataWithoutCrashing() throws {
        let suite = "pane-layout-acceptance-corrupt"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PaneLayoutStore(userDefaults: defaults)
        for payload in [Data([0x00, 0xff, 0x10]), Data(), Data(#"{"hello":"world"}"#.utf8)] {
            defaults.set(payload, forKey: PaneLayoutStore.storageKey)
            #expect(store.load() == nil, "壊れたデータは nil を返す（クラッシュしない）")
        }
    }

    @Test func store_returnsNilForUnknownSchemaVersion() throws {
        let suite = "pane-layout-acceptance-schema"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PaneLayoutStore(userDefaults: defaults)
        store.save(PaneLayoutPreset.columns2.tree(for: [sid(0), sid(1)]))
        let data = try #require(defaults.data(forKey: PaneLayoutStore.storageKey))
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["schemaVersion"] = 999
        defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: PaneLayoutStore.storageKey)

        #expect(store.load() == nil, "未知の schemaVersion は既定へフォールバックさせる")
    }

    @Test func store_doesNotTouchLegacyArrangementKeys() throws {
        // D5: 旧キー phlox.grid.arrangement.<k> は移行も削除もしない。
        let suite = "pane-layout-acceptance-legacy"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        let legacy = Data("legacy-payload".utf8)
        for size in 1...4 {
            defaults.set(legacy, forKey: "phlox.grid.arrangement.\(size)")
        }
        PaneLayoutStore(userDefaults: defaults).save(
            PaneLayoutPreset.grid2x2.tree(for: (0..<4).map(sid))
        )
        for size in 1...4 {
            #expect(defaults.data(forKey: "phlox.grid.arrangement.\(size)") == legacy,
                    "旧キー \(size) を書き換えない")
        }
    }

    // MARK: - paneLayoutForDisplay（純読み取り・ADR 0010）

    @Test @MainActor func paneLayoutForDisplay_isPureAndIdempotent() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, _) = try await makeDashboardWithSessions(ws, count: 3)

        let persistedBefore = dashboard.paneLayout
        let first = dashboard.paneLayoutForDisplay()
        let second = dashboard.paneLayoutForDisplay()
        let third = dashboard.paneLayoutForDisplay()

        #expect(first == second)
        #expect(second == third)
        #expect(dashboard.paneLayout == persistedBefore, "読み取りが永続ツリーを変えない")
    }

    // MARK: - セッションの増減に追随する

    @Test @MainActor func paneLayout_placesSpawnedSessions() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 3)

        #expect(Set(dashboard.paneLayout.sessions) == Set(ids))
        #expect(Set(dashboard.paneLayoutForDisplay().sessions) == Set(ids))
    }

    @Test @MainActor func paneLayout_dropsRemovedSession() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 3)

        _ = await dashboard.removeSession(ids[0])

        #expect(!dashboard.paneLayout.sessions.contains(ids[0]), "消えたセッションは永続ツリーからも消える")
        #expect(Set(dashboard.paneLayout.sessions) == Set([ids[1], ids[2]]))
    }

    // MARK: - D4 の中核: 絞り込みは永続ツリーを書き換えない

    @Test @MainActor func hidingSession_doesNotMutatePersistedLayout() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 3)

        let persistedBefore = dashboard.paneLayout
        dashboard.gridSessionSelection = Set([ids[0], ids[2]])

        #expect(dashboard.paneLayout == persistedBefore,
                "表示セッション選択の変更で永続ツリーが書き換わってはいけない（D4）")
        #expect(Set(dashboard.paneLayoutForDisplay().sessions) == Set([ids[0], ids[2]]),
                "実効ツリーからは隠れたセッションが消える")
    }

    @Test @MainActor func hidingThenShowingSession_restoresOriginalPosition() async throws {
        // D4 の end-to-end。隠して戻したら元の場所に戻る。
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 3)

        let bounds = CGSize(width: 1200, height: 800)
        let spacing: CGFloat = 8
        let before = dashboard.paneLayoutForDisplay().frames(in: bounds, spacing: spacing)

        dashboard.gridSessionSelection = Set([ids[0], ids[2]])
        #expect(dashboard.paneLayoutForDisplay().sessions.count == 2)

        dashboard.gridSessionSelection = nil
        let after = dashboard.paneLayoutForDisplay().frames(in: bounds, spacing: spacing)

        for id in ids {
            let beforeRect = try #require(before.tiles.first(where: { $0.session == id })?.rect)
            let afterRect = try #require(after.tiles.first(where: { $0.session == id })?.rect)
            #expect(beforeRect == afterRect, "セッション \(id) が元の位置・大きさに戻る")
        }
    }

    @Test @MainActor func changingWorkspaceFilter_doesNotMutatePersistedLayout() async throws {
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
        let sessionA = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectA)
        let sessionB = try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectB)

        let persistedBefore = dashboard.paneLayout
        #expect(Set(persistedBefore.sessions) == Set([sessionA, sessionB]))

        dashboard.gridSessionFilterProjectID = projectA

        #expect(dashboard.paneLayout == persistedBefore,
                "ワークスペース絞り込みの変更で永続ツリーが書き換わってはいけない（D4）")
        #expect(dashboard.paneLayoutForDisplay().sessions == [sessionA],
                "実効ツリーは絞り込み後の集合になる")
    }

    // MARK: - handlePaneLayoutAction（ユーザー操作の書き込み経路）

    @Test @MainActor func handlePaneLayoutAction_applyPresetChangesLayout() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 3)

        dashboard.handlePaneLayoutAction(.applyPreset(.mainLeftStackRight))

        let bounds = CGSize(width: 1000, height: 800)
        let frames = dashboard.paneLayoutForDisplay().frames(in: bounds, spacing: 8)
        #expect(frames.tiles.count == 3)
        #expect(Set(dashboard.paneLayout.sessions) == Set(ids), "セッションを取りこぼさない")

        // 「左半分1枚＋右半分を上下2枚」になっている。
        let sorted = frames.tiles.sorted { $0.rect.minX < $1.rect.minX }
        #expect(abs(sorted[0].rect.height - 800) < 1.0, "左のペインが全高")
        #expect(abs(sorted[1].rect.height - 396) < 1.0, "右のペインは半分の高さ")
        #expect(abs(sorted[2].rect.height - 396) < 1.0, "右のペインは半分の高さ")
    }

    @Test @MainActor func handlePaneLayoutAction_setDividerChangesProportions() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 2)

        dashboard.handlePaneLayoutAction(.applyPreset(.columns2))
        let bounds = CGSize(width: 1000, height: 800)
        let divider = try #require(
            dashboard.paneLayoutForDisplay().frames(in: bounds, spacing: 8).dividers.first
        )

        dashboard.handlePaneLayoutAction(.setDivider(divider.id, leadingFraction: 0.7))

        let after = dashboard.paneLayoutForDisplay().frames(in: bounds, spacing: 8)
        let leading = try #require(after.tiles.first(where: { $0.session == ids[0] })?.rect)
        #expect(abs(leading.width - 992 * 0.7) < 2.0, "比率が反映される (width=\(leading.width))")
    }

    @Test @MainActor func handlePaneLayoutAction_swapExchangesPositions() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 2)

        let bounds = CGSize(width: 1000, height: 800)
        let before = dashboard.paneLayoutForDisplay().frames(in: bounds, spacing: 8)
        let firstRectBefore = try #require(before.tiles.first(where: { $0.session == ids[0] })?.rect)

        dashboard.handlePaneLayoutAction(.swap(ids[0], ids[1]))

        let after = dashboard.paneLayoutForDisplay().frames(in: bounds, spacing: 8)
        let secondRectAfter = try #require(after.tiles.first(where: { $0.session == ids[1] })?.rect)
        #expect(secondRectAfter == firstRectBefore, "位置が入れ替わる")
    }

    @Test @MainActor func handlePaneLayoutAction_unknownTargetIsNoOp() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 2)

        let before = dashboard.paneLayout
        dashboard.handlePaneLayoutAction(.swap(ids[0], sid(999)))
        dashboard.handlePaneLayoutAction(
            .setDivider(PaneDividerID(split: PaneID("nope"), leading: PaneID("x"), trailing: PaneID("y")),
                        leadingFraction: 0.9)
        )
        dashboard.handlePaneLayoutAction(.equalize(PaneID("nope")))
        dashboard.handlePaneLayoutAction(
            .insertBySplitting(session: sid(999), target: ids[0], edge: .trailing)
        )

        #expect(dashboard.paneLayout == before, "無効な操作は状態を変えない（クラッシュもしない）")
    }

    @Test @MainActor func handlePaneLayoutAction_insertBySplittingMovesSession() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 3)

        dashboard.handlePaneLayoutAction(
            .insertBySplitting(session: ids[2], target: ids[0], edge: .bottom)
        )

        #expect(Set(dashboard.paneLayout.sessions) == Set(ids), "重複も欠落もしない")
        let frames = dashboard.paneLayoutForDisplay().frames(in: CGSize(width: 1000, height: 800), spacing: 8)
        let target = try #require(frames.tiles.first(where: { $0.session == ids[0] })?.rect)
        let moved = try #require(frames.tiles.first(where: { $0.session == ids[2] })?.rect)
        #expect(moved.minY > target.minY, "下側へ差し込まれる")
    }

    // MARK: - 旧グリッド経路への非干渉

    @Test @MainActor func legacyGridArrangementStillWorks() async throws {
        // 旧 k×k 経路（撤去は PM がフェーズ4で行う）の挙動を変えていないこと。
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 2)

        #expect(try #require(dashboard.gridArrangement(size: 2).placement(at: 0)).id == ids[0])
        dashboard.handleGridAction(.moveToCell(ids[0], cell: 3), size: 2)
        #expect(try #require(dashboard.gridArrangement(size: 2).placement(at: 3)).id == ids[0])
    }
}
