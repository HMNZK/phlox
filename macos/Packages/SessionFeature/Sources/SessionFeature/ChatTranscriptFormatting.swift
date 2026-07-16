import Foundation

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

enum DiffLineKind: Equatable, Sendable {
    case fileHeader
    case hunk
    case addition
    case deletion
    case context
}

struct ClassifiedDiffLine: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let kind: DiffLineKind
}

enum DiffLineClassifier {
    static func classify(_ diff: String) -> [ClassifiedDiffLine] {
        diff.components(separatedBy: .newlines).enumerated().map { index, line in
            ClassifiedDiffLine(id: index, text: line, kind: kind(for: line))
        }
    }

    private static func kind(for line: String) -> DiffLineKind {
        if line.hasPrefix("@@") {
            return .hunk
        }
        if line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff --git") || line.hasPrefix("index ") {
            return .fileHeader
        }
        if line.hasPrefix("+") {
            return .addition
        }
        if line.hasPrefix("-") {
            return .deletion
        }
        return .context
    }
}
