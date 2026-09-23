// task-32（UI-08）の受け入れテストを 03 Sidebar（P4）の強調規則へ置き換えたもの。
//
// 契約（03「強調の使い分け」）: 選択 = accent の淡い面、ホバー = グレーの面、未読の完了 = タイトルを太字＋右の点。
// 背景色は選択とホバーだけに使い、未読と取り合わない。選択行の左マーカーと太字は廃止（03 G2）。
// プロジェクト行（対象範囲）の面と、読み上げの値（現在の会話 / グリッドを絞り込み中）は従来どおり。

import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("03 Sidebar: sidebar row emphasis")
struct AcceptanceSidebarRowEmphasisTests {
    @Test("projectScope の面は filtering||defaultTarget → hover → なし の順")
    func projectScopeFillPriority() {
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isDefaultTarget: false, isHovering: false)).fill == DSColor.fillSelected)
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isDefaultTarget: true, isHovering: false)).fill == DSColor.fillSelected)
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isDefaultTarget: false, isHovering: true)).fill == DSColor.fillSubtle)
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isDefaultTarget: false, isHovering: false)).fill == Color.clear)
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isDefaultTarget: true, isHovering: true)).fill == DSColor.fillSelected)
    }

    @Test("選択中のセッション行は accent の淡い面、ホバーはグレーの面")
    func sessionSelectionUsesAccentTintAndHoverUsesGray() {
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, hasUnseenCompletion: false)).fill == DSColor.selectionFill)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: true, hasUnseenCompletion: true)).fill == DSColor.selectionFill)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, hasUnseenCompletion: false)).fill == DSColor.fillSubtle)
    }

    @Test("未読の完了は背景を塗らず、タイトルを太字にする")
    func unreadCompletionIsBoldWithoutFill() {
        let unread = SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: false, hasUnseenCompletion: true))
        #expect(unread.fill == Color.clear)
        #expect(unread.nameWeight == .semibold)
    }

    @Test("選択しただけのセッション行は太字にしない（太字は未読に割り当てた）")
    func selectionAloneIsNotBold() {
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, hasUnseenCompletion: false)).nameWeight == .regular)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, hasUnseenCompletion: false)).nameWeight == .regular)
    }

    @Test("グリッドの表示範囲の印は projectScope(isFiltering: true) だけ")
    func scopeBadgeOnlyWhenProjectIsFiltering() {
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isDefaultTarget: false, isHovering: false)).scopeBadgeText == "グリッドの表示範囲")
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isDefaultTarget: true, isHovering: true)).scopeBadgeText == nil)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, hasUnseenCompletion: false)).scopeBadgeText == nil)
    }

    @Test("accessibilityValue は現在の会話 / グリッドを絞り込み中 / その他 nil")
    func accessibilityValueThreeBranches() {
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, hasUnseenCompletion: false)).accessibilityValue == "現在の会話")
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isDefaultTarget: false, isHovering: false)).accessibilityValue == "グリッドを絞り込み中")
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, hasUnseenCompletion: true)).accessibilityValue == nil)
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isDefaultTarget: true, isHovering: false)).accessibilityValue == nil)
    }
}
