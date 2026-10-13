// セッション行の強調: 未読は文字色と太さ、質問待ちは注意色、選択はグレー。

import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("03 Sidebar: sidebar row emphasis")
struct AcceptanceSidebarRowEmphasisTests {
    @Test("projectScope の面は filtering → hover → なし の順（選択だけでは敷かない）")
    func projectScopeFillPriority() {
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isHovering: false)).fill == DSColor.selectionFill)
        // 選択中のプロジェクトは色を変えない（2026-10-13 ユーザー指示）。グリッドの絞り込み中だけ面を敷く。
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isHovering: true)).fill == DSColor.fillSubtle)
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isHovering: false)).fill == Color.clear)
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isHovering: true)).fill == DSColor.selectionFill)
    }

    @Test("選択はアクセントの淡い面、ホバーは従来の面、質問待ちは注意色")
    func sessionFillPriority() {
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, state: .idle)).fill == DSColor.selectionFill)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, state: .idle)).fill == DSColor.fillSubtle)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: false, state: .doneUnread)).fill == Color.clear)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, state: .doneUnread)).fill == DSColor.fillSubtle)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: true, state: .question)).fill == DSColor.attentionTint(.question))
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: false, state: .done)).fill == Color.clear)
    }

    @Test("未確認完了のタイトルは太字にする")
    func unreadCompletionIsBold() {
        let unread = SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: false, state: .doneUnread))
        #expect(unread.nameWeight == .semibold)
    }

    @Test("未読の題名は主文字色、既読は副文字色で示す")
    func unreadTitleUsesTextColor() {
        let unread = SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: false, state: .doneUnread))
        let read = SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: false, state: .done))
        #expect(unread.nameColor == DSColor.textPrimary)
        #expect(read.nameColor == DSColor.textSecondary)
    }

    @Test("選択しただけのセッション行は太字にしない（太字は未読に割り当てた）")
    func selectionAloneIsNotBold() {
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, state: .idle)).nameWeight == .regular)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, state: .running)).nameWeight == .regular)
    }

    @Test("グリッドの表示範囲の印は projectScope(isFiltering: true) だけ")
    func scopeBadgeOnlyWhenProjectIsFiltering() {
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isHovering: false)).scopeBadgeText == "グリッドの表示範囲")
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isHovering: true)).scopeBadgeText == nil)
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, state: .idle)).scopeBadgeText == nil)
    }

    @Test("accessibilityValue は現在の会話 / グリッドを絞り込み中 / その他 nil")
    func accessibilityValueThreeBranches() {
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: true, isHovering: false, state: .idle)).accessibilityValue == "現在の会話")
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: true, isHovering: false)).accessibilityValue == "グリッドを絞り込み中")
        #expect(SidebarRowEmphasis.resolve(.session(isCurrent: false, isHovering: true, state: .doneUnread)).accessibilityValue == nil)
        #expect(SidebarRowEmphasis.resolve(.projectScope(isFiltering: false, isHovering: false)).accessibilityValue == nil)
    }
}
