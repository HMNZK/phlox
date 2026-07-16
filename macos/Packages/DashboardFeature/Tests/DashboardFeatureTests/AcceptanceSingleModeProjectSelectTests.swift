// task-1（PM 著・凍結受け入れテスト・編集禁止）:
// single モードでプロジェクトを選択したら「新規セッション開始画面」を表示する挙動。
// grid モードでは従来のグリッド絞り込みトグルを維持する。
import Testing
import AgentDomain
@testable import DashboardFeature

@MainActor
@Test func selectProjectFromSidebar_inSingleMode_clearsSessionAndShowsStartCards() {
    let router = AppRouter(viewMode: .single)
    // 既にセッションを開いている状態から始める（ゲート①: single では閉じて新規画面を出す）。
    router.selectedSession = SessionID()
    let project = ProjectID()

    router.selectProjectFromSidebar(project)

    // グリッドに遷移しない・プロジェクト選択済み・セッションは閉じる。
    #expect(router.viewMode == .single)
    #expect(router.selectedProjectID == project)
    #expect(router.selectedSession == nil)

    // → 新規セッション開始画面（AgentStartCards）が表示される条件を満たす。
    #expect(StartAreaPolicy.content(
        hasSelectedProject: router.selectedProjectID != nil,
        hasSelectedSession: router.selectedSession != nil
    ) == .agentStartCards)
}

@MainActor
@Test func selectProjectFromSidebar_inGridMode_togglesFilterAndStaysGrid() {
    let router = AppRouter(viewMode: .grid)
    let project = ProjectID()

    // 1回目: グリッド絞り込みをこのプロジェクトに設定し、grid のまま。
    router.selectProjectFromSidebar(project)
    #expect(router.viewMode == .grid)
    #expect(router.selectedProjectID == project)
    #expect(router.gridFilterProjectID == project)

    // 2回目（同一プロジェクト）: 従来のトグル挙動で絞り込み解除。
    router.selectProjectFromSidebar(project)
    #expect(router.gridFilterProjectID == nil)
    #expect(router.viewMode == .grid)
}
