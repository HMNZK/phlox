import Foundation
import ChatRenderKit
import DesignSystem

/// 原文を保持したまま、閲覧用の長い行だけ省略する。
final class ReadOnlyText {
    private struct Part {
        let text: String
        let omitted: Int
        let newline: String
    }
    private let parts: [Part]
    let hasOmittedLines: Bool

    init(_ text: String) {
        let source = text as NSString
        var parts: [Part] = []
        var offset = 0
        var start = 0
        var hasOmittedLines = false
        let limit = ChatCodeTokenizer.maximumLineUTF16Length
        while offset < source.length {
            var end = 0
            var contentsEnd = 0
            source.getLineStart(nil, end: &end, contentsEnd: &contentsEnd,
                                for: NSRange(location: offset, length: 0))
            if contentsEnd - offset > limit {
                var cut = offset + limit
                let boundary = source.rangeOfComposedCharacterSequence(at: cut - 1)
                if NSMaxRange(boundary) > cut { cut = boundary.location }
                let omitted = source.substring(with: NSRange(location: cut, length: contentsEnd - cut)).count
                hasOmittedLines = true
                parts.append(Part(text: source.substring(with: NSRange(location: start, length: cut - start)),
                                  omitted: omitted,
                                  newline: source.substring(with: NSRange(location: contentsEnd, length: end - contentsEnd))))
                start = end
            }
            offset = end
        }
        parts.append(Part(text: source.substring(from: start), omitted: 0, newline: ""))
        self.parts = parts
        self.hasOmittedLines = hasOmittedLines
    }

    func display(locale: Locale, bundle: Bundle) -> (text: String, markers: [NSRange]) {
        let format = AppLocalizedString.string("…（残り %lld 文字を省略）", locale: locale, bundle: bundle)
        var text = ""
        var markers: [NSRange] = []
        var offset = 0
        for part in parts {
            text += part.text
            offset += part.text.utf16.count
            if part.omitted > 0 {
                let marker = String(format: format, Int64(part.omitted))
                markers.append(NSRange(location: offset, length: marker.utf16.count))
                text += marker
                offset += marker.utf16.count
            }
            text += part.newline
            offset += part.newline.utf16.count
        }
        return (text, markers)
    }
}
