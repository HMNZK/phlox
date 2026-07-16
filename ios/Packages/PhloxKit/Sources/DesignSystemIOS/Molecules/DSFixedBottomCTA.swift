import SwiftUI

/// 画面最下部に固定する主要 CTA バー（接続設定「保存して接続」等）。
/// 親ビューで `.safeAreaInset(edge: .bottom) { DSFixedBottomCTA(...) }` として使う。
public struct DSFixedBottomCTA: View {
    /// 画面水平インセット（design.md §2.3 · `DSTouch.screenInset` 相当）。
    public static let horizontalInset: CGFloat = DSSpacing.l

    let title: String
    let icon: String?
    let isLoading: Bool
    let isEnabled: Bool
    let accessibilityIdentifier: String?
    let action: () -> Void

    public init(
        _ title: String,
        icon: String? = nil,
        isLoading: Bool = false,
        isEnabled: Bool = true,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        DSGradientButton(
            title,
            icon: icon,
            isLoading: isLoading,
            isEnabled: isEnabled,
            accessibilityIdentifier: accessibilityIdentifier,
            action: action
        )
        .padding(.horizontal, Self.horizontalInset)
        .padding(.top, DSSpacing.m)
        .padding(.bottom, DSSpacing.m)
        .frame(maxWidth: .infinity)
        .background(DSColor.background)
    }
}

#if DEBUG
#Preview("DSFixedBottomCTA") {
    VStack {
        Spacer()
    }
    .safeAreaInset(edge: .bottom) {
        DSFixedBottomCTA("保存して接続") {}
    }
}
#endif
