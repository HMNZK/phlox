import SwiftUI
import AppKit
import DesignSystem

/// ファイルタブの編集欄（07 D4）。左に行番号（幅 28・右寄せ・淡色）、カーソルのある行を淡く塗る。
/// SwiftUI の `TextEditor` には同期する行番号欄が無いので NSTextView を包む。
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.contentView.postsBoundsChangedNotifications = true
        // 行番号の計算に NSLayoutManager を使うので TextKit 1 で作る。
        let textView = CurrentLineTextView(usingTextLayoutManager: false)
        textView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        textView.string = text
        textView.delegate = context.coordinator
        scrollView.documentView = textView
        scrollView.drawsBackground = true

        let ruler = LineNumberRuler(textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CurrentLineTextView else { return }
        if textView.string != text { textView.string = text }
        let background = NSColor(DSColor.background)
        scrollView.backgroundColor = background
        textView.backgroundColor = background
        textView.textColor = NSColor(DSColor.textPrimary)
        textView.insertionPointColor = NSColor(DSColor.textPrimary)
        textView.currentLineColor = NSColor(DSColor.fillSelected)
        textView.needsDisplay = true
        if let ruler = scrollView.verticalRulerView as? LineNumberRuler {
            ruler.numberColor = NSColor(DSColor.textTertiary)
            ruler.backgroundColor = background
            ruler.needsDisplay = true
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            textView.needsDisplay = true
            textView.enclosingScrollView?.verticalRulerView?.needsDisplay = true
        }
    }
}

/// カーソルのある行（折り返しを含む論理行）の矩形。行番号欄と本文で同じ塗りを使う。
private extension NSTextView {
    var currentLineRect: NSRect? {
        guard let layoutManager, let textContainer, selectedRange().length == 0 else { return nil }
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: min(selectedRange().location, nsString.length), length: 0))
        let glyphs = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        // 末尾の改行の後ろ（空の最終行）は字形が無いので、余白の行の矩形を使う。
        var rect = glyphs.length == 0
            ? layoutManager.extraLineFragmentRect
            : layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        rect.origin.y += textContainerOrigin.y
        rect.origin.x = 0
        rect.size.width = bounds.width
        return rect
    }
}

final class CurrentLineTextView: NSTextView {
    var currentLineColor: NSColor = .clear

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if let line = currentLineRect {
            currentLineColor.setFill()
            line.fill()
        }
    }
}

/// 行番号欄。左 10・番号幅 28（右寄せ）・右 10（見本 PhloxAux のコード行）。
final class LineNumberRuler: NSRulerView {
    var numberColor: NSColor = .tertiaryLabelColor
    var backgroundColor: NSColor = .textBackgroundColor
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 48
        NotificationCenter.default.addObserver(
            self, selector: #selector(redraw), name: NSView.boundsDidChangeNotification,
            object: textView.enclosingScrollView?.contentView
        )
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func redraw() { needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        bounds.fill()
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else { return }
        let font = textView.font ?? .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: numberColor]
        let nsString = textView.string as NSString
        let offset = convert(NSPoint.zero, from: textView).y
        let origin = textView.textContainerOrigin.y

        if let line = textView.currentLineRect {
            (textView as? CurrentLineTextView)?.currentLineColor.setFill()
            NSRect(x: 0, y: line.minY + offset, width: bounds.width, height: line.height).fill()
        }

        func drawNumber(_ number: Int, lineRect: NSRect) {
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attributes)
            let y = lineRect.minY + origin + offset + (lineRect.height - size.height) / 2
            label.draw(at: NSPoint(x: 10 + 28 - size.width, y: y), withAttributes: attributes)
        }

        let visible = textView.visibleRect
        let glyphs = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let characters = layoutManager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        // ponytail: 表示範囲の先頭までの改行を毎回数える（O(n)）。巨大ファイルで重ければ行頭の索引を持つ。
        var number = 1
        nsString.enumerateSubstrings(in: NSRange(location: 0, length: characters.location), options: [.byLines, .substringNotRequired]) { _, _, _, _ in
            number += 1
        }
        if characters.location > 0, ![0x0A, 0x0D].contains(nsString.character(at: characters.location - 1)) { number -= 1 }

        var index = characters.location
        let end = NSMaxRange(characters)
        while index < end {
            let lineRange = nsString.lineRange(for: NSRange(location: index, length: 0))
            let lineGlyphs = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            guard lineGlyphs.length > 0 else { break }
            drawNumber(number, lineRect: layoutManager.lineFragmentRect(forGlyphAt: lineGlyphs.location, effectiveRange: nil))
            number += 1
            index = NSMaxRange(lineRange)
        }
        // 末尾が改行のとき、カーソルが置ける空の最終行にも番号を付ける。
        if index >= nsString.length, nsString.length == 0 || nsString.hasSuffix("\n") || nsString.hasSuffix("\r") {
            let extra = layoutManager.extraLineFragmentRect
            if extra.height > 0 { drawNumber(number, lineRect: extra) }
        }
    }
}
