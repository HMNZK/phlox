import SwiftUI
import DesignSystem

/// サイドバー行の強調（03「強調の使い分け」）。背景色は選択とホバーだけに使い、
/// 未読の完了はタイトルの太字と点で示す（背景を取り合わない）。
struct SidebarRowEmphasis: Equatable {
    enum Role: Equatable {
        case projectScope(isFiltering: Bool, isDefaultTarget: Bool, isHovering: Bool)
        case session(isCurrent: Bool, isHovering: Bool, hasUnseenCompletion: Bool)
    }

    let fill: Color
    let nameWeight: Font.Weight
    let scopeBadgeText: String?
    let accessibilityValue: String?

    static func resolve(_ role: Role) -> SidebarRowEmphasis {
        switch role {
        case let .projectScope(isFiltering, isDefaultTarget, isHovering):
            let fill: Color
            if isFiltering || isDefaultTarget {
                fill = DSColor.fillSelected
            } else if isHovering {
                fill = DSColor.fillSubtle
            } else {
                fill = Color.clear
            }
            return SidebarRowEmphasis(
                fill: fill,
                nameWeight: .semibold,
                scopeBadgeText: isFiltering ? "グリッドの表示範囲" : nil,
                accessibilityValue: isFiltering ? "グリッドを絞り込み中" : nil
            )
        case let .session(isCurrent, isHovering, hasUnseenCompletion):
            let fill: Color
            if isCurrent {
                fill = DSColor.selectionFill
            } else if isHovering {
                fill = DSColor.fillSubtle
            } else {
                fill = Color.clear
            }
            return SidebarRowEmphasis(
                fill: fill,
                nameWeight: hasUnseenCompletion ? .semibold : .regular,
                scopeBadgeText: nil,
                accessibilityValue: isCurrent ? "現在の会話" : nil
            )
        }
    }
}
