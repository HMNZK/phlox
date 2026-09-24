import Foundation
import Testing
import AgentDomain
import DesignSystem
@testable import DashboardFeature
@testable import SessionFeature

// 06 グリッド: タイルの大きさ・見出しの文言・左上からの番号・グリッドから外す・レイアウト名・範囲外の対応待ち。

@Suite("Grid tile redesign (06)")
struct GridTileRedesignTests {

    @MainActor
    private func makeDashboard(
        _ workspaceURL: URL,
        count: Int,
        defaults: UserDefaults
    ) async throws -> (DashboardViewModel, [SessionID]) {
        let projectURL = workspaceURL.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
        let dashboard = DashboardViewModel(
            environment: makeTestEnvironment(
                pty: MockPTYManager(),
                hookStream: hookStream,
                workspaceDirectory: workspaceURL
            ),
            paneLayoutStore: PaneLayoutStore(userDefaults: defaults)
        )
        await dashboard.start()
        let projectID = try #require(dashboard.addProject(name: "Project", directoryPath: projectURL.path))
        var ids: [SessionID] = []
        for _ in 0..<count {
            ids.append(try await dashboard.spawnNewSession(kind: .claudeCode, projectID: projectID))
        }
        return (dashboard, ids)
    }

    private func suite(_ name: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: "grid-tile-redesign-\(name)"))
        defaults.removePersistentDomain(forName: "grid-tile-redesign-\(name)")
        return defaults
    }

    @Test func tileSize_followsTheThresholds() {
        #expect(GridTileSize(CGSize(width: 480, height: 330)) == .large)
        #expect(GridTileSize(CGSize(width: 479, height: 600)) == .medium)
        #expect(GridTileSize(CGSize(width: 800, height: 329)) == .medium)
        #expect(GridTileSize(CGSize(width: 249, height: 600)) == .small)
        #expect(GridTileSize(CGSize(width: 600, height: 174)) == .small)
        // 中は高さ 300pt 以上なら会話の列（入力欄つき）を出す。小は出さない。
        #expect(GridTileSize.showsConversationColumn(CGSize(width: 380, height: 300)))
        #expect(!GridTileSize.showsConversationColumn(CGSize(width: 380, height: 299)))
        #expect(!GridTileSize.showsConversationColumn(CGSize(width: 240, height: 600)))
        // 子タブは小では隠し、幅 380pt 以上だけ。
        #expect(GridTileSize.showsChildTabs(CGSize(width: 380, height: 200)))
        #expect(!GridTileSize.showsChildTabs(CGSize(width: 379, height: 400)))
        #expect(!GridTileSize.showsChildTabs(CGSize(width: 600, height: 170)))
    }

    @Test func stateLabel_showsElapsedOnlyForAttention() {
        let ja = Locale(identifier: "ja")
        let now = Date()
        let since = now.addingTimeInterval(-180)
        #expect(GridTileText.stateLabel(state: .approval, since: since, silence: nil, now: now, locale: ja) == "承認待ち · 3分")
        #expect(GridTileText.stateLabel(state: .stalled, since: since, silence: 134, now: now, locale: ja) == "無応答 · 2分")
        #expect(GridTileText.stateLabel(state: .running, since: since, silence: nil, now: now, locale: ja) == "実行中")
        #expect(GridTileText.stateLabel(state: .question, since: nil, silence: nil, now: now, locale: ja) == "質問待ち")
    }

    @Test func accessibilityLabel_matchesTheMockOrder() {
        let ja = Locale(identifier: "ja")
        #expect(GridTileText.accessibilityLabel(title: "承認 API", state: "承認待ち", elapsed: "3分", isFocused: true, locale: ja)
            == "承認 API、承認待ち、3分、フォーカス中")
        #expect(GridTileText.accessibilityLabel(title: "承認 API", state: "待機", elapsed: nil, isFocused: false, locale: ja)
            == "承認 API、待機")
    }

    @Test @MainActor func tileOrder_readsFromTopLeft_andDrivesCommandNumbers() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboard(ws, count: 3, defaults: try suite("order"))
        dashboard.handlePaneLayoutAction(.applyPreset(.mainLeftStackRight))
        // 左のメイン → 右上 → 右下。
        let order = dashboard.gridTileOrder()
        #expect(order == dashboard.paneLayout.sessions)
        #expect(Set(order) == Set(ids))

        let router = AppRouter(selectedSession: ids[0])
        router.viewMode = .grid
        #expect(dashboard.numberedTabSessionIDs(router: router) == order)

        // 入れ替えると番号も入れ替わる（見出しの ⌘ 番号と ⌘1–9 が同じ並びを読む）。
        dashboard.handlePaneLayoutAction(.swap(order[0], order[2]))
        #expect(dashboard.gridTileOrder() == [order[2], order[1], order[0]])
    }

    @Test @MainActor func removeFromGrid_hidesTheTileButKeepsTheSession() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let (dashboard, ids) = try await makeDashboard(ws, count: 3, defaults: try suite("remove"))
        let order = dashboard.gridTileOrder()

        let next = dashboard.removeFromGrid(order[1])
        #expect(next == order[2])
        #expect(dashboard.gridTileOrder() == [order[0], order[2]])
        #expect(dashboard.sessionNode(id: order[1]) != nil)
        #expect(dashboard.gridSessionSelection == Set([order[0], order[2]]))

        #expect(dashboard.removeFromGrid(order[2]) == order[0])
        // 最後の 1 枚は外さない（選択が空になると全件表示に戻ってしまうため）。
        #expect(dashboard.removeFromGrid(order[0]) == nil)
        #expect(dashboard.gridTileOrder() == [order[0]])
        // 表示していないセッションは何もしない。
        #expect(dashboard.removeFromGrid(ids.first { $0 != order[0] }!) == nil)
    }

    @Test @MainActor func layoutName_marksAdjustedAfterManualChange_andPersists() async throws {
        let ws = try makeTemporaryWorkspaceRoot()
        defer { cleanupTemporaryWorkspaceRoot(ws) }
        let defaults = try suite("preset")
        let (dashboard, _) = try await makeDashboard(ws, count: 3, defaults: defaults)
        #expect(dashboard.paneLayoutPresetState == .init(preset: .balanced, isAdjusted: false))

        dashboard.handlePaneLayoutAction(.applyPreset(.columns3))
        #expect(dashboard.paneLayoutPresetState == .init(preset: .columns3, isAdjusted: false))

        let order = dashboard.gridTileOrder()
        dashboard.handlePaneLayoutAction(.swap(order[0], order[1]))
        #expect(dashboard.paneLayoutPresetState == .init(preset: .columns3, isAdjusted: true))
        #expect(PaneLayoutStore(userDefaults: defaults).loadPresetState() == .init(preset: .columns3, isAdjusted: true))

        // 何も変わらない操作では「調整済み」にしない。プリセットを選び直すと外れる。
        dashboard.handlePaneLayoutAction(.applyPreset(.columns3))
        #expect(dashboard.paneLayoutPresetState.isAdjusted == false)
        dashboard.handlePaneLayoutAction(.swap(order[0], SessionID()))
        #expect(dashboard.paneLayoutPresetState.isAdjusted == false)
    }

    @Test func layoutName_withoutRecord_comparesSavedLayoutWithBalanced() throws {
        let ids = [SessionID(), SessionID(), SessionID()]
        let defaults = try suite("preset-migration")
        let store = PaneLayoutStore(userDefaults: defaults)
        #expect(store.loadPresetState() == .init(preset: .balanced, isAdjusted: false))
        store.save(PaneLayoutPreset.balanced.tree(for: ids))
        #expect(store.loadPresetState() == .init(preset: .balanced, isAdjusted: false))
        store.save(PaneLayoutPreset.columns3.tree(for: ids))
        #expect(store.loadPresetState() == .init(preset: .balanced, isAdjusted: true))
    }

    @Test func outOfScope_countsByStateInFixedOrder() {
        let entries = [
            AttentionEntry(id: SessionID(), kind: .stalled, since: nil),
            AttentionEntry(id: SessionID(), kind: .error, since: nil),
            AttentionEntry(id: SessionID(), kind: .stalled, since: nil),
        ]
        let counts = GridOutOfScopeAttention.counts(entries)
        #expect(counts.map(\.kind) == [.error, .stalled])
        #expect(counts.map(\.count) == [1, 2])
    }

    @Test @MainActor func commandW_inGridRemovesTheTile() {
        let session = SessionID()
        let router = AppRouter(selectedSession: session)
        router.viewMode = .grid
        #expect(router.tabs.closeTarget(selectedSession: session, viewMode: .grid) == .gridTile(session))
        #expect(router.requestClose())
        #expect(router.tabRequest == .removeFromGrid(session))
    }
}
