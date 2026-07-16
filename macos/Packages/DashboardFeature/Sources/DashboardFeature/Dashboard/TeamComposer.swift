import SwiftUI
import AppKit
import DesignSystem
import SessionFeature

struct TeamComposer: View {
    let targetDisplayName: String?
    let isReadyForInput: Bool
    let onSend: (String) async throws -> Void

    @State private var draft = ""
    @State private var isFocused = false
    @State private var isComposing = false
    @State private var editorHeight = TeamComposerTextMetrics.minEditorHeight

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        targetDisplayName != nil && isReadyForInput && !trimmedDraft.isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.s) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                if let targetDisplayName {
                    Text("宛先: \(targetDisplayName)")
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textTertiary)
                }
                ZStack(alignment: .topLeading) {
                    TeamComposerTextInput(
                        text: $draft,
                        isComposing: $isComposing,
                        editorHeight: $editorHeight,
                        isEnabled: targetDisplayName != nil,
                        onFocusChange: { isFocused = $0 },
                        onSubmit: send
                    )
                    .frame(height: editorHeight)
                    .background(
                        RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                            .fill(DSColor.chatElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DSRadius.m, style: .continuous)
                            .stroke(isFocused ? DSColor.chatAccent : DSColor.border, lineWidth: 1)
                    )

                    if draft.isEmpty && !isComposing {
                        Text("メッセージを入力")
                            .font(DSFont.body)
                            .foregroundStyle(DSColor.textTertiary)
                            .padding(.horizontal, DSSpacing.m)
                            .padding(.vertical, DSSpacing.s)
                            .allowsHitTesting(false)
                    }
                }
            }

            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: DSIconSize.m, weight: .semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? DSColor.chatTextPrimary : DSColor.textTertiary)
            .background(
                Circle()
                    .fill(canSend ? DSColor.fillSelected : DSColor.fillSubtle)
            )
            .disabled(!canSend)
            .help("送信")
        }
        .padding(.horizontal, DSSpacing.l)
        .padding(.top, DSSpacing.s)
        .padding(.bottom, DSSpacing.m)
        .background(DSColor.chatBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DSColor.separator)
                .frame(height: 1)
        }
    }

    private func send() {
        let text = trimmedDraft
        guard canSend, !text.isEmpty else { return }
        draft = ""
        Task { @MainActor in
            do {
                try await onSend(text)
            } catch {
                draft = TeamComposerDraftPolicy.draftAfterSendFailure(
                    currentDraft: draft,
                    sentText: text
                )
            }
        }
    }
}

enum TeamComposerKeyRouting {
    static func action(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        isComposing: Bool
    ) -> ComposerKeyAction {
        ComposerKeyRouting.action(
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            isComposing: isComposing,
            suggestionsVisible: false
        )
    }
}

enum TeamComposerTextMetrics {
    static let maxVisibleLines = 6

    static var bodyFont: NSFont { .preferredFont(forTextStyle: .body) }

    static var lineHeight: CGFloat {
        ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading)
    }

    static var textInsets: NSSize {
        NSSize(width: DSSpacing.m, height: DSSpacing.s)
    }

    static var minEditorHeight: CGFloat {
        lineHeight + textInsets.height * 2
    }

    static var maxEditorHeight: CGFloat {
        lineHeight * CGFloat(maxVisibleLines) + textInsets.height * 2
    }

    static func resolvedHeight(usedTextHeight: CGFloat) -> CGFloat {
        min(
            maxEditorHeight,
            max(minEditorHeight, ceil(usedTextHeight + textInsets.height * 2))
        )
    }

    static func shouldWriteHeight(current: CGFloat, next: CGFloat) -> Bool {
        abs(current - next) > 0.5
    }
}

enum TeamComposerDraftPolicy {
    static func draftAfterSendFailure(currentDraft: String, sentText: String) -> String {
        currentDraft.isEmpty ? sentText : currentDraft
    }
}

private struct TeamComposerTextInput: NSViewRepresentable {
    @Binding var text: String
    @Binding var isComposing: Bool
    @Binding var editorHeight: CGFloat
    let isEnabled: Bool
    let onFocusChange: (Bool) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = true

        let textView = SubmitAwareTeamTextView()
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onComposingChanged = { [coordinator = context.coordinator] composing, currentText in
            coordinator.setComposing(composing, currentText: currentText)
        }
        textView.onFocusChange = onFocusChange
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = TeamComposerTextMetrics.bodyFont
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = TeamComposerTextMetrics.textInsets
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.minSize = NSSize(width: 0, height: TeamComposerTextMetrics.lineHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [.width]
        textView.string = text
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? SubmitAwareTeamTextView else { return }

        textView.onSubmit = onSubmit
        textView.onComposingChanged = { [coordinator = context.coordinator] composing, currentText in
            coordinator.setComposing(composing, currentText: currentText)
        }
        textView.onFocusChange = onFocusChange
        textView.isEditable = isEnabled
        textView.isSelectable = isEnabled

        if !textView.hasMarkedText(), textView.string != text {
            textView.syncStringFromBinding(text)
        }

        if let nextHeight = context.coordinator.resolvedHeight(for: textView),
           TeamComposerTextMetrics.shouldWriteHeight(current: editorHeight, next: nextHeight) {
            Task { @MainActor [weak textView, coordinator = context.coordinator] in
                guard let textView else { return }
                coordinator.recalculateHeight(for: textView)
            }
        }

        scrollView.hasVerticalScroller = editorHeight >= TeamComposerTextMetrics.maxEditorHeight
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TeamComposerTextInput

        init(_ parent: TeamComposerTextInput) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            if textView.hasMarkedText() {
                setComposing(true, currentText: textView.string)
                recalculateHeight(for: textView)
                return
            }
            parent.text = textView.string
            recalculateHeight(for: textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.onFocusChange(true)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onFocusChange(false)
        }

        func setComposing(_ composing: Bool, currentText: String) {
            if !composing, parent.text != currentText {
                parent.text = currentText
            }
            guard parent.isComposing != composing else { return }
            parent.isComposing = composing
        }

        func resolvedHeight(for textView: NSTextView) -> CGFloat? {
            guard let textContainer = textView.textContainer, let layoutManager = textView.layoutManager else { return nil }
            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            return TeamComposerTextMetrics.resolvedHeight(usedTextHeight: usedHeight)
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let nextHeight = resolvedHeight(for: textView) else { return }
            guard TeamComposerTextMetrics.shouldWriteHeight(current: parent.editorHeight, next: nextHeight) else { return }
            parent.editorHeight = nextHeight
        }
    }

    final class SubmitAwareTeamTextView: NSTextView {
        var onSubmit: (() -> Void)?
        var onComposingChanged: ((Bool, String) -> Void)?
        var onFocusChange: ((Bool) -> Void)?

        override func becomeFirstResponder() -> Bool {
            let became = super.becomeFirstResponder()
            if became {
                onFocusChange?(true)
            }
            return became
        }

        override func resignFirstResponder() -> Bool {
            let resigned = super.resignFirstResponder()
            if resigned {
                onFocusChange?(false)
            }
            return resigned
        }

        override func keyDown(with event: NSEvent) {
            switch TeamComposerKeyRouting.action(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                isComposing: hasMarkedText()
            ) {
            case .undo:
                undoManager?.undo()
            case .redo:
                undoManager?.redo()
            case .paste:
                paste(nil)
            case .submit:
                onSubmit?()
            case .insertNewline:
                insertNewline(nil)
            case .escape, .moveSuggestionUp, .moveSuggestionDown, .acceptSuggestion, .dismissSuggestions:
                super.keyDown(with: event)
            case .passToSystem:
                super.keyDown(with: event)
            }
        }

        func syncStringFromBinding(_ nextString: String) {
            guard string != nextString else { return }
            let currentSelection = selectedRange()
            let selectionLocation = min(currentSelection.location, nextString.utf16.count)
            let selectionLength = min(
                currentSelection.length,
                max(0, nextString.utf16.count - selectionLocation)
            )
            let manager = undoManager
            manager?.disableUndoRegistration()
            defer { manager?.enableUndoRegistration() }
            let attributedString = NSAttributedString(string: nextString, attributes: typingAttributes)
            if let textStorage {
                textStorage.setAttributedString(attributedString)
            } else {
                string = nextString
            }
            setSelectedRange(NSRange(location: selectionLocation, length: selectionLength))
            breakUndoCoalescing()
        }

        override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            super.setMarkedText(string, selectedRange: selectedRange, replacementRange: replacementRange)
            notifyComposingChanged()
        }

        override func unmarkText() {
            super.unmarkText()
            notifyComposingChanged()
        }

        override func didChangeText() {
            super.didChangeText()
            notifyComposingChanged()
        }

        private func notifyComposingChanged() {
            onComposingChanged?(hasMarkedText(), string)
        }
    }
}
