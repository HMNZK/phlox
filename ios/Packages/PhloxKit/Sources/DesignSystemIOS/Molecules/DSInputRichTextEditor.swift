#if os(iOS)
import DesignSystem
import Foundation
import SwiftUI
import UIKit

/// 本文、画像マーカー、選択範囲、キャレットを同じ TextKit レイアウトで描く。
struct DSInputRichTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var cursorUTF16: Int
    @Binding var isFocused: Bool
    @Binding var hasMarkedText: Bool
    let dynamicTypeSize: DynamicTypeSize
    let accessibilityLabel: String
    let submission: Submission
    let submissionRevision: Int

    @MainActor
    @Observable
    final class Submission {
        @ObservationIgnored weak var view: UITextView?
        var composingText: String?
        var revision = 0

        func commit() {
            guard let view, let coordinator = view.delegate as? Coordinator else { return }
            coordinator.commitNativeState(from: view)
            revision &+= 1
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        submission.view = view
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.showsVerticalScrollIndicator = false
        view.adjustsFontForContentSizeCategory = false
        view.font = DSFont.inputBarTextFieldUIFont(for: dynamicTypeSize)
        view.tintColor = UIColor(IOSColor.accent)
        view.accessibilityLabel = accessibilityLabel
        view.attributedText = attributedText()
        view.typingAttributes = baseAttributes()
        view.selectedRange = NSRange(location: DSInputCursorMath.clampedCursorUTF16(cursorUTF16, textUTF16Count: text.utf16.count), length: 0)
        context.coordinator.lastExternalText = text
        context.coordinator.lastExternalCursor = cursorUTF16
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        view.accessibilityLabel = accessibilityLabel
        view.tintColor = UIColor(IOSColor.accent)
        coordinator.updateMarkedText(in: view)

        // IME の未確定文字列は UITextInput の所有物。属性・本文・選択を触らない。
        guard view.markedTextRange == nil else { return }

        let nativeEditPending = coordinator.pendingNativeText == view.text
            && text == coordinator.lastExternalText
        if view.text != text && !nativeEditPending {
            coordinator.delivery.invalidate()
            coordinator.isApplying = true
            view.attributedText = attributedText()
            view.typingAttributes = baseAttributes()
            view.selectedRange = NSRange(location: DSInputCursorMath.clampedCursorUTF16(cursorUTF16, textUTF16Count: text.utf16.count), length: 0)
            coordinator.isApplying = false
            coordinator.pendingNativeText = nil
            coordinator.lastExternalText = text
            coordinator.lastExternalCursor = cursorUTF16
        } else if view.text == text {
            coordinator.lastExternalText = text
            coordinator.pendingNativeText = nil
            let styled = attributedText()
            if !view.attributedText.isEqual(to: styled) {
                let selection = view.selectedRange
                coordinator.isApplying = true
                view.attributedText = styled
                view.typingAttributes = baseAttributes()
                view.selectedRange = selection
                coordinator.isApplying = false
            }
        }

        if cursorUTF16 != coordinator.lastExternalCursor {
            coordinator.delivery.invalidate()
            let location = DSInputCursorMath.clampedCursorUTF16(cursorUTF16, textUTF16Count: view.text.utf16.count)
            coordinator.isApplying = true
            view.selectedRange = NSRange(location: location, length: 0)
            coordinator.isApplying = false
            coordinator.lastExternalCursor = cursorUTF16
        }
        coordinator.updateFocus(in: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let lineHeight = DSFont.inputBarTextFieldUIFont(for: dynamicTypeSize).lineHeight
        let maximumHeight = ceil(lineHeight * CGFloat(DSInputBar.maximumTextLineCount))
        let storage = NSTextStorage(attributedString: view.attributedText)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let trailingLine = view.text.hasSuffix("\n") ? lineHeight : 0
        let measured = layout.usedRect(for: container).height + trailingLine
        let shouldScroll = measured > maximumHeight
        if view.isScrollEnabled != shouldScroll { view.isScrollEnabled = shouldScroll }
        return CGSize(width: width, height: ceil(min(max(measured, lineHeight), maximumHeight)))
    }

    private func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: DSFont.inputBarTextFieldUIFont(for: dynamicTypeSize),
            .foregroundColor: UIColor(IOSColor.text.primary),
        ]
    }

    private func attributedText() -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: baseAttributes())
        let expression = try? NSRegularExpression(pattern: #"\[Image #[0-9]+\]"#)
        let range = NSRange(location: 0, length: (text as NSString).length)
        let markerAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.boldSystemFont(ofSize: DSFont.inputBarTextFieldPointSize(for: dynamicTypeSize)),
            .foregroundColor: UIColor(IOSColor.accent),
        ]
        expression?.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            result.addAttributes(markerAttributes, range: match.range)
        }
        return result
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: DSInputRichTextEditor
        let delivery = DSInputSelectionDelivery()
        let focusDelivery = DSInputSelectionDelivery()
        let markedTextDelivery = DSInputSelectionDelivery()
        var lastExternalText = ""
        var lastExternalCursor = -1
        var pendingNativeText: String?
        var isApplying = false
        private var focusGeneration = 0

        init(_ parent: DSInputRichTextEditor) { self.parent = parent }

        @discardableResult
        func updateFocus(in view: UITextView) -> Task<Void, Never>? {
            focusDelivery.invalidate()
            let focused = parent.isFocused
            guard focused != view.isFirstResponder else { return nil }
            // UIKitのキーボード更新をSwiftUIの画面更新へ再入させない。
            return focusDelivery.enqueue(isCurrent: { [weak self, weak view] in
                guard let self, let view else { return false }
                return parent.isFocused == focused && view.window != nil && view.isFirstResponder != focused
            }) { [weak view] in
                if focused { view?.becomeFirstResponder() }
                else { view?.resignFirstResponder() }
            }
        }

        func textViewDidChange(_ textView: UITextView) { publishNativeState(from: textView) }

        func textViewDidChangeSelection(_ textView: UITextView) { publishNativeState(from: textView) }

        @discardableResult
        func updateMarkedText(in view: UITextView) -> Task<Void, Never>? {
            markedTextDelivery.invalidate()
            let marked = view.markedTextRange != nil && !view.text.isEmpty
            guard parent.hasMarkedText != marked else { return nil }
            // 未確定の本文は公開せず、placeholder に必要な変換状態だけを渡す。
            return markedTextDelivery.enqueue(isCurrent: { [weak view] in
                guard let view else { return false }
                return (view.markedTextRange != nil && !view.text.isEmpty) == marked
            }) { [weak self] in
                self?.parent.hasMarkedText = marked
            }
        }

        func commitNativeState(from view: UITextView) {
            view.unmarkText()
            // 確定に伴う遅延通知で、送信受付後のクリアを巻き戻さない。
            delivery.invalidate()
            markedTextDelivery.invalidate()
            parent.hasMarkedText = false
            parent.submission.composingText = nil
            applyNativeState(text: view.text ?? "", cursor: view.selectedRange.location)
        }

        private func applyNativeState(text: String, cursor: Int) {
            if parent.text != text { parent.text = text }
            if parent.cursorUTF16 != cursor { parent.cursorUTF16 = cursor }
            lastExternalText = text
            lastExternalCursor = cursor
            pendingNativeText = nil
        }

        private func publishNativeState(from view: UITextView) {
            guard !isApplying else { return }
            updateMarkedText(in: view)
            let capturedText = view.text ?? ""
            let capturedCursor = view.selectedRange.location
            let isComposing = view.markedTextRange != nil
            if !isComposing { pendingNativeText = capturedText }
            delivery.enqueue(isCurrent: { [weak view] in
                guard let view else { return false }
                return (view.markedTextRange != nil) == isComposing && view.text == capturedText
                    && view.selectedRange.location == capturedCursor
            }) { [weak self] in
                guard let self else { return }
                parent.submission.composingText = isComposing ? capturedText : nil
                guard !isComposing else { return }
                applyNativeState(text: capturedText, cursor: capturedCursor)
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) { publishFocus(true, from: textView) }
        func textViewDidEndEditing(_ textView: UITextView) { publishFocus(false, from: textView) }

        private func publishFocus(_ focused: Bool, from view: UITextView) {
            focusGeneration += 1
            let generation = focusGeneration
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, focusGeneration == generation, view.isFirstResponder == focused,
                      parent.isFocused != focused else { return }
                parent.isFocused = focused
            }
        }
    }
}
#endif
