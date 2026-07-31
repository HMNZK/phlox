// task-0 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-0.md — AppRouter のパネル表示フラグとトグル。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。
//
// 凍結する公開面:
// - AppRouter.terminalPanelVisible / editorPanelVisible（初期値 false）
// - AppRouter.toggleTerminalPanel() / toggleEditorPanel()

import Foundation
import Testing
@testable import DashboardFeature

@Suite("Panel router acceptance (task-0)")
@MainActor
struct AcceptancePanelRouterTests {

    @Test("初期状態では両パネルとも非表示")
    func defaultsAreHidden() {
        let router = AppRouter()
        #expect(router.terminalPanelVisible == false)
        #expect(router.editorPanelVisible == false)
    }

    @Test("toggleTerminalPanel はターミナルパネルの表示だけを反転する")
    func toggleTerminalFlipsOnlyTerminal() {
        let router = AppRouter()
        router.toggleTerminalPanel()
        #expect(router.terminalPanelVisible == true)
        #expect(router.editorPanelVisible == false)
        router.toggleTerminalPanel()
        #expect(router.terminalPanelVisible == false)
    }

    @Test("toggleEditorPanel はエディタパネルの表示だけを反転する")
    func toggleEditorFlipsOnlyEditor() {
        let router = AppRouter()
        router.toggleEditorPanel()
        #expect(router.editorPanelVisible == true)
        #expect(router.terminalPanelVisible == false)
        router.toggleEditorPanel()
        #expect(router.editorPanelVisible == false)
    }
}
