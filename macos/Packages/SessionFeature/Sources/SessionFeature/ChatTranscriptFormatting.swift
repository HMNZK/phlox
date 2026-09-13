import Foundation
import ChatRenderKit

enum ChatMarkdownBlock: Equatable, Sendable {
    case markdown(String)
    case code(language: String?, text: String)
}

enum ChatMarkdownFormatter {
    static func splitFencedCodeBlocks(_ text: String) -> [ChatMarkdownBlock] {
        TranscriptMarkdownPresentation.splitFencedCodeBlocks(text)
    }
}

// 既存の macOS 側参照を壊さないための薄い型名アダプタ。実装本体は ChatRenderKit にある。
typealias DiffLineKind = ChatDiffLineKind
typealias ClassifiedDiffLine = ChatDiffLine
typealias DiffLineClassifier = ChatDiffClassifier
