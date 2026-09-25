#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import DesignSystem

// C-11: 名前変更欄は、入力先のあいだだけ選んだ文字の面を --selText にし、離れたら元に戻す。↩ と Esc を呼び分ける。
@MainActor
@Suite("Inline text field")
struct DSInlineTextFieldTests {
    @Test
    func selectionUsesTheSelTextColorOnlyWhileEditing() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        let field = SelectionColoredTextField(string: "承認 API に失効処理を追加")
        let other = NSTextField(string: "ほか")
        window.contentView?.addSubview(field)
        window.contentView?.addSubview(other)

        #expect(window.makeFirstResponder(field))
        let editor = try #require(field.currentEditor() as? NSTextView)
        let expected = NSColor(DSColor.textSelection).usingColorSpace(.sRGB)
        let actual = (editor.selectedTextAttributes[.backgroundColor] as? NSColor)?.usingColorSpace(.sRGB)
        #expect(actual == expected)

        #expect(window.makeFirstResponder(other))
        let otherEditor = try #require(other.currentEditor() as? NSTextView)
        let restored = (otherEditor.selectedTextAttributes[.backgroundColor] as? NSColor)?.usingColorSpace(.sRGB)
        #expect(restored != expected)
    }

    /// 見本 PhloxSidebar の `--selText`（ライト rgba(217,119,87,.30)・ダーク .40）。
    @Test
    func selTextMatchesTheMock() throws {
        for (isDark, alpha) in [(false, 0.30), (true, 0.40)] {
            let color = try #require(NSColor(DSColor.textSelection(isDark: isDark)).usingColorSpace(.sRGB))
            #expect(abs(color.redComponent * 255 - 217) < 0.5)
            #expect(abs(color.greenComponent * 255 - 119) < 0.5)
            #expect(abs(color.blueComponent * 255 - 87) < 0.5)
            #expect(abs(color.alphaComponent - alpha) < 0.001)
        }
    }

    @Test
    func returnSubmitsAndEscapeCancels() {
        var submitted = 0
        var cancelled = 0
        let view = DSInlineTextField(
            text: .constant("名前"),
            placeholder: "名前",
            onSubmit: { submitted += 1 },
            onCancel: { cancelled += 1 },
            onEndEditing: {}
        )
        let coordinator = view.makeCoordinator()
        let control = NSTextField()
        let textView = NSTextView()
        #expect(coordinator.control(control, textView: textView, doCommandBy: #selector(NSResponder.insertNewline(_:))))
        #expect(coordinator.control(control, textView: textView, doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        #expect(!coordinator.control(control, textView: textView, doCommandBy: #selector(NSResponder.moveLeft(_:))))
        #expect(submitted == 1)
        #expect(cancelled == 1)
    }
}
#endif
