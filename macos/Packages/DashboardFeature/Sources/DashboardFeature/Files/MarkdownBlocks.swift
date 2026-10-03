import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// 原文の編集区間と、文書全体の文脈で解決済みの描画内容。
public struct MarkdownBlock: Identifiable, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case markdown
        case heading(level: Int)
        case frontMatter
        case raw
        case empty
    }

    public var id: Int { range.lowerBound }
    /// 原文の UTF-8 バイト位置。改行と参照定義も区間に含める。
    public let range: Range<Int>
    public let original: String
    public let renderedMarkdown: String
    public let kind: Kind

}

public enum MarkdownBlocks {
    struct Analysis: Sendable {
        let blocks: [MarkdownBlock]
        let isSafe: Bool
    }

    public static func parse(_ source: String) -> [MarkdownBlock] {
        analyze(source).blocks
    }

    static func analyze(_ source: String) -> Analysis {
        let bytes = Array(source.utf8)
        guard !bytes.isEmpty else {
            return Analysis(blocks: [MarkdownBlock(range: 0..<0, original: "", renderedMarkdown: "", kind: .empty)], isSafe: true)
        }
        let lines = lineStarts(bytes)
        var bodyOffset = 0
        var blocks: [MarkdownBlock] = []

        // front matter は Markdown の水平線・見出しとして解釈しない。
        if lineContent(bytes, starts: lines, index: 0) == "---",
           let end = lines.indices.dropFirst().first(where: { lineContent(bytes, starts: lines, index: $0) == "---" }) {
            bodyOffset = end + 1 < lines.count ? lines[end + 1] : bytes.count
            blocks.append(block(bytes, range: 0..<bodyOffset, markdown: "", kind: .frontMatter))
        }
        guard bodyOffset < bytes.count else { return Analysis(blocks: blocks, isSafe: coversSource(blocks, source: source)) }

        let body = String(decoding: bytes[bodyOffset...], as: UTF8.self)
        let bodyLines = lineStarts(Array(body.utf8))
        cmark_gfm_core_extensions_ensure_registered()
        guard let parser = cmark_parser_new(CMARK_OPT_DEFAULT) else {
            return fallback(bytes)
        }
        defer { cmark_parser_free(parser) }
        for name in ["autolink", "strikethrough", "tagfilter", "tasklist", "table"] {
            if let syntax = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, syntax)
            }
        }
        body.withCString { cmark_parser_feed(parser, $0, body.utf8.count) }
        guard let document = cmark_parser_finish(parser) else {
            return fallback(bytes)
        }
        defer { cmark_node_free(document) }

        var nodes: [UnsafeMutablePointer<cmark_node>] = []
        var next = cmark_node_first_child(document)
        while let node = next {
            nodes.append(node)
            next = cmark_node_next(node)
        }
        guard !nodes.isEmpty else {
            blocks.append(block(bytes, range: bodyOffset..<bytes.count, markdown: "", kind: .raw))
            return Analysis(blocks: blocks, isSafe: coversSource(blocks, source: source))
        }
        var groups: [(start: Int, markdown: String, kind: MarkdownBlock.Kind)] = []
        var previousLine = 0
        var leadingMarkdown = ""
        for node in nodes {
            let line = Int(cmark_node_get_start_line(node))
            guard line >= 0, line <= bodyLines.count else { return fallback(bytes) }
            // 隣のリストとの分離用コメントを生成させない。参照は既に文書全体で解決済み。
            cmark_node_unlink(node)
            defer { cmark_node_free(node) }
            let markdown = MarkdownBlockContent.render(node)
            // 表の前の段落など、位置を失ったノードは隣接ブロックへ統合する。
            if line == 0 || line <= previousLine {
                leadingMarkdown += markdown
                previousLine = max(previousLine, line)
                continue
            }
            let start = groups.isEmpty ? bodyOffset : bodyOffset + bodyLines[line - 1]
            guard start < bytes.count, groups.last.map({ start > $0.start }) ?? true else { return fallback(bytes) }
            let kind: MarkdownBlock.Kind = cmark_node_get_type(node) == CMARK_NODE_HEADING
                ? .heading(level: Int(cmark_node_get_heading_level(node))) : .markdown
            groups.append((start, leadingMarkdown + markdown, leadingMarkdown.isEmpty ? kind : .markdown))
            leadingMarkdown = ""
            previousLine = line
        }
        if groups.isEmpty { return fallback(bytes) }
        for index in groups.indices {
            let group = groups[index]
            let end = index + 1 < groups.count ? groups[index + 1].start : bytes.count
            guard group.start >= 0, group.start < end, end <= bytes.count else { return fallback(bytes) }
            blocks.append(block(bytes, range: group.start..<end, markdown: group.markdown, kind: group.kind))
        }
        guard coversSource(blocks, source: source) else { return fallback(bytes) }
        return Analysis(blocks: blocks, isSafe: true)
    }

    static func coversSource(_ blocks: [MarkdownBlock], source: String) -> Bool {
        let bytes = Array(source.utf8)
        var offset = 0
        guard !blocks.isEmpty else { return false }
        for block in blocks {
            guard block.range.lowerBound == offset, block.range.upperBound <= bytes.count,
                  bytes.isEmpty ? blocks.count == 1 && block.range.isEmpty : !block.range.isEmpty,
                  block.original.utf8.elementsEqual(bytes[block.range]) else { return false }
            offset = block.range.upperBound
        }
        return offset == bytes.count
    }

    private static func fallback(_ bytes: [UInt8]) -> Analysis {
        Analysis(blocks: [block(bytes, range: 0..<bytes.count, markdown: "", kind: .raw)], isSafe: false)
    }

    private static func block(_ bytes: [UInt8], range: Range<Int>, markdown: String, kind: MarkdownBlock.Kind) -> MarkdownBlock {
        MarkdownBlock(range: range, original: String(decoding: bytes[range], as: UTF8.self), renderedMarkdown: markdown,
                      kind: kind)
    }

    /// cmark と同じく LF、CRLF、単独 CR を改行として数える。
    private static func lineStarts(_ bytes: [UInt8]) -> [Int] {
        var starts = [0]
        var index = 0
        while index < bytes.count {
            if bytes[index] == 13 {
                index += 1
                if index < bytes.count, bytes[index] == 10 { index += 1 }
                if index < bytes.count { starts.append(index) }
            } else if bytes[index] == 10 {
                index += 1
                if index < bytes.count { starts.append(index) }
            } else {
                index += 1
            }
        }
        return starts
    }

    private static func lineContent(_ bytes: [UInt8], starts: [Int], index: Int) -> String {
        let end = index + 1 < starts.count ? starts[index + 1] : bytes.count
        var contentEnd = end
        while contentEnd > starts[index], [10, 13].contains(bytes[contentEnd - 1]) { contentEnd -= 1 }
        return String(decoding: bytes[starts[index]..<contentEnd], as: UTF8.self)
    }
}
