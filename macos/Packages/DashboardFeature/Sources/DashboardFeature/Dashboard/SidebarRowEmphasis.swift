import SwiftUI
import DesignSystem

/// サイドバー行の強調。完了未確認と質問待ちを優先し、選択はグレーで示す。
struct SidebarRowEmphasis: Equatable {
    enum Role: Equatable {
        case projectScope(isFiltering: Bool, isDefaultTarget: Bool, isHovering: Bool)
        case session(isCurrent: Bool, isHovering: Bool, state: SessionDisplayState)
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
        case let .session(isCurrent, isHovering, state):
            let fill: Color
            if state == .doneUnread || state == .question {
                fill = DSColor.selectionFill
            } else if isCurrent || isHovering {
                fill = DSColor.fillSelected
            } else {
                fill = Color.clear
            }
            return SidebarRowEmphasis(
                fill: fill,
                nameWeight: state == .doneUnread ? .semibold : .regular,
                scopeBadgeText: nil,
                accessibilityValue: isCurrent ? "現在の会話" : nil
            )
        }
    }
}
