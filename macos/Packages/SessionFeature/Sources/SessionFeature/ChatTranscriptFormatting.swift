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
    let oldLineNumber: Int?
    let newLineNumber: Int?
}

enum DiffLineClassifier {
    static func classify(_ diff: String) -> [ClassifiedDiffLine] {
        var oldLineNumber: Int?
        var newLineNumber: Int?

        return diff.components(separatedBy: .newlines).enumerated().map { index, line in
            let lineKind = kind(for: line)
            if lineKind == .hunk {
                if let hunk = hunkStartNumbers(in: line) {
                    oldLineNumber = hunk.old
                    newLineNumber = hunk.new
                } else {
                    oldLineNumber = nil
                    newLineNumber = nil
                }
            }

            let result = ClassifiedDiffLine(
                id: index,
                text: line,
                kind: lineKind,
                oldLineNumber: lineKind == .deletion ? oldLineNumber : nil,
                newLineNumber: lineKind == .addition || (lineKind == .context && line != "\\ No newline at end of file") ? newLineNumber : nil
            )

            guard result.isDisplayable else { return result }

            switch lineKind {
            case .deletion:
                advanceLineNumber(.old, oldLineNumber: &oldLineNumber, newLineNumber: &newLineNumber)
            case .addition:
                advanceLineNumber(.new, oldLineNumber: &oldLineNumber, newLineNumber: &newLineNumber)
            case .context:
                advanceLineNumber(.old, oldLineNumber: &oldLineNumber, newLineNumber: &newLineNumber)
                advanceLineNumber(.new, oldLineNumber: &oldLineNumber, newLineNumber: &newLineNumber)
            case .fileHeader, .hunk:
                break
            }
            return result
        }
    }

    /// 加算不能な採番は推測せず、以降の old/new 両方の採番を停止する。
    private enum LineNumberSide {
        case old
        case new
    }

    private static func advanceLineNumber(
        _ side: LineNumberSide,
        oldLineNumber: inout Int?,
        newLineNumber: inout Int?
    ) {
        let currentLineNumber = switch side {
        case .old: oldLineNumber
        case .new: newLineNumber
        }
        guard let currentLineNumber else { return }
        let (next, overflow) = currentLineNumber.addingReportingOverflow(1)
        if overflow {
            oldLineNumber = nil
            newLineNumber = nil
        } else {
            switch side {
            case .old: oldLineNumber = next
            case .new: newLineNumber = next
            }
        }
    }

    /// file header と末尾改行注記を除いた、コードビューで描く行。
    static func displayLines(_ diff: String) -> [ClassifiedDiffLine] {
        classify(diff).filter(\.isDisplayable)
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

    private static func hunkStartNumbers(in line: String) -> (old: Int, new: Int)? {
        let parts = line.split(separator: " ")
        guard parts.count >= 3,
              let old = hunkStart(in: parts[1], marker: "-"),
              let new = hunkStart(in: parts[2], marker: "+") else {
            return nil
        }
        return (old, new)
    }

    private static func hunkStart(in part: Substring, marker: Character) -> Int? {
        guard part.first == marker else { return nil }
        let digits = part.dropFirst().prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}

extension ClassifiedDiffLine {
    var isDisplayable: Bool {
        kind != .fileHeader && text != "\\ No newline at end of file"
    }

    var displayLineNumber: Int? {
        guard isDisplayable else { return nil }
        return switch kind {
        case .deletion: oldLineNumber
        case .addition, .context: newLineNumber
        case .fileHeader, .hunk: nil
        }
    }
}

enum DiffPathDisplay {
    static func shorten(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else { return path }
        return components.suffix(2).joined(separator: "/")
    }
}
