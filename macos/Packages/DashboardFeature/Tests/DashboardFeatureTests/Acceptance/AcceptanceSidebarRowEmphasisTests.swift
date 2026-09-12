// task-32（UI-08）の受け入れテスト。
//
// ベースラインでの red 理由: `SidebarRowEmphasis` と `SidebarRowEmphasis.resolve(_:)`、
// `SidebarRowEmphasis.Role` は本タスクが新設を要求する API で、baseline_commit には存在しない
// （参照未解決でコンパイル不能＝red）。
//
// 契約: プロジェクト行（対象範囲）とセッション行（現在の会話）の強調を 1 箇所で解決する。
// fill/border は既存トークンの優先順を保ち、現在の会話は太さとマーカー、絞り込みはバッジでも示す。

import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("task-32: sidebar row emphasis")
struct AcceptanceSidebarRowEmphasisTests {
    @Test("projectScope の fill/border は filtering||defaultTarget → hover → その他の順")
    func projectScopeFillAndBorderPriority() {
        let filtering = SidebarRowEmphasis.resolve(
            .projectScope(isFiltering: true, isDefaultTarget: false, isHovering: false)
        )
        #expect(filtering.fill == DSColor.fillSelected)
        #expect(filtering.border == Color.clear)

        let defaultTarget = SidebarRowEmphasis.resolve(
            .projectScope(isFiltering: false, isDefaultTarget: true, isHovering: false)
        )
        #expect(defaultTarget.fill == DSColor.fillSelected)
        #expect(defaultTarget.border == Color.clear)

        let hovering = SidebarRowEmphasis.resolve(
            .projectScope(isFiltering: false, isDefaultTarget: false, isHovering: true)
        )
        #expect(hovering.fill == DSColor.fillSubtle)
        #expect(hovering.border == Color.clear)

        let idle = SidebarRowEmphasis.resolve(
            .projectScope(isFiltering: false, isDefaultTarget: false, isHovering: false)
        )
        #expect(idle.fill == Color.clear)
        #expect(idle.border == Color.clear)

        let filteringBeatsHover = SidebarRowEmphasis.resolve(
            .projectScope(isFiltering: true, isDefaultTarget: false, isHovering: true)
        )
        #expect(filteringBeatsHover.fill == DSColor.fillSelected)
        #expect(filteringBeatsHover.border == Color.clear)

        let defaultBeatsHover = SidebarRowEmphasis.resolve(
            .projectScope(isFiltering: false, isDefaultTarget: true, isHovering: true)
        )
        #expect(defaultBeatsHover.fill == DSColor.fillSelected)
        #expect(defaultBeatsHover.border == Color.clear)
    }

    @Test("session の fill/border は current → hover → attention → その他の順")
    func sessionFillAndBorderPriority() {
        let current = SidebarRowEmphasis.resolve(
            .session(isCurrent: true, isHovering: false, requiresAttention: false)
        )
        #expect(current.fill == DSColor.sessionRowSelected)
        #expect(current.border == DSColor.sessionRowSelectedBorder)

        let hovering = SidebarRowEmphasis.resolve(
            .session(isCurrent: false, isHovering: true, requiresAttention: false)
        )
        #expect(hovering.fill == DSColor.sessionRowHover)
        #expect(hovering.border == DSColor.sessionRowHoverBorder)

        let attention = SidebarRowEmphasis.resolve(
            .session(isCurrent: false, isHovering: false, requiresAttention: true)
        )
        #expect(attention.fill == DSColor.idleHighlight)
        #expect(attention.border == Color.clear)

        let idle = SidebarRowEmphasis.resolve(
            .session(isCurrent: false, isHovering: false, requiresAttention: false)
        )
        #expect(idle.fill == Color.clear)
        #expect(idle.border == Color.clear)

        let currentBeatsHover = SidebarRowEmphasis.resolve(
            .session(isCurrent: true, isHovering: true, requiresAttention: true)
        )
        #expect(currentBeatsHover.fill == DSColor.sessionRowSelected)
        #expect(currentBeatsHover.border == DSColor.sessionRowSelectedBorder)

        let hoverBeatsAttention = SidebarRowEmphasis.resolve(
            .session(isCurrent: false, isHovering: true, requiresAttention: true)
        )
        #expect(hoverBeatsAttention.fill == DSColor.sessionRowHover)
        #expect(hoverBeatsAttention.border == DSColor.sessionRowHoverBorder)
    }

    @Test("showsCurrentMarker と nameWeight は session(isCurrent: true) だけ")
    func currentMarkerAndNameWeightOnlyForCurrentSession() {
        let current = SidebarRowEmphasis.resolve(
            .session(isCurrent: true, isHovering: false, requiresAttention: false)
        )
        #expect(current.showsCurrentMarker)
        #expect(current.nameWeight == .semibold)

        let currentWithOthers = SidebarRowEmphasis.resolve(
            .session(isCurrent: true, isHovering: true, requiresAttention: true)
        )
        #expect(currentWithOthers.showsCurrentMarker)
        #expect(currentWithOthers.nameWeight == .semibold)

        let hovering = SidebarRowEmphasis.resolve(
            .session(isCurrent: false, isHovering: true, requiresAttention: false)
        )
        #expect(!hovering.showsCurrentMarker)
        #expect(hovering.nameWeight == .regular)

        let attention = SidebarRowEmphasis.resolve(
            .session(isCurrent: false, isHovering: false, requiresAttention: true)
        )
        #expect(!attention.showsCurrentMarker)
        #expect(attention.nameWeight == .regular)

        let idleSession = SidebarRowEmphasis.resolve(
            .session(isCurrent: false, isHovering: false, requiresAttention: false)
        )
        #expect(!idleSession.showsCurrentMarker)
        #expect(idleSession.nameWeight == .regular)

        let filtering = SidebarRowEmphasis.resolve(
            .projectScope(isFiltering: true, isDefaultTarget: true, isHovering: true)
        )
        #expect(!filtering.showsCurrentMarker)
        #expect(filtering.nameWeight == .regular)

        let idleProject = SidebarRowEmphasis.resolve(
            .projectScope(isFiltering: false, isDefaultTarget: false, isHovering: false)
        )
        #expect(!idleProject.showsCurrentMarker)
        #expect(idleProject.nameWeight == .regular)
    }

    @Test("scopeBadgeText は projectScope(isFiltering: true) だけ「絞り込み中」")
    func scopeBadgeTextOnlyWhenProjectIsFiltering() {
        #expect(
            SidebarRowEmphasis.resolve(
                .projectScope(isFiltering: true, isDefaultTarget: false, isHovering: false)
            ).scopeBadgeText == "絞り込み中"
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .projectScope(isFiltering: true, isDefaultTarget: true, isHovering: true)
            ).scopeBadgeText == "絞り込み中"
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .projectScope(isFiltering: false, isDefaultTarget: true, isHovering: false)
            ).scopeBadgeText == nil
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .projectScope(isFiltering: false, isDefaultTarget: false, isHovering: true)
            ).scopeBadgeText == nil
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .session(isCurrent: true, isHovering: false, requiresAttention: false)
            ).scopeBadgeText == nil
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .session(isCurrent: false, isHovering: true, requiresAttention: true)
            ).scopeBadgeText == nil
        )
    }

    @Test("accessibilityValue は現在の会話 / グリッドを絞り込み中 / その他 nil")
    func accessibilityValueThreeBranches() {
        #expect(
            SidebarRowEmphasis.resolve(
                .session(isCurrent: true, isHovering: false, requiresAttention: false)
            ).accessibilityValue == "現在の会話"
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .session(isCurrent: true, isHovering: true, requiresAttention: true)
            ).accessibilityValue == "現在の会話"
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .projectScope(isFiltering: true, isDefaultTarget: false, isHovering: false)
            ).accessibilityValue == "グリッドを絞り込み中"
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .projectScope(isFiltering: true, isDefaultTarget: true, isHovering: true)
            ).accessibilityValue == "グリッドを絞り込み中"
        )

        #expect(
            SidebarRowEmphasis.resolve(
                .session(isCurrent: false, isHovering: true, requiresAttention: false)
            ).accessibilityValue == nil
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .session(isCurrent: false, isHovering: false, requiresAttention: true)
            ).accessibilityValue == nil
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .projectScope(isFiltering: false, isDefaultTarget: true, isHovering: false)
            ).accessibilityValue == nil
        )
        #expect(
            SidebarRowEmphasis.resolve(
                .projectScope(isFiltering: false, isDefaultTarget: false, isHovering: true)
            ).accessibilityValue == nil
        )
    }
}
