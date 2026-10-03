import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// 再解析で構造が変わらないように、文書全体で解決済みのノードを描画用に出力する。
/// cmark の commonmark 出力が挿入するコメント・字下げコード・空白の変更を避ける。
enum MarkdownBlockContent {
    private typealias Node = UnsafeMutablePointer<cmark_node>

    static func render(_ node: UnsafeMutablePointer<cmark_node>) -> String {
        block(node) + "\n"
    }

    private static func children(_ node: Node) -> [Node] {
        var result: [Node] = []
        var child = cmark_node_first_child(node)
        while let current = child {
            result.append(current)
            child = cmark_node_next(current)
        }
        return result
    }

    private static func literal(_ node: Node) -> String {
        cmark_node_get_literal(node).map { String(cString: $0) } ?? ""
    }

    private static func type(_ node: Node) -> String { String(cString: cmark_node_get_type_string(node)) }

    private static func block(_ node: Node) -> String {
        let children = children(node)
        switch type(node) {
        case "paragraph": return inlines(node)
        case "heading":
            let level = Int(cmark_node_get_heading_level(node))
            let content = inlines(node)
            if level <= 2, content.contains("\n") {
                return content + "\n" + (level == 1 ? "===" : "---")
            }
            return String(repeating: "#", count: level) + " " + content
        case "block_quote":
            return children.map(block).joined(separator: "\n\n")
                .components(separatedBy: "\n").map { "> " + $0 }.joined(separator: "\n")
        case "list":
            let ordered = cmark_node_get_list_type(node) == CMARK_ORDERED_LIST
            let start = Int(cmark_node_get_list_start(node))
            let delimiter = cmark_node_get_list_delim(node) == CMARK_PAREN_DELIM ? ")" : "."
            let bullet = UnicodeScalar(UInt8(node.pointee.as.list.bullet_char))
            let tight = cmark_node_get_list_tight(node) != 0
            return children.map { item in
                let marker = ordered ? "\(start)\(delimiter) " : "\(Character(bullet)) "
                var content = self.children(item).map(block).joined(separator: tight ? "\n" : "\n\n")
                if type(item) == "tasklist" {
                    content = (cmark_gfm_extensions_get_tasklist_item_checked(item) ? "[x] " : "[ ] ") + content
                }
                let lines = content.components(separatedBy: "\n")
                return marker + (lines.first ?? "") + lines.dropFirst().map {
                    "\n" + String(repeating: " ", count: marker.utf8.count) + $0
                }.joined()
            }.joined(separator: tight ? "\n" : "\n\n")
        case "code_block":
            let info = cmark_node_get_fence_info(node).map { String(cString: $0) } ?? ""
            let content = literal(node)
            let character: Character = info.contains("`") ? "~" : "`"
            let fence = String(repeating: String(character), count: max(3, longestRun(character, in: content) + 1))
            return fence + escapedFenceInfo(info) + "\n" + content
                + (content.isEmpty || content.hasSuffix("\n") ? "" : "\n") + fence
        case "html_block":
            let content = literal(node)
            return content.hasSuffix("\n") ? String(content.dropLast()) : content
        case "thematic_break": return "___"
        case "table":
            let count = Int(cmark_gfm_extensions_get_table_columns(node))
            let alignments = cmark_gfm_extensions_get_table_alignments(node)
            let rows = children.map { row in
                "| " + self.children(row).map { inlines($0).replacingOccurrences(of: "|", with: "\\|") }
                    .joined(separator: " | ") + " |"
            }
            let separator = "| " + (0..<count).map { column in
                switch alignments?[column] {
                case 108: return ":---"
                case 99: return ":---:"
                case 114: return "---:"
                default: return "---"
                }
            }.joined(separator: " | ") + " |"
            return ([rows.first ?? "", separator] + rows.dropFirst()).joined(separator: "\n")
        default: return ""
        }
    }

    private static func inlines(_ node: Node, parentMarker: String? = nil,
                                encodeFirst: Bool = false, encodeLast: Bool = false) -> String {
        var result = ""
        var previousMarker: String?
        let children = children(node)
        func isEmphasis(_ index: Int) -> Bool {
            index >= 0 && index < children.count && ["emph", "strong"].contains(type(children[index]))
        }
        func isBreak(_ index: Int) -> Bool {
            index >= 0 && index < children.count && ["softbreak", "linebreak"].contains(type(children[index]))
        }
        func isStrikeBesideEmphasis(_ index: Int, direction: Int) -> Bool {
            index >= 0 && index < children.count && type(children[index]) == "strikethrough"
                && isEmphasis(index + direction)
        }
        for (index, child) in children.enumerated() {
            let kind = type(child)
            if kind == "emph" || kind == "strong" {
                let adjacentMarker = (index == 0 || index == children.count - 1) ? parentMarker : nil
                let character = (adjacentMarker ?? previousMarker)?.contains("*") == true ? "_" : "*"
                let marker = String(repeating: character, count: kind == "strong" ? 2 : 1)
                result += inline(child, marker: marker)
                previousMarker = marker
            } else {
                // 前後の文字が強調の区切りを妨げないようにし、隣接する空白だけを残す。
                let nextIsEmphasis = isEmphasis(index + 1)
                if kind == "text" {
                    var scalars = Array(literal(child).unicodeScalars)
                    var head = "", tail = ""
                    if previousMarker != nil || (encodeFirst && index == 0)
                        || isStrikeBesideEmphasis(index - 1, direction: -1), let first = scalars.first {
                        let edge = scalars.count == 1 && (index == children.count - 1 || isBreak(index + 1))
                        head = previousMarker != nil && parentMarker != nil && first == " " && !edge
                            ? " " : "&#\(first.value);"
                        scalars.removeFirst()
                    }
                    if nextIsEmphasis || (encodeLast && index == children.count - 1)
                        || isStrikeBesideEmphasis(index + 1, direction: 1), let last = scalars.last {
                        let edge = scalars.count == 1 && head.isEmpty && (index == 0 || isBreak(index - 1))
                        tail = nextIsEmphasis && parentMarker != nil && last == " " && !edge
                            ? " " : "&#\(last.value);"
                        scalars.removeLast()
                    }
                    var text = String.UnicodeScalarView()
                    text.append(contentsOf: scalars)
                    result += head + escapedText(String(text)) + tail
                } else if kind == "strikethrough" {
                    // cmark が ~ を読み飛ばしても、強調の隣が語中にならないようにする。
                    result += "~~" + inlines(child, encodeFirst: isEmphasis(index - 1),
                                              encodeLast: nextIsEmphasis) + "~~"
                } else { result += inline(child) }
                previousMarker = nil
            }
        }
        return result
    }

    private static func inline(_ node: Node, marker: String? = nil) -> String {
        switch type(node) {
        case "text": return escapedText(literal(node))
        case "softbreak": return "\n"
        case "linebreak": return "\\\n"
        case "code":
            let content = literal(node)
            let fence = String(repeating: "`", count: longestRun("`", in: content) + 1)
            let allSpaces = !content.isEmpty && content.allSatisfy { $0 == " " }
            let padding = !allSpaces && (content.hasPrefix("`") || content.hasSuffix("`")
                || (content.hasPrefix(" ") && content.hasSuffix(" "))) ? " " : ""
            return fence + padding + content + padding + fence
        case "emph", "strong":
            let delimiter = marker ?? (type(node) == "emph" ? "*" : "**")
            return delimiter + inlines(node, parentMarker: delimiter) + delimiter
        case "strikethrough": return "~~" + inlines(node) + "~~"
        case "link", "image":
            let destination = cmark_node_get_url(node).map { String(cString: $0) } ?? ""
            let escaped = escapedDestination(destination)
            let target = destination.isEmpty || destination.contains(where: { $0.isWhitespace || "()<>\\".contains($0) })
                ? "<" + escaped + ">" : escaped
            return (type(node) == "image" ? "!" : "") + "[" + inlines(node) + "](" + target + ")"
        case "html_inline": return literal(node)
        default: return ""
        }
    }

    /// 記号と行頭の空白を文字参照にし、段落が表・リスト・コードへ化けるのを防ぐ。
    private static func escapedText(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            if scalar.value < 128, !CharacterSet.alphanumerics.contains(scalar) {
                return "&#\(scalar.value);"
            }
            return String(scalar)
        }.joined()
    }

    private static func escapedDestination(_ text: String) -> String {
        text.unicodeScalars.map { scalar in
            [9, 10, 13, 32, 38, 60, 62, 92, 124].contains(scalar.value) ? "&#\(scalar.value);" : String(scalar)
        }.joined()
    }

    /// フェンス情報は再解析で実体参照・バックスラッシュをもう一度解かせない。
    private static func escapedFenceInfo(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\\", with: "\\\\")
    }

    private static func longestRun(_ character: Character, in text: String) -> Int {
        var longest = 0
        var current = 0
        for value in text {
            current = value == character ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }
}
