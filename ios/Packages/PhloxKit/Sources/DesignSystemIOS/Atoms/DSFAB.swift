import SwiftUI

/// セッション一覧ツールバーの追加（＋）。ブランド色グリフのみ・44pt タッチターゲット。
public struct DSFAB: View {
    /// カンプ FAB タッチ領域（design.md §2.3 · HIG 最小 44pt）。
    public static let size: CGFloat = DSTouch.minSize
    /// カンプの＋アイコン（SF Symbol）。
    public static let iconName = "plus"
    /// 塗り潰し円背景は使わない（アイコンのみスタイル）。
    public static let usesFilledCircleBackground = false
    /// `frame` 全域をタップ可能にする（アイコンのみ表示でも 44pt ヒット領域を保つ）。
    public static let usesFullFrameContentShape = true
    /// ＋グリフに適用するブランドグラデ開始色。
    public static var iconBrandGradientStart: Color { DSGradient.brandStart.color }
    /// ＋グリフに適用するブランドグラデ終端色。
    public static var iconBrandGradientEnd: Color { DSGradient.brandEnd.color }
    /// ＋アイコンのタイポグラフィトークン。
    public static let iconFont = DSFont.iconFAB

    let accessibilityLabel: String
    let accessibilityIdentifier: String?
    let action: () -> Void

    public init(
        accessibilityLabel: String = "新規タスク",
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: Self.iconName)
                .font(Self.iconFont)
                .foregroundStyle(DSGradient.brand)
                .frame(width: Self.size, height: Self.size)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
        .modifier(OptionalAccessibilityIdentifier(accessibilityIdentifier))
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
#Preview("DSFAB") {
    DSFAB {}
        .padding(DSSpacing.l)
}
#endif
