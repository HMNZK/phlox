import Foundation
import Testing
@testable import ChatRenderKit

@Suite("埋め込み字句の範囲と原文")
struct SyntaxEmbeddedSpanTests {
    @Test(arguments: [
        ("swift", "let title = \"😀é日本語\"\nlet block = \"\"\"\n複数行\n\"\"\"\n"),
        ("json", "{\"名前\":\"😀é\",\"count\":42,\"enabled\":true}\n"),
        ("html", "<div title=\"😀日本語\"><script>const s = 'é';</script><style>.a { color: #333; }</style></div>\n"),
        ("yaml", "# 日本語\nname: '😀é'\nmessage: |\n  複数行\n  本文\n")
    ])
    func fencedTokensMatchStandaloneLanguage(language: String, body: String) {
        let prefix = "```\(language)\n"
        let source = prefix + body + "```\n"
        let tokens = ChatCodeTokenizer.tokens(for: source, path: "README.md")
        #expect(tokens.map(\.text).joined().utf8.elementsEqual(source.utf8))
        let target = NSRange(location: prefix.utf8.count, length: body.utf8.count)
        var offset = 0
        var embedded: [ChatCodeToken] = []
        for token in tokens {
            let bytes = Array(token.text.utf8)
            let overlap = NSIntersectionRange(NSRange(location: offset, length: bytes.count), target)
            if overlap.length > 0 {
                let start = overlap.location - offset
                let text = String(decoding: bytes[start..<(start + overlap.length)], as: UTF8.self)
                embedded.append(ChatCodeToken(text: text, kind: token.kind))
            }
            offset += bytes.count
        }
        #expect(embedded == ChatCodeTokenizer.tokens(for: body, syntax: ChatCodeLanguage.named(language)!))
    }
}
