import SwiftUI

/// 主要 CTA（ブランドグラデ・50pt 高さ・`ctaGlow` 影）。接続設定・spawn 等で使う。
public struct DSGradientButton: View {
    /// カンプ主要ボタン高さ（design.md §2.3）。生値 `50` を避け `DSSpacing` から導出。
    public static let height: CGFloat = DSSpacing.xxl + DSSpacing.m + DSSpacing.xs + DSSpacing.xxs
    /// カンプボタン角丸（12–14px の上限 · `DSRadius.card`）。
    public static let cornerRadius: CGFloat = DSRadius.card
    /// 適用する elevation トークン。
    public static let shadowToken = DSShadow.ctaGlow

    let title: String
    let icon: String?
    let isLoading: Bool
    let isEnabled: Bool
    let accessibilityIdentifier: String?
    let usesHorizontalBrand: Bool
    let cornerRadiusOverride: CGFloat?
    let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        accessibilityIdentifier: String? = nil,
        usesHorizontalBrand: Bool = false,
        cornerRadius: CGFloat? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.accessibilityIdentifier = accessibilityIdentifier
        self.usesHorizontalBrand = usesHorizontalBrand
        self.cornerRadiusOverride = cornerRadius
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                labelContent
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(DSColor.textOnBrand)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height)
            .padding(.horizontal, DSSpacing.l)
            .foregroundStyle(DSColor.textOnBrand)
            .background(background, in: RoundedRectangle(cornerRadius: resolvedCornerRadius, style: .continuous))
            .dsShadow(isEnabled ? Self.shadowToken : DSShadow(color: .clear, radius: 0, x: 0, y: 0))
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isLoading ? Text("読み込み中") : Text(""))
        .modifier(OptionalAccessibilityIdentifier(accessibilityIdentifier))
    }

    @ViewBuilder
    private var labelContent: some View {
        if let icon {
            HStack(spacing: DSSpacing.s) {
                Image(systemName: icon)
                    .font(DSFont.headline)
                Text(title)
                    .font(DSFont.headline)
            }
        } else {
            Text(title)
                .font(DSFont.headline)
        }
    }

    private var resolvedCornerRadius: CGFloat {
        cornerRadiusOverride ?? Self.cornerRadius
    }

    private var background: some ShapeStyle {
        if !isEnabled { return AnyShapeStyle(DSColor.textTertiary) }
        return AnyShapeStyle(usesHorizontalBrand ? DSGradient.brandHorizontal : DSGradient.brand)
    }
}

private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) { self.identifier = identifier }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

#if DEBUG
#Preview("DSGradientButton") {
    VStack(spacing: DSSpacing.m) {
        DSGradientButton("保存して接続") {}
        DSGradientButton("起動して送信", icon: "play.fill") {}
        DSGradientButton("保存して接続", isLoading: true) {}
        DSGradientButton("保存して接続", isEnabled: false) {}
    }
    .padding(DSSpacing.l)
}
#endif
