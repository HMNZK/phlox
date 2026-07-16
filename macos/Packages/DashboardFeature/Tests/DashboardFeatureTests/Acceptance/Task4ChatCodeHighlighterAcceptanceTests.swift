import Testing
import SwiftUI
@testable import DashboardFeature
@testable import SessionFeature

/// task-4 受け入れテスト — PM 著・不変（実装役は編集禁止）。
///
/// 駆動源#2（HighlightSwift `CodeText` の非同期サイズ変化による LazyVStack 自励発振）根治の契約:
/// markdown コードブロックのハイライトは同期・決定論的・文字保存の純関数
/// `ChatCodeHighlighter.highlight(_:)` に一本化する。
/// CPU 収束そのもの（runtime 挙動）は swift test では捕捉できないため、実機統合検証（PM）が別途担う。
@Suite("task-4 ChatCodeHighlighter acceptance")
struct Task4ChatCodeHighlighterAcceptanceTests {

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
    func appliesForegroundColorToKeyword() {
        // キーワードへ前景色が付く（ハイライトとして機能している）。
        let out = ChatCodeHighlighter.highlight("let value = 1")
        let hasColoredRun = out.runs.contains { $0.foregroundColor != nil }
        #expect(hasColoredRun)
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
