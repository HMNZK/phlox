import SwiftUI

/// 色＋ドット＋アイコン＋文字のカプセル状バッジ（状態は色だけに頼らない）。
public struct CapsuleBadge: View {
    public let label: String
    public let iconName: String
    public let tint: Color

    public init(label: String, iconName: String, tint: Color) {
        self.label = label
        self.iconName = iconName
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Image(systemName: iconName)
                .font(.system(size: 9, weight: .semibold))
            Text(label)
                .font(DSFont.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DSSpacing.s)
        .padding(.vertical, DSSpacing.xxs)
        .background(tint.opacity(0.14), in: Capsule(style: .continuous))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}
