import SwiftUI

/// クリアボタン付きテキストフィールド。最小タッチ高さを保証し、focus に追従する。
public struct DSTextField: View {
    static let minHeight: CGFloat = DSTouch.minSize

    @Binding var text: String
    let placeholder: String
    let isSecure: Bool
    let usesCampMono: Bool
    let showsVisibilityToggle: Bool
    @Binding var isVisible: Bool
    @FocusState private var focused: Bool

    private var effectiveIsSecure: Bool {
        showsVisibilityToggle ? !isVisible : isSecure
    }

    private var fieldFont: Font {
        usesCampMono ? DSFont.campMono : DSFont.body
    }

    public init(
        text: Binding<String>,
        placeholder: String,
        isSecure: Bool = false,
        usesCampMono: Bool = false,
        showsVisibilityToggle: Bool = false,
        isVisible: Binding<Bool> = .constant(true)
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.usesCampMono = usesCampMono
        self.showsVisibilityToggle = showsVisibilityToggle
        self._isVisible = isVisible
    }

    public var body: some View {
        HStack(spacing: DSSpacing.s) {
            Group {
                if effectiveIsSecure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(fieldFont)
            .foregroundStyle(DSColor.textPrimary)
            .tint(DSColor.accent)
            .focused($focused)

            if showsVisibilityToggle {
                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundStyle(DSColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(isVisible ? "トークンを非表示" : "トークンを表示"))
            } else if !text.isEmpty {
                Button {
                    text = ""
                    focused = true
                } label: {
                    Image(systemName: DSIcon.clear)
                        .foregroundStyle(DSColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("クリア"))
            }
        }
        .padding(.horizontal, DSSpacing.m)
        .frame(minHeight: Self.minHeight)
        .background(DSColor.surfaceElevated, in: RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                .strokeBorder(focused ? DSColor.accent : DSColor.border, lineWidth: 1)
        )
        .accessibilityLabel(Text(placeholder))
    }
}

#if DEBUG
private struct DSTextFieldPreviewHost: View {
    @State private var text = ""
    @State private var secret = "token-123"
    @State private var isTokenVisible = false
    var body: some View {
        VStack(spacing: DSSpacing.m) {
            DSTextField(text: $text, placeholder: "ホスト名")
            DSTextField(text: $secret, placeholder: "トークン", isSecure: true)
            DSTextField(
                text: $secret,
                placeholder: "トークン",
                usesCampMono: true,
                showsVisibilityToggle: true,
                isVisible: $isTokenVisible
            )
        }
        .padding(DSSpacing.l)
    }
}

#Preview("DSTextField") {
    DSTextFieldPreviewHost()
}
#endif
