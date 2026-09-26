import ChatRenderKit
import DesignSystem
import Foundation
import SwiftUI

/// 会話の本文の段落を、Chat Screen.dc.html の `rich()` どおりに強調した文字列にする。
/// 太字・斜体・取り消し線・リンクは Markdown のまま、文中のコードは紫、書式の無いコード上の名前・
/// ファイル名・`.member` は等幅の地つきで色分けし、成功・失敗・増減は色つきの太字、数量は太字にする。
enum ChatProseText {
    static func attributed(markdown: String, scale: CGFloat) -> AttributedString {
        let key = "\(ThemeStore.active.id)\u{0}\(scale)\u{0}\(markdown)"
        return ChatMessageRenderCache.proseCache.value(for: key) { _ in compute(markdown, scale: scale) }
    }

    static func compute(_ markdown: String, scale: CGFloat = 1) -> AttributedString {
        // 文中のコードは MarkdownUI のテーマ（.code）と同じ小さめの等幅。
        let codeFont = Font.system(size: ChatTypography.codeFontSize(scale: scale), design: .monospaced)
        var text = (try? AttributedString(markdown: markdown, options: .init(interpretedSyntax: .inlineOnly)))
            ?? AttributedString(markdown)
        var plainRanges: [Range<AttributedString.Index>] = []
        for run in text.runs {
            let intent = run.inlinePresentationIntent ?? []
            if intent.contains(.code) {
                text[run.range].foregroundColor = DSColor.codeSyntaxKeyword
                text[run.range].backgroundColor = DSColor.fillSubtle
                text[run.range].font = codeFont
            } else if run.link != nil {
                // MarkdownUI のテーマ（.link）と同じリンク色。
                text[run.range].foregroundColor = DSColor.accentInk
            } else if !intent.contains(.stronglyEmphasized) {
                plainRanges.append(run.range)
            }
        }
        for range in plainRanges {
            let plain = String(text[range].characters)
            // 一致は前から順に並ぶので、直前の一致の終わりから数えて進める（長文でも線形）。
            var plainCursor = plain.startIndex
            var textCursor = range.lowerBound
            for span in ChatProseHighlighter.spans(in: plain) {
                let lower = text.characters.index(textCursor, offsetBy: plain.distance(from: plainCursor, to: span.range.lowerBound))
                let upper = text.characters.index(lower, offsetBy: plain[span.range].count)
                style(&text[lower..<upper], kind: span.kind, codeFont: codeFont)
                plainCursor = span.range.upperBound
                textCursor = upper
            }
        }
        return text
    }

    private static func style(_ part: inout AttributedSubstring, kind: ChatProseSpanKind, codeFont: Font) {
        let intent = part.inlinePresentationIntent ?? []
        switch kind {
        case .identifier, .file, .member:
            part.inlinePresentationIntent = intent.union(.code)
            part.font = codeFont
            part.backgroundColor = DSColor.fillSubtle
            part.foregroundColor = kind == .identifier ? DSColor.codeSyntaxKeyword
                : kind == .file ? DSColor.attentionInk(.question) : DSColor.codeSyntaxNumber
        case .success, .failure:
            part.inlinePresentationIntent = intent.union(.stronglyEmphasized)
            part.foregroundColor = kind == .success ? DSColor.diffAdded : DSColor.diffRemoved
        case .quantity:
            part.inlinePresentationIntent = intent.union(.stronglyEmphasized)
        }
    }
}
