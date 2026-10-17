import SwiftUI

/// プライマリ / セカンダリ / 破壊的の 3 variant を持つ標準ボタン。
/// 最小タッチ領域 `DSTouch.minSize`（44pt）を保証し、`isLoading` 中は無効化してスピナーを表示する。
public struct DSButton: View {
    public enum Variant: Sendable, CaseIterable {
        case primary
        case secondary
        case destructive
        /// 承認の主操作。
        case approve
        /// 却下・取り消しなどの注意操作。
        case declineOutline

        /// 破壊的操作のみ `.destructive` ロール（赤系・VoiceOver も破壊的と読む）。
        var role: ButtonRole? {
            self == .destructive ? .destructive : nil
        }

        /// テスト用スタイル契約（AtomsTests · DS-AUDIT-5）。
        package var foregroundToken: Color {
            switch self {
            case .primary, .approve:
                return IOSColor.accentOnFill
            case .destructive:
                return .white
            case .secondary:
                return IOSColor.text.primary
            case .declineOutline:
                return IOSColor.status.error
            }
        }

        package var backgroundToken: Color {
            switch self {
            case .primary:
                return IOSColor.accent
            case .destructive:
                return IOSColor.status.error
            case .secondary:
                return IOSColor.bg.fill
            case .declineOutline:
                return IOSColor.bg.fill
            case .approve:
                return IOSColor.accent
            }
        }

        package var borderToken: Color {
            switch self {
            case .secondary:
                return IOSColor.bg.separator
            case .declineOutline:
                return IOSColor.status.error
            default:
                return .clear
            }
        }
    }

    /// 全 variant 共通の最小高さ（= タッチターゲット下限）。
    static let minHeight: CGFloat = DSTouch.minSize
    static let cornerRadius = DSRadius.m

    let title: String
    let variant: Variant
    let isLoading: Bool
    let accessibilityIdentifier: String?
    let action: () -> Void

    package var isEnabled: Bool { !isLoading }

    public init(
        _ title: String,
        variant: Variant = .primary,
        isLoading: Bool = false,
        accessibilityIdentifier: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.isLoading = isLoading
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(role: variant.role, action: action) {
            ZStack {
                Text(title)
                    .font(DSFont.headline)
                    .opacity(isLoading ? 0 : 1)
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, minHeight: Self.minHeight)
            .padding(.horizontal, DSSpacing.l)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isLoading ? Text("読み込み中") : Text(""))
        .modifier(OptionalAccessibilityIdentifier(accessibilityIdentifier))
    }

    private var foreground: Color { variant.foregroundToken }

    private var background: Color { variant.backgroundToken }

    private var borderColor: Color { variant.borderToken }

    private var borderWidth: CGFloat {
        switch variant {
        case .secondary, .declineOutline:
            return 1
        default:
            return 0
        }
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
#Preview("DSButton") {
    VStack(spacing: DSSpacing.m) {
        DSButton("プライマリ", variant: .primary) {}
        DSButton("セカンダリ", variant: .secondary) {}
        DSButton("削除する", variant: .destructive) {}
        DSButton("読み込み中", variant: .primary, isLoading: true) {}
    }
    .padding(DSSpacing.l)
}
#endif
