import SwiftUI

/// アクセシビリティラベル付きトグル。タイトル + 任意の補助説明を持つ。
public struct DSToggle: View {
    /// テスト用スタイル契約（AtomsTests · DS-AUDIT-1）。
    public static let titleForegroundToken = DSColor.textPrimary
    public static let onTintToken = DSColor.statusRunning

    @Binding var isOn: Bool
    let title: String
    let subtitle: String?

    public init(isOn: Binding<Bool>, title: String, subtitle: String? = nil) {
        self._isOn = isOn
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(DSFont.body)
                    .foregroundStyle(DSColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(DSFont.footnote)
                        .foregroundStyle(DSColor.textSecondary)
                }
            }
        }
        .tint(DSColor.statusRunning)
        .frame(minHeight: DSTouch.minSize)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(subtitle ?? ""))
        .accessibilityValue(Text(isOn ? "オン" : "オフ"))
    }
}

#if DEBUG
private struct DSTogglePreviewHost: View {
    @State private var on = true
    @State private var off = false
    var body: some View {
        VStack(spacing: DSSpacing.m) {
            DSToggle(isOn: $on, title: "生体認証で保護", subtitle: "起動時に Face ID を要求")
            DSToggle(isOn: $off, title: "詳細ログ")
        }
        .padding(DSSpacing.l)
    }
}

#Preview("DSToggle") {
    DSTogglePreviewHost()
}
#endif
