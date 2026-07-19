import Foundation

/// 入力欄（ChatComposer）でハイライトすべき範囲の種別（task-2 契約面）。
enum ComposerHighlightKind: Equatable, Sendable {
    case slashCommand
    case fileReference
}

/// ハイライト範囲（UTF16 オフセット）と種別。
struct ComposerHighlightSpan: Equatable, Sendable {
    let range: Range<Int>
    let kind: ComposerHighlightKind
}

/// 入力テキストからハイライト範囲を導出する純関数（task-2 契約面）。
/// シグネチャは受け入れテスト AcceptanceComposerHighlightTests が凍結している（変更禁止）。
/// 契約:
///   - 先頭が "/" のとき、先頭スラッシュコマンドトークン（"/" ＋ 空白以外の連続文字、最初の空白/終端で停止）を
///     `.slashCommand` として1件。"/" が先頭でない場合は返さない。
///   - 空白区切りトークンのうち "@" で始まるものを各1件 `.fileReference`（"@" ＋ 空白以外の連続文字）。
///   - range は UTF16 オフセット。CJK/絵文字でも正しいこと。決定論。
enum ComposerHighlight {
    static func spans(in text: String) -> [ComposerHighlightSpan] {
        var spans: [ComposerHighlightSpan] = []
        var tokenStart = text.startIndex

        while tokenStart < text.endIndex {
            while tokenStart < text.endIndex, text[tokenStart].isWhitespace {
                tokenStart = text.index(after: tokenStart)
            }
            guard tokenStart < text.endIndex else { break }

            let tokenEnd = text[tokenStart...].firstIndex(where: \.isWhitespace) ?? text.endIndex
            let range = tokenStart.utf16Offset(in: text)..<tokenEnd.utf16Offset(in: text)

            if tokenStart == text.startIndex, text[tokenStart] == "/" {
                spans.append(ComposerHighlightSpan(range: range, kind: .slashCommand))
            } else if text[tokenStart] == "@" {
                spans.append(ComposerHighlightSpan(range: range, kind: .fileReference))
            }

            tokenStart = tokenEnd
        }

        return spans
    }
}
