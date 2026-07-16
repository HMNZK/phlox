import SwiftUI
import DesignSystemIOS

/// カンプ⑪の文言（テスト可能なコピー層）。
public enum EmptyStateCopy {
    public static let title = "セッションがありません"
    public static let subtitle = "+ をタップして最初のエージェントを\nspawn しましょう。外出先でも指示できます。"
    public static let ctaTitle = "+ 新規タスクを作成"
}

/// カンプ⑪の寸法トークン（design.md §2.3 / ios-design.html）。
enum EmptyStateMetrics {
    /// 点線アイコン枠 96×96。
    static let iconContainerSize: CGFloat = DSSpacing.xxl * 3
    /// 点線枠角丸 24px。
    static let iconContainerCornerRadius: CGFloat = DSSpacing.l + DSSpacing.s
    /// 点線枠 2px。
    static let iconContainerBorderWidth: CGFloat = DSSpacing.xxs
    /// 内側アイコン 42×42。
    static let iconSize: CGFloat = DSTouch.minSize - DSSpacing.xxs
    /// `rgba(168,85,247,.45)` 相当。
    static let iconBorderOpacity: CGFloat = 0.45
    /// カンプ内ターミナル風 SF Symbol。
    static let iconName = "terminal"
}

/// セッション 0 件の空状態（カンプ⑪）。
public struct EmptyStateView: View {
    let onCreate: () -> Void
    let showsCTA: Bool

    public init(onCreate: @escaping () -> Void, showsCTA: Bool = true) {
        self.onCreate = onCreate
        self.showsCTA = showsCTA
    }

    public var body: some View {
        VStack(spacing: DSSpacing.l) {
            Spacer()
            dashedIconPlaceholder
            Text(EmptyStateCopy.title)
                .font(DSFont.title2.weight(.bold))
                .foregroundStyle(DSColor.textPrimary)
            Text(EmptyStateCopy.subtitle)
                .font(DSFont.subheadline)
                .foregroundStyle(DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(DSSpacing.xxs)
                .padding(.horizontal, DSSpacing.xl)
            Spacer()
            if showsCTA {
                DSGradientButton(
                    EmptyStateCopy.ctaTitle,
                    usesHorizontalBrand: true,
                    cornerRadius: DSGradientButton.height / 2,
                    action: onCreate
                )
                    .padding(.horizontal, DSSpacing.l)
                    .padding(.bottom, DSSpacing.s)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DSColor.background)
    }

    private var dashedIconPlaceholder: some View {
        Image(systemName: EmptyStateMetrics.iconName)
            .font(DSFont.title1)
            .foregroundStyle(DSColor.accent)
            .frame(width: EmptyStateMetrics.iconSize, height: EmptyStateMetrics.iconSize)
            .frame(width: EmptyStateMetrics.iconContainerSize, height: EmptyStateMetrics.iconContainerSize)
            .overlay(
                RoundedRectangle(cornerRadius: EmptyStateMetrics.iconContainerCornerRadius, style: .continuous)
                    .strokeBorder(
                        DSColor.accent.opacity(EmptyStateMetrics.iconBorderOpacity),
                        style: StrokeStyle(
                            lineWidth: EmptyStateMetrics.iconContainerBorderWidth,
                            dash: [DSSpacing.xs, DSSpacing.xs]
                        )
                    )
            )
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    EmptyStateView(onCreate: {})
}
#endif
