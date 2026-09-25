#if os(macOS)
import SwiftUI
import AppKit

/// 行の中で名前を書き換える 1 行の入力欄（03 F6・PhloxSidebar の renaming）。
/// 選んだ文字の面を `--selText`（`DSColor.textSelection`）にするため AppKit の `NSTextField` を使う
/// （SwiftUI の `TextField` では選択の色を変えられない。C-11）。
/// 出たら入力先になって全体を選ぶ。↩ で `onSubmit`、Esc で `onCancel`、ほかへ移ったら `onEndEditing`。
public struct DSInlineTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let fontSize: CGFloat
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onEndEditing: () -> Void

    public init(
        text: Binding<String>,
        placeholder: String,
        fontSize: CGFloat = 13,
        onSubmit: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onEndEditing: @escaping () -> Void
    ) {
        _text = text
        self.placeholder = placeholder
        self.fontSize = fontSize
        self.onSubmit = onSubmit
        self.onCancel = onCancel
        self.onEndEditing = onEndEditing
    }

    public func makeCoordinator() -> Coordinator { Coordinator(self) }

    public func makeNSView(context: Context) -> NSTextField {
        let field = SelectionColoredTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.font = .systemFont(ofSize: fontSize)
        field.placeholderString = placeholder
        field.stringValue = text
        field.delegate = context.coordinator
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    public func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        field.textColor = NSColor(DSColor.textPrimary)
    }

    public final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: DSInlineTextField

        init(_ parent: DSInlineTextField) { self.parent = parent }

        public func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onCancel()
                return true
            default:
                return false
            }
        }

        public func controlTextDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }
    }
}

/// 入力先になったあいだだけ、共有の入力エディタの選択色を `--selText` にする（離れたら元に戻す）。
final class SelectionColoredTextField: NSTextField {
    private var savedSelectionAttributes: [NSAttributedString.Key: Any]?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became, let editor = currentEditor() as? NSTextView {
            savedSelectionAttributes = editor.selectedTextAttributes
            editor.selectedTextAttributes = [.backgroundColor: NSColor(DSColor.textSelection)]
        }
        return became
    }

    override func textDidEndEditing(_ notification: Notification) {
        if let editor = currentEditor() as? NSTextView, let savedSelectionAttributes {
            editor.selectedTextAttributes = savedSelectionAttributes
        }
        savedSelectionAttributes = nil
        super.textDidEndEditing(notification)
    }
}
#endif
