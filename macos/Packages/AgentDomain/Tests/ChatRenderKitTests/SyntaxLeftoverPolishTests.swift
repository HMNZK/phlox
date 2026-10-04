import Foundation
import Testing
@testable import ChatRenderKit

@Suite("残差: CSSのURL引数")
struct SyntaxLeftoverPolishTests {
    @Test(arguments: ["a.css", "a.scss", "a.less"])
    func urlArgumentsAreEntirelyStrings(path: String) {
        for argument in ["https://example.com/image.png", "'https://example.com/a)b.png'",
                         "\"data:image/svg+xml;base64,123==\"", "../images/a\\)b.png", "https://閉じ忘れ/a"] {
            let closed = !argument.contains("閉じ忘れ")
            let prefix = "a { background: url("
            let code = prefix + argument + (closed ? "); color: red; }" : "")
            let tokens = ChatCodeTokenizer.tokens(for: code, path: path)
            #expect(tokens.map(\.text).joined() == code)
            var offset = 0
            let target = NSRange(location: prefix.utf16.count, length: argument.utf16.count)
            for token in tokens {
                let range = NSRange(location: offset, length: token.text.utf16.count)
                if NSIntersectionRange(range, target).length > 0 {
                    #expect(token.kind == .string, "URL引数を分断しない: \(token.text)")
                }
                offset += range.length
            }
            if closed { #expect(tokens.contains { $0.text == "color" && $0.kind == .property }) }
        }
    }
}
