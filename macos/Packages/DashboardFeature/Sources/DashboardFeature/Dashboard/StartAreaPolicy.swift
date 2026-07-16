import SwiftUI
import DesignSystem

/// セッション未選択時に detail 領域へ何を出すかの内容種別（シングル/エージェント両ビュー共通）。
public enum StartAreaContent: Equatable, Sendable {
    /// セッション選択中 → 通常のセッション表示
    case sessionContent
    /// プロジェクト選択済み・セッション未選択 → エージェント選択カード
    case agentStartCards
    /// プロジェクト未選択・セッション未選択 → 「プロジェクトを選択してください」
    case selectProjectPlaceholder
}

/// セレクトカード表示条件の純ロジック（R4）。
public enum StartAreaPolicy {
    public static func content(hasSelectedProject: Bool, hasSelectedSession: Bool) -> StartAreaContent {
        if hasSelectedSession { return .sessionContent }
        if hasSelectedProject { return .agentStartCards }
        return .selectProjectPlaceholder
    }
}

/// プロジェクト未選択時のプレースホルダ表示。
struct SelectProjectPlaceholderView: View {
    var body: some View {
        VStack(spacing: DSSpacing.m) {
            Image(systemName: "folder")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(DSColor.textTertiary)
            Text("プロジェクトを選択してください")
                .font(DSFont.sectionHeader)
                .foregroundStyle(DSColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
