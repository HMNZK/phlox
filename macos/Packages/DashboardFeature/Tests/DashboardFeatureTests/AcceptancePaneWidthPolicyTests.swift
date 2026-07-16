// task-1 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-1.md — 3ペイン幅クランプの純関数ポリシー。
// アサーションは変更禁止。テストハーネスの欠陥を発見した場合は、PM に報告し
// 承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
@testable import DashboardFeature

// 最小幅定数の凍結（DashboardView の従来値と一致させる）
@Test func paneWidthPolicy_constants_matchFrozenValues() {
    #expect(PaneWidthPolicy.sidebarMinWidth == 240)
    #expect(PaneWidthPolicy.inspectorMinWidth == 240)
    #expect(PaneWidthPolicy.detailMinWidth == 400)
}

// 十分な幅では現在幅を変えない
@Test func paneWidthPolicy_wideWindow_keepsCurrentWidths() {
    let r = PaneWidthPolicy.clamped(
        windowWidth: 1400, sidebarVisible: true, inspectorVisible: true,
        sidebarWidth: 280, inspectorWidth: 300
    )
    #expect(r == PaneWidths(sidebar: 280, inspector: 300))
}

// 丁度収まる幅（280+300+detail 400 = 980）では現在幅を変えない
@Test func paneWidthPolicy_exactFit_keepsCurrentWidths() {
    let r = PaneWidthPolicy.clamped(
        windowWidth: 980, sidebarVisible: true, inspectorVisible: true,
        sidebarWidth: 280, inspectorWidth: 300
    )
    #expect(r == PaneWidths(sidebar: 280, inspector: 300))
}

// 収まらないときはインスペクター側から縮め、min 到達後にサイドバーを縮める
@Test func paneWidthPolicy_narrowWindow_shrinksInspectorFirstThenSidebar() {
    // budget = 900 - 400(detail) = 500。inspector→240（min 床）、sidebar→260 で丁度 500。
    let r = PaneWidthPolicy.clamped(
        windowWidth: 900, sidebarVisible: true, inspectorVisible: true,
        sidebarWidth: 280, inspectorWidth: 300
    )
    #expect(r == PaneWidths(sidebar: 260, inspector: 240))
}

// 両方 min まで縮めても収まらない場合は min で床止め（それ以上は縮めない）
@Test func paneWidthPolicy_tooNarrow_floorsAtMinWidths() {
    let r = PaneWidthPolicy.clamped(
        windowWidth: 800, sidebarVisible: true, inspectorVisible: true,
        sidebarWidth: 280, inspectorWidth: 300
    )
    #expect(r == PaneWidths(sidebar: 240, inspector: 240))
}

// クランプは縮める方向のみ（広いウィンドウでユーザー設定幅を勝手に広げない）
@Test func paneWidthPolicy_neverGrowsWidths() {
    let r = PaneWidthPolicy.clamped(
        windowWidth: 2000, sidebarVisible: true, inspectorVisible: true,
        sidebarWidth: 250, inspectorWidth: 260
    )
    #expect(r == PaneWidths(sidebar: 250, inspector: 260))
}

// 非表示ペインの幅は変更しない（パススルー）
@Test func paneWidthPolicy_hiddenPanes_passThrough() {
    let r = PaneWidthPolicy.clamped(
        windowWidth: 500, sidebarVisible: false, inspectorVisible: false,
        sidebarWidth: 280, inspectorWidth: 300
    )
    #expect(r == PaneWidths(sidebar: 280, inspector: 300))
}

// サイドバーのみ表示: budget = 620 - 400 = 220 < min → 240 で床止め。inspector は不変
@Test func paneWidthPolicy_sidebarOnly_clampsToBudget() {
    let r = PaneWidthPolicy.clamped(
        windowWidth: 620, sidebarVisible: true, inspectorVisible: false,
        sidebarWidth: 280, inspectorWidth: 300
    )
    #expect(r.sidebar == 240)
    #expect(r.inspector == 300)
}

// インスペクターのみ表示: budget = 700 - 400 = 300 → 300 のまま。sidebar は不変
@Test func paneWidthPolicy_inspectorOnly_keepsWidthWithinBudget() {
    let r = PaneWidthPolicy.clamped(
        windowWidth: 700, sidebarVisible: false, inspectorVisible: true,
        sidebarWidth: 280, inspectorWidth: 300
    )
    #expect(r.inspector == 300)
    #expect(r.sidebar == 280)
}

// 事後条件の総性質: 可視ペイン幅は常に min 以上。budget が両 min の合計以上なら
// 合計 <= budget、それ未満なら両 min で床止め
@Test func paneWidthPolicy_postconditions_holdAcrossWindowWidths() {
    for w in stride(from: CGFloat(700), through: 1600, by: 50) {
        let r = PaneWidthPolicy.clamped(
            windowWidth: w, sidebarVisible: true, inspectorVisible: true,
            sidebarWidth: 280, inspectorWidth: 300
        )
        #expect(r.sidebar >= PaneWidthPolicy.sidebarMinWidth)
        #expect(r.inspector >= PaneWidthPolicy.inspectorMinWidth)
        let budget = w - PaneWidthPolicy.detailMinWidth
        if budget >= PaneWidthPolicy.sidebarMinWidth + PaneWidthPolicy.inspectorMinWidth {
            #expect(r.sidebar + r.inspector <= budget)
        } else {
            #expect(r == PaneWidths(sidebar: 240, inspector: 240))
        }
    }
}
