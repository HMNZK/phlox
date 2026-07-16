import SwiftUI

/// チャット画面用入力バー（カンプ⑦）。紫枠のピル入力 + グラデ丸送信ボタン。
public struct DSChatInputBar: View {
    static let minHeight: CGFloat = DSTouch.minSize
    /// カンプの入力バー角丸（44px 高さの半分 = 22px）。
    static let fieldCornerRadius = DSRadius.dialog
    /// 送信丸ボタン内アイコン（白矢印）。
    static let sendButtonIconName = "arrow.up"
    static let sendButtonIconFont = DSFont.iconSend

    @Binding var text: String
    let placeholder: String
    let isLoading: Bool
    let onSubmit: () -> Void

    public init(
        text: Binding<String>,
        placeholder: String,
        isLoading: Bool = false,
        onSubmit: @escaping () -> Void
    ) {
        self._text = text
        self.placeholder = placeholder
        self.isLoading = isLoading
        self.onSubmit = onSubmit
    }

    /// 送信可能か（テスト可能な決定点）: 空白のみ・送信中は不可。
    static func canSubmit(text: String, isLoading: Bool) -> Bool {
        DSSubmitBarLogic.canSubmit(text: text, isLoading: isLoading)
    }

    private var canSubmit: Bool { Self.canSubmit(text: text, isLoading: isLoading) }

    public var body: some View {
        HStack(spacing: DSSpacing.s) {
            TextField(placeholder, text: $text, axis: .vertical)
                .font(DSFont.body)
                .foregroundStyle(DSColor.textPrimary)
                .tint(DSColor.accent)
                .lineLimit(1...4)
                .padding(.horizontal, DSSpacing.m)
                .frame(minHeight: Self.minHeight)
                .background(DSColor.surfaceElevated, in: fieldShape)
                .overlay(fieldShape.strokeBorder(DSColor.accent, lineWidth: 1))
                .accessibilityLabel(Text(placeholder))

            Button(action: submit) {
                ZStack {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DSColor.textOnBrand)
                    } else {
                        Image(systemName: Self.sendButtonIconName)
                            .font(Self.sendButtonIconFont)
                    }
                }
                .foregroundStyle(DSColor.textOnBrand)
                .frame(width: Self.minHeight, height: Self.minHeight)
                .background(DSGradient.brand, in: Circle())
                .dsShadow(DSShadow.fabGlow)
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.45)
            .accessibilityLabel(Text("送信"))
        }
    }

    private var fieldShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Self.fieldCornerRadius, style: .continuous)
    }

    private func submit() {
        guard canSubmit else { return }
        onSubmit()
    }
}

#if DEBUG
private struct DSChatInputBarPreviewHost: View {
    @State private var text = ""

    var body: some View {
        VStack(spacing: DSSpacing.m) {
            DSChatInputBar(text: $text, placeholder: "回答を入力…") {}
            DSChatInputBar(text: .constant("送信中"), placeholder: "回答を入力…", isLoading: true) {}
        }
        .padding(DSSpacing.l)
    }
}

#Preview("DSChatInputBar") {
    DSChatInputBarPreviewHost()
}
#endif
