import SwiftUI
import DesignSystem

struct ChatCodeCard<Header: View, Content: View>: View {
    let copyText: String
    let copyAccessibilityIdentifier: String
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content
    @State private var isHovering = false
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id
    @AppStorage(ChatFontSettings.scaleKey) private var chatScale = ChatFontSettings.defaultScale

    var body: some View {
        let _ = themeID
        let scale = ChatFontSettings.adjusted(from: chatScale, by: 0)
        let shape = RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: DSSpacing.s) {
                header
                Spacer(minLength: 0)
                MessageCopyButton(
                    text: copyText,
                    accessibilityIdentifier: copyAccessibilityIdentifier,
                    scale: scale,
                    isVisible: isHovering
                )
            }
            .padding(.horizontal, DSSpacing.m)
            .padding(.vertical, DSSpacing.s)

            content
        }
        .background(DSColor.chatCard)
        .clipShape(shape)
        .overlay(shape.strokeBorder(DSColor.border, lineWidth: 1))
        .onHover { isHovering = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovering)
    }
}
