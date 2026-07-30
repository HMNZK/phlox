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
    @State private var isHovering = false
    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

    init(text: String, accessibilityIdentifier: String, scale: CGFloat, isVisible: Bool = true) {
        self.text = text
        self.accessibilityIdentifier = accessibilityIdentifier
        self.scale = scale
        self.isVisible = isVisible
    }

    var body: some View {
        Button(action: copyAndShowFeedback) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(ChatScaledFont.captionStrong(scale: scale))
                if didCopy {
                    Text("コピーしました")
                        .font(ChatScaledFont.captionStrong(scale: scale))
                }
            }
            .animation(.easeInOut(duration: 0.16), value: didCopy)
        }
        .buttonStyle(.plain)
        .foregroundStyle(DSColor.chatTextSecondary)
        .padding(DSSpacing.xs)
        .background {
            if MessageCopyButtonPresentation.showsHoverBackground(isHovering: isHovering) {
                Capsule().fill(DSColor.fillSubtle)
            }
        }
        .onHover { isHovering = $0 }
        .help(didCopy ? "コピーしました" : "Copy message")
        .accessibilityLabel(didCopy ? "コピーしました" : "Copy message")
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
