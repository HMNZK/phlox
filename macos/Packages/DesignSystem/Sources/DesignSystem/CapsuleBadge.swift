import SwiftUI

/// 文字と淡い面だけのカプセル（「承認待ち · 3分」）。ドットと SF Symbol は使わない（12 Design System）。
public struct CapsuleBadge: View {
    public let label: String
    public let ink: Color
    public let tint: Color

    public init(label: String, ink: Color, tint: Color) {
        self.label = label
        self.ink = ink
        self.tint = tint
    }

    public var body: some View {
        Text(label)
            .font(DSFont.auxiliary.weight(.semibold))
            .foregroundStyle(ink)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(tint, in: RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous))
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
    }
}
