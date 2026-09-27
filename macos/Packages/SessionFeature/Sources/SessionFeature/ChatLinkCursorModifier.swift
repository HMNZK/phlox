import AppKit
import SwiftUI

/// 選択可能な Text はリンク部分にも I ビームを出すため、文字位置からリンクだけを判定する。
struct ChatLinkCursorModifier: ViewModifier {
    let text: AttributedString
    let scale: CGFloat
    let fontSize: CGFloat?
    let fontWeight: NSFont.Weight
    let lineSpacing: CGFloat?

    @State private var width: CGFloat = 0

    init(text: AttributedString, scale: CGFloat, fontSize: CGFloat? = nil,
         fontWeight: NSFont.Weight = .regular, lineSpacing: CGFloat? = nil) {
        self.text = text
        self.scale = scale
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.lineSpacing = lineSpacing
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if text.runs.contains(where: { $0.link != nil }) {
            content
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
                .onContinuousHover { phase in
                    if case .active(let point) = phase {
                        let cursor = ChatLinkHitTester.cursor(
                            in: text, at: point, width: width, scale: scale,
                            fontSize: fontSize, fontWeight: fontWeight, lineSpacing: lineSpacing
                        )
                        // 選択可能な Text が mouseMoved 後に I ビームへ戻すため、次の main turn で指定する。
                        DispatchQueue.main.async { cursor.set() }
                    } else {
                        NSCursor.arrow.set()
                    }
                }
        } else {
            content
        }
    }
}

enum ChatLinkHitTester {
    static func cursor(in text: AttributedString, at point: CGPoint, width: CGFloat, scale: CGFloat,
                       fontSize: CGFloat? = nil, fontWeight: NSFont.Weight = .regular,
                       lineSpacing: CGFloat? = nil) -> NSCursor {
        guard width > 0 else { return .arrow }
        let storage = NSTextStorage(attributedString: NSAttributedString(text))
        let fullRange = NSRange(location: 0, length: storage.length)
        guard fullRange.length > 0 else { return .arrow }

        let bodySize = fontSize ?? ChatTypography.bodyFontSize(scale: scale)
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            let size = intent.contains(.code) ? ChatTypography.codeFontSize(scale: scale) : bodySize
            let font: NSFont
            if intent.contains(.code) {
                font = .monospacedSystemFont(ofSize: size, weight: .regular)
            } else if intent.contains(.stronglyEmphasized) {
                font = .boldSystemFont(ofSize: size)
            } else {
                font = .systemFont(ofSize: size, weight: fontWeight)
            }
            storage.addAttribute(.font, value: font, range: NSRange(run.range, in: text))
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing ?? 6 * scale
        storage.addAttribute(.paragraphStyle, value: paragraph, range: fullRange)

        let layout = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        layout.ensureLayout(for: container)

        let glyph = layout.glyphIndex(for: point, in: container)
        guard layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) else {
            return .arrow
        }
        let character = layout.characterIndexForGlyph(at: glyph)
        return storage.attribute(.link, at: character, effectiveRange: nil) != nil ? .pointingHand : .iBeam
    }
}
