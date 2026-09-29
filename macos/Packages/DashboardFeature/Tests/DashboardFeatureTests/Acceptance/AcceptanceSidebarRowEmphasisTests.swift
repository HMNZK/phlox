// セッション行の強調: 未確認完了・質問待ちはオレンジ、選択はグレー。

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

    @Test("選択はグレー、未確認完了と質問待ちは選択より優先してオレンジ")
    func sessionFillPriority() {
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, state: .idle)).fill == DSColor.fillSelected)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, state: .idle)).fill == DSColor.fillSelected)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: false, state: .doneUnread)).fill == DSColor.selectionFill)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: true, state: .question)).fill == DSColor.selectionFill)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: false, state: .done)).fill == Color.clear)
    }

    @Test("未確認完了のタイトルは太字にする")
    func unreadCompletionIsBold() {
        let unread = SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: false, state: .doneUnread))
        #expect(unread.nameWeight == .semibold)
    }

    @Test("選択しただけのセッション行は太字にしない（太字は未読に割り当てた）")
    func selectionAloneIsNotBold() {
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, state: .idle)).nameWeight == .regular)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, state: .running)).nameWeight == .regular)
    }

    @Test("グリッドの表示範囲の印は projectScope(isFiltering: true) だけ")
    func scopeBadgeOnlyWhenProjectIsFiltering() {
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isDefaultTarget: false, isHovering: false)).scopeBadgeText == "グリッドの表示範囲")
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isDefaultTarget: true, isHovering: true)).scopeBadgeText == nil)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, state: .idle)).scopeBadgeText == nil)
    }

    @Test("accessibilityValue は現在の会話 / グリッドを絞り込み中 / その他 nil")
    func accessibilityValueThreeBranches() {
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, state: .idle)).accessibilityValue == "現在の会話")
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isDefaultTarget: false, isHovering: false)).accessibilityValue == "グリッドを絞り込み中")
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, state: .doneUnread)).accessibilityValue == nil)
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isDefaultTarget: true, isHovering: false)).accessibilityValue == nil)
    }
}
