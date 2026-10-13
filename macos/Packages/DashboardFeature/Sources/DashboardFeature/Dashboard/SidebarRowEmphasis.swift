import SwiftUI
import DesignSystem

/// サイドバー行の強調。選択はアクセントの淡い面、未読は文字色と太さ、対応待ちは注意色で示す。
struct SidebarRowEmphasis: Equatable {
    enum Role: Equatable {
        case projectScope(isFiltering: Bool, isHovering: Bool)
        case session(isCurrent: Bool, isHovering: Bool, state: SessionDisplayState)
    }

    let fill: Color
    let nameWeight: Font.Weight
    let nameColor: Color
    let scopeBadgeText: String?
    let accessibilityValue: String?

    static func resolve(_ role: Role) -> SidebarRowEmphasis {
        switch role {
        case let .projectScope(isFiltering, isHovering):
            let fill: Color
            // 選択中のプロジェクト（セッションを選んだときも含む）は色を変えない（2026-10-13 ユーザー指示）。
            if isFiltering {
                fill = DSColor.selectionFill
            } else if isHovering {
                fill = DSColor.fillSubtle
            } else {
                fill = Color.clear
            }
            return SidebarRowEmphasis(
                fill: fill,
                nameWeight: .semibold,
                nameColor: DSColor.textPrimary,
                scopeBadgeText: isFiltering ? "グリッドの表示範囲" : nil,
                accessibilityValue: isFiltering ? "グリッドを絞り込み中" : nil
            )
        case let .session(isCurrent, isHovering, state):
            let fill: Color
            if state == .question {
                fill = DSColor.attentionTint(.question)
            } else if isCurrent {
                fill = DSColor.selectionFill
            } else if isHovering {
                fill = DSColor.fillSubtle
            } else {
                fill = Color.clear
            }
            return SidebarRowEmphasis(
                fill: fill,
                nameWeight: state == .doneUnread ? .semibold : .regular,
                nameColor: state == .doneUnread ? DSColor.textPrimary : DSColor.textSecondary,
                scopeBadgeText: nil,
                accessibilityValue: isCurrent ? "現在の会話" : nil
            )
        }
    }
}
