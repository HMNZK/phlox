#if os(macOS)
import AppKit

/// 日本語 IME の未確定文字（marked text）を Claude Code 純正キャレット風に描画する。
@MainActor
final class MarkedTextOverlayView: NSView {
    var markedText: String = "" {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
            isHidden = markedText.isEmpty
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // SwiftTerm の CALayer 描画より確実に手前へ。
        wantsLayer = true
        layer?.zPosition = 1000
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// IME が示すカーソル位置（caret）。`length == 0` のときは insertion point として右端を強調する。
    var selectedRange: NSRange = NSRange(location: 0, length: 0) {
        didSet { needsDisplay = true }
    }

    var textFont: NSFont = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    /// Claude Code 純正キャレットに合わせた、暗めだが穏やかな文字色。
    var textColor: NSColor = NSColor(srgbRed: 0.18, green: 0.14, blue: 0.14, alpha: 1.0)
    /// 未確定文字全体の背景。Claude 純正の淡いピンクベージュに寄せて明るめに。
    var backgroundFill: NSColor = NSColor(srgbRed: 0.99, green: 0.92, blue: 0.89, alpha: 1.0)
    /// IME キャレット位置の濃い背景。背景を明るくした分、こちらも対応して柔らかく。
    var caretHighlight: NSColor = NSColor(srgbRed: 0.97, green: 0.80, blue: 0.78, alpha: 1.0)

    override var isOpaque: Bool { false }

    override var intrinsicContentSize: NSSize {
        guard !markedText.isEmpty else { return .zero }
        let attributes: [NSAttributedString.Key: Any] = [.font: textFont]
        let size = (markedText as NSString).size(withAttributes: attributes)
        // 文字ぴったりのサイズ。余白を入れない（下のセルへの被覆を最小限に保つ）
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !markedText.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: textColor,
        ]
        let nsText = markedText as NSString
        let textSize = nsText.size(withAttributes: attributes)
        let rowHeight = min(bounds.height, ceil(textSize.height))
        let totalWidth = min(bounds.width, ceil(textSize.width))

        // 1) 未確定文字全体の薄ピンク背景。
        backgroundFill.setFill()
        NSRect(x: 0, y: 0, width: totalWidth, height: rowHeight).fill()

        // 2) IME のキャレット位置（selectedRange）を濃いピンクで強調。
        let safeRange = clampedSelectedRange(textLength: nsText.length)
        let caretFill = caretHighlightRect(
            nsText: nsText,
            attributes: attributes,
            range: safeRange,
            rowHeight: rowHeight,
            totalWidth: totalWidth
        )
        if let caretFill {
            caretHighlight.setFill()
            caretFill.fill()
        }

        // 3) テキスト描画（背景の上に乗る）。
        let origin = NSPoint(x: 0, y: max(0, (bounds.height - textSize.height) / 2))
        nsText.draw(at: origin, withAttributes: attributes)
    }

    private func clampedSelectedRange(textLength: Int) -> NSRange {
        let location = max(0, min(selectedRange.location, textLength))
        let length = max(0, min(selectedRange.length, textLength - location))
        return NSRange(location: location, length: length)
    }

    /// IME キャレット部分の塗りつぶし矩形。`length == 0` のときは末尾に caret 風の縦棒を返す。
    private func caretHighlightRect(
        nsText: NSString,
        attributes: [NSAttributedString.Key: Any],
        range: NSRange,
        rowHeight: CGFloat,
        totalWidth: CGFloat
    ) -> NSRect? {
        let prefix = nsText.substring(with: NSRange(location: 0, length: range.location))
        let prefixWidth = ceil((prefix as NSString).size(withAttributes: attributes).width)

        if range.length == 0 {
            // insertion point: 末尾に細い縦棒を描く。
            let caretWidth: CGFloat = 2
            let x = min(prefixWidth, max(0, totalWidth - caretWidth))
            return NSRect(x: x, y: 0, width: caretWidth, height: rowHeight)
        }

        let selectedText = nsText.substring(with: range)
        let selectedWidth = ceil((selectedText as NSString).size(withAttributes: attributes).width)
        return NSRect(x: prefixWidth, y: 0, width: selectedWidth, height: rowHeight)
    }
}
#endif
