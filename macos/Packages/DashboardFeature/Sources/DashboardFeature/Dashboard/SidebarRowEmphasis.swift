import SwiftUI
import DesignSystem

struct SidebarRowEmphasis: Equatable {
    enum Role: Equatable {
        case projectScope(isFiltering: Bool, isDefaultTarget: Bool, isHovering: Bool)
        case session(isCurrent: Bool, isHovering: Bool, requiresAttention: Bool)
    }

    let fill: Color
    let border: Color
    let showsCurrentMarker: Bool
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
                border: Color.clear,
                showsCurrentMarker: false,
                nameWeight: .regular,
                scopeBadgeText: isFiltering ? "絞り込み中" : nil,
                accessibilityValue: isFiltering ? "グリッドを絞り込み中" : nil
            )
        case let .session(isCurrent, isHovering, requiresAttention):
            let fill: Color
            let border: Color
            if isCurrent {
                fill = DSColor.sessionRowSelected
                border = DSColor.sessionRowSelectedBorder
            } else if isHovering {
                fill = DSColor.sessionRowHover
                border = DSColor.sessionRowHoverBorder
            } else if requiresAttention {
                fill = DSColor.idleHighlight
                border = Color.clear
            } else {
                fill = Color.clear
                border = Color.clear
            }
            return SidebarRowEmphasis(
                fill: fill,
                border: border,
                showsCurrentMarker: isCurrent,
                nameWeight: isCurrent ? .semibold : .regular,
                scopeBadgeText: nil,
                accessibilityValue: isCurrent ? "現在の会話" : nil
            )
        }
    }
}
