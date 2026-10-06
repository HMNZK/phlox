import Testing
import SwiftUI
@testable import DashboardFeature
@testable import SessionFeature

/// markdown コードブロックのハイライトは、同期・決定論的・文字保存の純関数
/// `ChatCodeHighlighter.highlight(_:)` に一本化されている
/// （非同期ハイライトの CodeText が LazyVStack を自励発振させた不具合の再発防止）。
@Suite("ChatCodeHighlighter")
struct ChatCodeHighlighterTests {

    @Test
    func commentLineHasColoredRun() {
        let out = ChatCodeHighlighter.highlight("// comment")
        let hasColoredRun = out.runs.contains { $0.foregroundColor != nil }
        #expect(hasColoredRun)
    }

    @Test
    func numberLiteralHasColoredRun() {
        let out = ChatCodeHighlighter.highlight("let n = 42")
        let coloredRunCount = out.runs.filter { $0.foregroundColor != nil }.count
        #expect(coloredRunCount >= 2)
    }

    @Test
    func preservesCharactersExactly() {
        // 文字の完全保存（色属性のみ付与し、テキスト自体を変えない）。
        let code = "let x = \"あいう\" // コメント\nfunc f() { return }"
        let out = ChatCodeHighlighter.highlight(code)
        #expect(String(out.characters) == code)
    }

    @Test
    func deterministicAcrossRepeatedCalls() {
        // 決定論: 同一入力 → 同一出力（非同期・環境依存のハイライトを禁止する契約の核）。
        let code = "struct S { var n = 42 }"
        let first = ChatCodeHighlighter.highlight(code)
        let second = ChatCodeHighlighter.highlight(code)
        #expect(first == second)
    }

    @Test
    func emptyInputYieldsEmptyOutput() {
        // 境界: 空入力で安全（クラッシュ・パディング挿入なし）。
        let out = ChatCodeHighlighter.highlight("")
        #expect(String(out.characters).isEmpty)
    }

    @Test
    func stringLiteralWithEscapesRoundTrips() {
        // 境界: エスケープ付き文字列リテラルでも文字保存が崩れない。
        let code = #"print("a\"b\\c")"#
        let out = ChatCodeHighlighter.highlight(code)
        #expect(String(out.characters) == code)
    }
}
