#if os(macOS)
import AppKit
import SwiftTerm

/// SwiftTerm の macOS `NSTextInputClient` は marked text の描画が未実装のため、
/// 未確定文字をオーバーレイ表示する。
@MainActor
final class IMETerminalView: SwiftTerm.TerminalView {
    private let markedTextOverlay = MarkedTextOverlayView(frame: .zero)
    private var imeMarkedText: String?
    private var imeMarkedSelectedRange = NSRange(location: 0, length: 0)

    override init(frame: CGRect, font: NSFont?) {
        super.init(frame: frame, font: font)
        configureMarkedTextOverlay()
        syncScrollerVisibility()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureMarkedTextOverlay()
        syncScrollerVisibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - スクロールバーの表示制御

    override func bufferActivated(source: Terminal) {
        super.bufferActivated(source: source)
        syncScrollerVisibility()
    }

    override func scrolled(source terminal: Terminal, yDisp: Int) {
        super.scrolled(source: terminal, yDisp: yDisp)
        syncScrollerVisibility()
    }

    /// スクロールできない状態(alternate screen 中・スクロールバック履歴なし)では
    /// SwiftTerm が無効スクロールバーを全長 knob のまま表示し続けるため、
    /// スクロール可能なときだけスクロールバーを見せる。
    /// `NSScroller` は SwiftTerm の internal プロパティで直接触れないので subviews から探す。
    private func syncScrollerVisibility() {
        for subview in subviews {
            guard let scroller = subview as? NSScroller else { continue }
            scroller.isHidden = !canScroll
        }
    }

    private func configureMarkedTextOverlay() {
        markedTextOverlay.isHidden = true
        markedTextOverlay.wantsLayer = true
        markedTextOverlay.layer?.zPosition = 1000
        addSubview(markedTextOverlay, positioned: .above, relativeTo: nil)
    }

    override func layout() {
        super.layout()
        syncMarkedTextOverlayGeometry()
    }

    override func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        // SwiftTerm 標準実装は markedText を下線付きで terminal cell に書き込んでしまう。
        // 自前のオーバーレイで Claude Code 風に描画したいので super は呼ばない。
        // 代わりに hasMarkedText / markedRange / selectedRange を本クラスで完結させる。

        let text = Self.normalizedMarkedText(from: string)
        imeMarkedText = text
        imeMarkedSelectedRange = selectedRange

        if let text, !text.isEmpty {
            markedTextOverlay.markedText = text
            markedTextOverlay.selectedRange = selectedRange
            markedTextOverlay.textFont = font
            markedTextOverlay.isHidden = false
            syncMarkedTextOverlayGeometry()
        } else {
            clearMarkedTextOverlay()
        }
    }

    override func unmarkText() {
        clearMarkedTextOverlay()
        // SwiftTerm の super は markedText 状態を消すので、super も呼ばない
        // （自前で imeMarkedText を nil にすれば十分）
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        clearMarkedTextOverlay()
        super.insertText(string, replacementRange: replacementRange)
    }

    override func hasMarkedText() -> Bool {
        guard let imeMarkedText, !imeMarkedText.isEmpty else { return false }
        return true
    }

    override func markedRange() -> NSRange {
        guard let imeMarkedText, !imeMarkedText.isEmpty else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: (imeMarkedText as NSString).length)
    }

    override func selectedRange() -> NSRange {
        guard hasMarkedText() else {
            return super.selectedRange()
        }
        let markedLength = (imeMarkedText as NSString?)?.length ?? 0
        let location = min(imeMarkedSelectedRange.location, markedLength)
        let length = min(imeMarkedSelectedRange.length, markedLength - location)
        return NSRange(location: location, length: length)
    }

    override func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        if hasMarkedText(), !markedTextOverlay.isHidden {
            actualRange?.pointee = range
            if let rect = markedTextOverlay.window?.convertToScreen(
                markedTextOverlay.convert(markedTextOverlay.bounds, to: nil)
            ) {
                return rect
            }
        }
        return super.firstRect(forCharacterRange: range, actualRange: actualRange)
    }

    private func clearMarkedTextOverlay() {
        imeMarkedText = nil
        imeMarkedSelectedRange = NSRange(location: 0, length: 0)
        markedTextOverlay.markedText = ""
        markedTextOverlay.isHidden = true
    }

    private func syncMarkedTextOverlayGeometry() {
        guard !markedTextOverlay.isHidden else { return }

        let caret = caretFrame
        guard caret.width > 0, caret.height > 0 else { return }

        markedTextOverlay.textFont = font
        // textColor / backgroundFill は固定色 (Claude Code 純正キャレット風)
        let size = markedTextOverlay.intrinsicContentSize
        // overlay は文字幅・高さに正確に合わせる。caret の matrix で max を取らないことで、
        // 下のセル（claude TUI の input box 装飾）への被覆を最小化する。
        markedTextOverlay.frame = NSRect(
            x: caret.origin.x,
            y: caret.origin.y,
            width: size.width,
            height: size.height
        )
    }

    private static func normalizedMarkedText(from value: Any) -> String? {
        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        if let attributed = value as? AttributedString {
            return String(attributed.characters)
        }
        return nil
    }
}
#endif
