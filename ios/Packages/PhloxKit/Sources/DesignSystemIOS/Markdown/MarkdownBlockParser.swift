import Foundation

/// マークダウン本文をブロック列（段落 / フェンス付きコードブロック / 表）へ分割する純関数。
/// DSMarkdownText（task-5）の描画単位。契約は Tests/DesignSystemIOSTests/MarkdownRenderingAcceptanceTests.swift
/// および Tests/DesignSystemIOSTests/AcceptanceMarkdownReadabilityTests.swift。
public enum MarkdownBlock: Equatable, Sendable {
    /// コードブロック・表以外の本文（マークダウンとして描画する）。
    case paragraph(String)
    /// ``` フェンスのコードブロック。language はフェンス直後の識別子（無ければ nil）。
    case code(language: String?, content: String)
    /// GFM の表。横スクロールで描画するため段落から切り出す（公開面は PM 凍結・抽出の実装は task-2）。
    case table(String)
}

public enum MarkdownBlockParser {
    /// 本文をブロック列に分割する。フェンス（```）が閉じられていない場合は末尾までをコードとして扱う。
    public static func blocks(from text: String) -> [MarkdownBlock] {
        guard !text.isEmpty else { return [] }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []

        func fenceLanguage(from line: String) -> String? {
            guard line.hasPrefix("```") else { return nil }
            let suffix = line.dropFirst(3)
            return suffix.split(whereSeparator: \Character.isWhitespace).first.map(String.init)
        }

        func appendParagraph() {
            guard !paragraphLines.isEmpty else { return }
            blocks.append(.paragraph(paragraphLines.joined(separator: "\n")))
            paragraphLines.removeAll(keepingCapacity: true)
        }

        func tableCells(in line: String) -> [String]? {
            guard line.contains("|") else { return nil }
            let content = line
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            var cells: [String] = []
            var cell = ""
            var precedingBackslashCount = 0

            for character in content {
                if character == "|", precedingBackslashCount.isMultiple(of: 2) {
                    cells.append(cell.trimmingCharacters(in: .whitespaces))
                    cell = ""
                } else {
                    cell.append(character)
                }

                if character == "\\" {
                    precedingBackslashCount += 1
                } else {
                    precedingBackslashCount = 0
                }
            }
            cells.append(cell.trimmingCharacters(in: .whitespaces))
            return cells
        }

        func isDelimiterRow(_ line: String) -> Bool {
            guard let cells = tableCells(in: line), !cells.isEmpty else { return false }
            return cells.allSatisfy { cell in
                let characters = Array(cell)
                var start = 0
                var end = characters.count

                if characters.first == ":" { start += 1 }
                if characters.last == ":" { end -= 1 }
                guard end - start >= 1 else { return false }
                return characters[start..<end].allSatisfy { $0 == "-" }
            }
        }

        func isTableRow(_ line: String) -> Bool {
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            return leadingSpaces < 4 && line.contains("|")
        }

        func isListItem(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let first = trimmed.first else { return false }
            if "-*+".contains(first) {
                return trimmed.dropFirst().first?.isWhitespace == true
            }
            return trimmed.prefix(while: \.isNumber).isEmpty == false && trimmed.drop(while: \.isNumber).first == "."
        }

        func isIndentedListContinuationTable(at index: Int) -> Bool {
            let line = lines[index]
            guard line.first == " " else { return false }
            return paragraphLines.last.map(isListItem) ?? false
        }

        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                appendParagraph()
                let language = fenceLanguage(from: line)
                index += 1
                var codeLines: [String] = []

                while index < lines.count, !lines[index].hasPrefix("```") {
                    codeLines.append(lines[index])
                    index += 1
                }

                blocks.append(.code(language: language, content: codeLines.joined(separator: "\n")))
                if index < lines.count {
                    index += 1
                }
            } else if index + 2 < lines.count,
                      isTableRow(line),
                      !isIndentedListContinuationTable(at: index),
                      isDelimiterRow(lines[index + 1]),
                      tableCells(in: line)?.count == tableCells(in: lines[index + 1])?.count,
                      isTableRow(lines[index + 2]) {
                appendParagraph()
                let tableStart = index
                index += 3

                while index < lines.count, isTableRow(lines[index]) {
                    index += 1
                }

                blocks.append(.table(lines[tableStart..<index].joined(separator: "\n")))
            } else {
                paragraphLines.append(line)
                index += 1
            }
        }

        appendParagraph()
        return blocks
    }
}
