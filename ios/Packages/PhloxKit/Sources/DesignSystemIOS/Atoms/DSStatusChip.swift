import SwiftUI
import AgentDomain

/// `SessionStatus` の 6 状態を色 + アイコン + テキストの三重符号化で表示するチップ。
/// 色覚多様性に配慮し、状態は色だけでなく形（SF Symbol）と文言でも区別する。
/// 語彙・色・アイコンは共有 `StatusBadge`（SSOT）から引く。
public struct DSStatusChip: View {
    let status: SessionStatus
    @Environment(\.locale) private var locale

    public init(status: SessionStatus) {
        self.status = status
    }

    /// チップが表示するラベルとアイコン名を解決する純粋ヘルパー（テスト可能・6 分岐の検証点）。
    static func content(for status: SessionStatus, locale: Locale) -> (label: String, icon: String) {
        (StatusBadge.localizedLabel(for: status, locale: locale), StatusBadge.iconName(for: status))
    }

    public var body: some View {
        let resolved = Self.content(for: status, locale: locale)
        let tint = StatusBadge.color(for: status)
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: resolved.icon)
                .imageScale(.small)
            Text(resolved.label)
                .font(DSFont.captionStrong)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xxs)
        .background(tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.5), lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(resolved.label))
    }
}

#if DEBUG
#Preview("DSStatusChip") {
    VStack(alignment: .leading, spacing: DSSpacing.s) {
        DSStatusChip(status: .starting)
        DSStatusChip(status: .idle)
        DSStatusChip(status: .running)
        DSStatusChip(status: .awaitingApproval(prompt: "削除を承認しますか？"))
        DSStatusChip(status: .completed(exitCode: 0))
        DSStatusChip(status: .completed(exitCode: 1))
        DSStatusChip(status: .error(message: "接続失敗"))
    }
    .padding(DSSpacing.l)
}
#endif
