// PM著。wave-4 で概要（overview）タブを廃止したため、overview タブの順序主張・再選択トグルの
// 各テストは supersede した（正本は Wave4TabAndNavigationAcceptanceTests.overviewTabRemovedFromAppTab）。
// 決定は decision-log.md「task-1 波及テスト処理」を参照。
//
// 残置する契約（AppShellViewModel の純ロジック・View 非依存）:
//   - AppTab: CaseIterable, Equatable, Sendable。ケース宣言順 sessions, settings, usage。
//   - AppShellViewModel: @MainActor @Observable final class。
//       - selectedTab: AppTab（変更は selectTab(_:) 経由のみ）。
//       - overview: SessionsOverviewViewModel（既存の grid/single ロジックを保持・再利用）。
//       - selectTab(_:) がタブ選択の唯一のエントリポイント。

import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite struct Wave2AppShellAcceptanceTests {
    private func makeSession(id: String) -> Session {
        Session(
            id: id,
            name: id,
            agent: .claudeCode,
            status: .idle,
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    // MARK: - 選択タブ状態が切り替わる

    @Test func selectingTabChangesSelectedTab() {
        let vm = AppShellViewModel(
            selectedTab: .sessions,
            overview: SessionsOverviewViewModel(sessions: [makeSession(id: "s1")])
        )

        vm.selectTab(.settings)
        #expect(vm.selectedTab == .settings)

        vm.selectTab(.usage)
        #expect(vm.selectedTab == .usage)
    }
}
