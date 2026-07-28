// task-5 白箱テスト（実装役著）。PaneLayoutPresetMenu 自体の振る舞いを、
// 受け入れテストがソーススキャンで見ていない観点から補う。

import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature
@testable import SessionFeature

@Suite("PaneLayoutPresetMenu whitebox")
struct PaneLayoutPresetMenuWhiteboxTests {

    @Test @MainActor func onSelect_isInvokedWithTheChosenPreset() {
        var selected: [PaneLayoutPreset] = []
        let menu = PaneLayoutPresetMenu { preset in
            selected.append(preset)
        }

        menu.onSelect(.mainLeftStackRight)
        menu.onSelect(.grid2x2)

        #expect(selected == [.mainLeftStackRight, .grid2x2])
    }

    @Test func items_matchesDeclarationOrderOfEveryCase() {
        // 表示順は enum 宣言順に一致させている。並びを変えたら意図的な変更として
        // このテストを更新すること（受け入れテストは順序を固定していない）。
        #expect(PaneLayoutPresetMenu.items == PaneLayoutPreset.allCases)
    }
}
