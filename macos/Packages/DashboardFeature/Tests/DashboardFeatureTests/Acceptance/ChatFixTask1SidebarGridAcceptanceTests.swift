// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — viewMode 切替でサイドバー表示状態を暗黙に変更しない。
// 保留中は LOOPFLOW_PENDING_TASK1=1 で suite ごとスキップできる（PM の検証運用用。実装役は使わない）。

import Foundation
import Testing
@testable import DashboardFeature

@Suite(
    "ChatFix task-1: グリッド切替でサイドバーを勝手に閉じない",
    .enabled(if: ProcessInfo.processInfo.environment["LOOPFLOW_PENDING_TASK1"] != "1")
)
struct ChatFixTask1SidebarGridAcceptanceTests {

    // 核心の契約: grid への切替は現在の表示状態を保存する（フィルタ有無に依らない）。
    @Test
    func gridSwitchPreservesCurrentVisibility() {
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .grid, currentVisible: true, hasGridFilter: false) == true)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .grid, currentVisible: false, hasGridFilter: false) == false)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .grid, currentVisible: true, hasGridFilter: true) == true)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .grid, currentVisible: false, hasGridFilter: true) == false)
    }

    // 既存意図の保存: single / team への切替はサイドバーを開く（現行挙動の維持）。
    @Test
    func singleAndTeamSwitchKeepForcedOpen() {
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .single, currentVisible: false, hasGridFilter: false) == true)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .single, currentVisible: true, hasGridFilter: false) == true)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .team, currentVisible: false, hasGridFilter: false) == true)
        #expect(SidebarVisibilityPolicy.visibility(afterSwitchingTo: .team, currentVisible: true, hasGridFilter: true) == true)
    }
}
