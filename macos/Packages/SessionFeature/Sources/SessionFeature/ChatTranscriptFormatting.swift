import Foundation
import ChatRenderKit

enum ChatMarkdownBlock: Equatable, Sendable {
    case markdown(String)
    case code(language: String?, text: String)
}

enum ChatMarkdownFormatter {
    static func splitFencedCodeBlocks(_ text: String) -> [ChatMarkdownBlock] {
        var blocks: [ChatMarkdownBlock] = []
        var markdownLines: [String] = []
        var codeLines: [String] = []
        var codeLanguage: String?
        var isInsideFence = false

        func flushMarkdown() {
            let text = markdownLines.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.isEmpty {
                blocks.append(.markdown(text))
            }
            markdownLines.removeAll()
        }

        func flushCode() {
            blocks.append(.code(language: codeLanguage, text: codeLines.joined(separator: "\n")))
            codeLines.removeAll()
            codeLanguage = nil
        }

        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if isInsideFence {
                    flushCode()
                    isInsideFence = false
                } else {
                    flushMarkdown()
                    isInsideFence = true
                    let marker = line.trimmingCharacters(in: .whitespaces)
                    let language = String(marker.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = language.isEmpty ? nil : language
                }
            } else if isInsideFence {
                codeLines.append(line)
            } else {
                markdownLines.append(line)
            }
        }

        if isInsideFence {
            markdownLines.append("```" + (codeLanguage.map { " \($0)" } ?? ""))
            markdownLines.append(contentsOf: codeLines)
        }
        flushMarkdown()
        return blocks
    }
}

// 既存の macOS 側参照を壊さないための薄い型名アダプタ。実装本体は ChatRenderKit にある。
typealias DiffLineKind = ChatDiffLineKind
typealias ClassifiedDiffLine = ChatDiffLine
typealias DiffLineClassifier = ChatDiffClassifier
