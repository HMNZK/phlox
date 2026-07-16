import Foundation
import Testing
@testable import DashboardFeature

// task-4 受け入れテスト（PM 著・実装役編集禁止）。
// 契約: Usage チップ行の使用可能幅は「ウィンドウ実測幅 − サイドバー幅 −
// コントロール群の実測幅 − spacing − 右端 padding」を 0 でクランプした値。
// 固定 reservedWidth(420/640) の逆算を置き換える純関数として凍結する。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

@Test func usageAvailableWidthSubtractsAllOccupiedWidths() {
    let width = TrailingTopBarLayout.usageAvailableWidth(
        windowWidth: 1_000,
        occupiedSidebarWidth: 280,
        measuredControlsWidth: 200,
        spacing: 8,
        trailingPadding: 12
    )
    #expect(width == 500)
}

@Test func usageAvailableWidthIsZeroWithoutRoomInsteadOfNegative() {
    let width = TrailingTopBarLayout.usageAvailableWidth(
        windowWidth: 400,
        occupiedSidebarWidth: 280,
        measuredControlsWidth: 200,
        spacing: 8,
        trailingPadding: 12
    )
    #expect(width == 0)
}

@Test func usageAvailableWidthShrinksAsControlsGrow() {
    let narrowControls = TrailingTopBarLayout.usageAvailableWidth(
        windowWidth: 1_000,
        occupiedSidebarWidth: 0,
        measuredControlsWidth: 150,
        spacing: 8,
        trailingPadding: 12
    )
    let wideControls = TrailingTopBarLayout.usageAvailableWidth(
        windowWidth: 1_000,
        occupiedSidebarWidth: 0,
        measuredControlsWidth: 390,
        spacing: 8,
        trailingPadding: 12
    )
    // grid モード相当（列数トグル分でコントロール群が広がる）でも、固定値でなく
    // 実測幅の差分どおりに縮むこと。
    #expect(narrowControls - wideControls == 240)
    // ハーネス修理（2026-07-10 PM 承認・意味保存）: #expect の右辺を整数リテラルの
    // 計算式で書くとマクロ展開で Int と推論され、CGFloat との比較が値一致でも
    // false になるため、CGFloat を明示する（期待値 1000-390-8-12 = 590 は不変）。
    #expect(wideControls == CGFloat(1_000 - 390 - 8 - 12))
}

@Test func usageAvailableWidthIgnoresSidebarWhenHidden() {
    let width = TrailingTopBarLayout.usageAvailableWidth(
        windowWidth: 800,
        occupiedSidebarWidth: 0,
        measuredControlsWidth: 100,
        spacing: 8,
        trailingPadding: 12
    )
    #expect(width == 680)
}
