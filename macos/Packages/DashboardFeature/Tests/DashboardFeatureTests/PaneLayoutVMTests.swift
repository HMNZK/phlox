// DashboardViewModel の分割ツリー（永続ツリー・実効ツリー・操作の書き込み経路）。
// 永続化層は PaneLayoutStoreTests。
//
// 中核: 絞り込み（表示セッション選択・ワークスペース絞り込み）は一時的な表示制御であって
// レイアウト編集ではない。永続ツリーは隠れたセッションの leaf も保持し、描画時に可視集合で刈り込む。
// ここが破れると「隠したセッションが元の位置に戻らない」。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("PaneLayout VM")
struct PaneLayoutVMTests {

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

    // MARK: - paneLayoutForDisplay（純読み取り）

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

    // MARK: - 絞り込みは永続ツリーを書き換えない

    @Test @MainActor func hidingSession_doesNotMutatePersistedLayout() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboardWithSessions(ws, count: 3)

        let persistedBefore = dashboard.paneLayout
        dashboard.gridSessionSelection = Set([ids[0], ids[2]])

        #expect(dashboard.paneLayout == persistedBefore,
                "表示セッション選択の変更で永続ツリーが書き換わってはいけない")
        #expect(Set(dashboard.paneLayoutForDisplay().sessions) == Set([ids[0], ids[2]]),
                "実効ツリーからは隠れたセッションが消える")
    }

    @Test @MainActor func hidingThenShowingSession_restoresOriginalPosition() async throws {
        // 隠して戻したら元の場所に戻る。
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
                "ワークスペース絞り込みの変更で永続ツリーが書き換わってはいけない")
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

    // 同一操作を2回続けて発行しても、2回目で状態が余計に変化しない。
    @Test @MainActor func handlePaneLayoutAction_appliedTwice_isIdempotentAfterFirstChange() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, _) = try await makeDashboardWithSessions(ws, count: 2)

        dashboard.handlePaneLayoutAction(.applyPreset(.columns2))
        let afterFirst = dashboard.paneLayout
        dashboard.handlePaneLayoutAction(.applyPreset(.columns2))
        #expect(dashboard.paneLayout == afterFirst)
    }
}
