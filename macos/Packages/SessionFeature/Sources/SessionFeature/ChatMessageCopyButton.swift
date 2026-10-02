import AppKit
import SwiftUI
import DesignSystem

enum ChatMessageCopy {
    static func copyPlainTextToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct MessageCopyButton: View {
    let text: String
    let accessibilityIdentifier: String
    let scale: CGFloat
    let isVisible: Bool
    let helpKey: UIWording.Key
    @State private var isHovering = false
    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?
    @Environment(\.locale) private var locale

    private var languageCode: String { locale.language.languageCode?.identifier ?? locale.identifier }

    init(text: String, accessibilityIdentifier: String, scale: CGFloat, isVisible: Bool = true, helpKey: UIWording.Key = .copyMessageHelp) {
        self.text = text
        self.accessibilityIdentifier = accessibilityIdentifier
        self.scale = scale
        self.isVisible = isVisible
        self.helpKey = helpKey
    }

    var body: some View {
        Button(action: copyAndShowFeedback) {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11 * scale))
                .animation(.easeInOut(duration: 0.16), value: didCopy)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DSColor.chatTextSecondary)
        .frame(minWidth: 22 * scale, minHeight: 22 * scale)
        .background {
            // PhloxChat.dc.html: 22pt 角・角丸 5・ホバー色の面（行のホバーで出ている間は常に）。
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(MessageCopyButtonPresentation.showsHoverBackground(isHovering: isHovering) ? DSColor.fillSelected : DSColor.fillSubtle)
        }
        .onHover { isHovering = $0 }
        .help(didCopy ? UIWording.text(.copiedFeedback, languageCode: languageCode) : UIWording.text(helpKey, languageCode: languageCode))
        .accessibilityLabel(didCopy ? UIWording.text(.copiedFeedback, languageCode: languageCode) : UIWording.text(helpKey, languageCode: languageCode))
        .accessibilityIdentifier(accessibilityIdentifier)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
    }

    private func copyAndShowFeedback() {
        ChatMessageCopy.copyPlainTextToPasteboard(text)
        resetTask?.cancel()
        didCopy = true
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            didCopy = false
            resetTask = nil
        }
    }
}

enum MessageCopyButtonPresentation {
    static func showsHoverBackground(isHovering: Bool) -> Bool { isHovering }
}
