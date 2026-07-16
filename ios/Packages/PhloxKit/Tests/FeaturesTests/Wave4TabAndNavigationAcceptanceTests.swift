import Testing
@testable import Features

/// wave-4 task-1 受け入れテスト（PM 著・凍結。実装役は編集禁止 — tasks/task-1.md）。
/// 契約: 下部タブバーから「概要（overview）」を廃止し、AppTab は sessions/settings/usage の3つ（順序保持）。
@Suite struct Wave4TabAndNavigationAcceptanceTests {
    @Test func overviewTabRemovedFromAppTab() {
        #expect(AppTab.allCases == [.sessions, .settings, .usage])
    }
}
