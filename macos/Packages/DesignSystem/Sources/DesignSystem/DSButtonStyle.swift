import SwiftUI

/// 共通のボタン（12 Design System P「ボタン」）。高さ 28・角丸 6・13pt。
/// 主 = accent の面に白文字 600、副 = 操作面＋0.5pt の縁、破壊的 = 副の形に赤い文字 600、
/// 文字だけ = 面なしの補助色。無効は 45%。`keyHint` はボタン内の小さなキーの表示（10.5pt・0.85）。
/// 小さい面（07 のコミット欄 24 高・12pt、使用量の「更新」22 高・11.5pt）は高さ・文字・左右の余白を渡す。
public struct DSButtonStyle: ButtonStyle {
    public enum Kind: Sendable {
        case primary
        case secondary
        case destructive
        case plain
    }

    let kind: Kind
    let keyHint: String?
    let height: CGFloat
    let fontSize: CGFloat
    let padding: CGFloat?
    let fillsWidth: Bool
    @Environment(\.isEnabled) private var isEnabled

    public init(_ kind: Kind, keyHint: String? = nil, height: CGFloat = 28, fontSize: CGFloat = 13, padding: CGFloat? = nil, fillsWidth: Bool = false) {
        self.kind = kind
        self.fillsWidth = fillsWidth
        self.keyHint = keyHint
        self.height = height
        self.fontSize = fontSize
        self.padding = padding
    }

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.label
            if let keyHint {
                Text(keyHint)
                    .font(.system(size: 10.5))
                    .opacity(0.85)
            }
        }
        .font(.system(size: fontSize, weight: kind == .primary || kind == .destructive ? .semibold : .regular))
        .foregroundStyle(foreground)
        .lineLimit(1)
        .padding(.horizontal, padding ?? horizontalPadding)
        .frame(maxWidth: fillsWidth ? .infinity : nil)
        .frame(height: height)
        .background {
            switch kind {
            case .primary:
                RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous).fill(DSColor.accentFill)
            case .secondary, .destructive:
                RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                    .fill(DSColor.controlBackground)
                    .overlay {
                        RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous)
                            .strokeBorder(DSColor.controlBorder, lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.1), radius: 0.5, y: 0.5)
            case .plain:
                EmptyView()
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.row, style: .continuous))
        .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary: DSColor.textPrimary
        case .destructive: DSColor.statusError
        case .plain: DSColor.textSecondary
        }
    }

    private var horizontalPadding: CGFloat {
        switch kind {
        case .primary: 14
        case .secondary, .destructive: 12
        case .plain: 6
        }
    }
}

public extension ButtonStyle where Self == DSButtonStyle {
    static func ds(_ kind: DSButtonStyle.Kind, keyHint: String? = nil, height: CGFloat = 28, fontSize: CGFloat = 13, padding: CGFloat? = nil, fillsWidth: Bool = false) -> DSButtonStyle {
        DSButtonStyle(kind, keyHint: keyHint, height: height, fontSize: fontSize, padding: padding, fillsWidth: fillsWidth)
    }
}
