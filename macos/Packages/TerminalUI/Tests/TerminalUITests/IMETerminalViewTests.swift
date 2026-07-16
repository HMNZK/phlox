import AppKit
import Testing
@testable import TerminalUI

/// IMETerminalView の IME 未確定文字（marked text）ライフサイクルの検証。
/// NSTextInputClient のオーバーライド（setMarkedText / unmarkText / insertText /
/// hasMarkedText / markedRange / selectedRange）はウィンドウ不要で直接呼べる。
@MainActor
@Suite struct IMETerminalViewTests {
    private let view = IMETerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 480))

    /// オーバーレイは private のため、subview から型で引き当てる（可視性は緩めない）。
    private var overlay: MarkedTextOverlayView? {
        view.subviews.compactMap { $0 as? MarkedTextOverlayView }.first
    }

    @Test func setMarkedText_withNSAttributedString_reportsMarkedStateAndRange() {
        let text = NSAttributedString(string: "にほんご")

        view.setMarkedText(text, selectedRange: NSRange(location: 0, length: 4), replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: 0, length: ("にほんご" as NSString).length))
        #expect(overlay?.isHidden == false)
    }

    @Test func setMarkedText_withString_reportsMarkedState() {
        view.setMarkedText("abc", selectedRange: NSRange(location: 0, length: 3), replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: 0, length: 3))
    }

    @Test func setMarkedText_withAttributedString_reportsMarkedState() {
        let text = AttributedString("かな")

        view.setMarkedText(text, selectedRange: NSRange(location: 0, length: 2), replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: 0, length: 2))
    }

    @Test func selectedRange_locationBeyondTextLength_isClampedToTextEnd() {
        view.setMarkedText("abc", selectedRange: NSRange(location: 10, length: 5), replacementRange: NSRange(location: NSNotFound, length: 0))

        // location は文字長 3 へ、length は残り 0 へクランプされる（NSString 範囲外参照の防止）。
        #expect(view.selectedRange() == NSRange(location: 3, length: 0))
    }

    @Test func selectedRange_lengthOverrunningTextEnd_isClampedToRemainder() {
        view.setMarkedText("abcde", selectedRange: NSRange(location: 3, length: 10), replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(view.selectedRange() == NSRange(location: 3, length: 2))
    }

    @Test func unmarkText_clearsMarkedStateAndHidesOverlay() {
        view.setMarkedText("abc", selectedRange: NSRange(location: 0, length: 3), replacementRange: NSRange(location: NSNotFound, length: 0))

        view.unmarkText()

        #expect(!view.hasMarkedText())
        #expect(view.markedRange() == NSRange(location: NSNotFound, length: 0))
        #expect(overlay?.isHidden == true)
    }

    @Test func insertText_afterMarkedText_hidesOverlay() {
        view.setMarkedText("にほんご", selectedRange: NSRange(location: 0, length: 4), replacementRange: NSRange(location: NSNotFound, length: 0))

        view.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(!view.hasMarkedText())
        #expect(overlay?.isHidden == true)
    }

    @Test func setMarkedText_withEmptyString_clearsMarkedStateAndHidesOverlay() {
        view.setMarkedText("abc", selectedRange: NSRange(location: 0, length: 3), replacementRange: NSRange(location: NSNotFound, length: 0))

        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(!view.hasMarkedText())
        #expect(overlay?.isHidden == true)
    }

    @Test func markedRange_withSurrogatePair_usesNSStringLength() {
        // 絵文字はサロゲートペアで NSString length 2。"😀あ" は 2 + 1 = 3。
        view.setMarkedText("😀あ", selectedRange: NSRange(location: 0, length: 3), replacementRange: NSRange(location: NSNotFound, length: 0))

        #expect(("😀あ" as NSString).length == 3)
        #expect(view.markedRange() == NSRange(location: 0, length: 3))
        #expect(view.selectedRange() == NSRange(location: 0, length: 3))
    }
}
