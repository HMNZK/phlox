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
    @State private var didCopy = false
    @State private var resetTask: Task<Void, Never>?

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
        .background(DSColor.fillSubtle, in: Capsule())
        .help(didCopy ? "コピーしました" : "Copy message")
        .accessibilityLabel(didCopy ? "コピーしました" : "Copy message")
        .accessibilityIdentifier(accessibilityIdentifier)
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
