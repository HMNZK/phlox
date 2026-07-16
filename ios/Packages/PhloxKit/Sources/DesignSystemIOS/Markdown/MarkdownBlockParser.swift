import Foundation

/// マークダウン本文をブロック列（段落 / フェンス付きコードブロック）へ分割する純関数。
/// DSMarkdownText（task-5）の描画単位。契約は Tests/DesignSystemIOSTests/MarkdownRenderingAcceptanceTests.swift。
public enum MarkdownBlock: Equatable, Sendable {
    /// コードブロック以外の本文（マークダウンとして描画する）。
    case paragraph(String)
    /// ``` フェンスのコードブロック。language はフェンス直後の識別子（無ければ nil）。
    case code(language: String?, content: String)
}

public enum MarkdownBlockParser {
    /// 本文をブロック列に分割する。フェンス（```）が閉じられていない場合は末尾までをコードとして扱う。
    public static func blocks(from text: String) -> [MarkdownBlock] {
        guard !text.isEmpty else { return [] }

        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [MarkdownBlock] = []
        var paragraphLines: [String] = []
        var codeLines: [String] = []
        var language: String?
        var isInsideFence = false

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

        func appendCode() {
            blocks.append(.code(language: language, content: codeLines.joined(separator: "\n")))
            codeLines.removeAll(keepingCapacity: true)
            language = nil
        }

        for line in lines {
            if isInsideFence {
                if line.hasPrefix("```") {
                    appendCode()
                    isInsideFence = false
                } else {
                    codeLines.append(line)
                }
            } else if line.hasPrefix("```") {
                appendParagraph()
                language = fenceLanguage(from: line)
                isInsideFence = true
            } else {
                paragraphLines.append(line)
            }
        }

        if isInsideFence {
            appendCode()
        } else {
            appendParagraph()
        }
        return blocks
    }
}
