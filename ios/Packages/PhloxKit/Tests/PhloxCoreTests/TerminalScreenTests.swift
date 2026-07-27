import Foundation
import Testing
@testable import PhloxCore

@Suite("Mac から届く端末画面")
struct TerminalScreenTests {

    @Test("桁数が付いているものだけ端末として描き直せる")
    func onlyScreensWithColumnsCanBeRedrawn() {
        #expect(TerminalScreen(text: "x", cols: 120).isANSI)
        #expect(!TerminalScreen(text: "x", cols: nil).isANSI)
    }

    @Test("色のエスケープを外した本文が読める")
    func plainTextDropsColorEscapes() {
        let screen = TerminalScreen(text: "\u{1B}[0;31mred\u{1B}[0m plain", cols: 80)

        #expect(screen.plainText == "red plain")
    }

    @Test("色以外のエスケープも本文へ漏らさない")
    func plainTextDropsNonColorEscapes() {
        let screen = TerminalScreen(text: "a\u{1B}[2Kb\u{1B}[10;5Hc", cols: 80)

        #expect(screen.plainText == "abc")
    }

    @Test("エスケープが無い本文はそのまま返す")
    func plainTextKeepsPlainInputUnchanged() {
        #expect(TerminalScreen(text: "line one\nline two", cols: nil).plainText == "line one\nline two")
    }

    @Test("行末で途切れたエスケープを本文へ漏らさない")
    func plainTextHandlesTruncatedEscape() {
        #expect(TerminalScreen(text: "ok\u{1B}[0;3", cols: 80).plainText == "ok")
    }

    @Test("改行はそのまま残る（行数の判定に使うため）")
    func plainTextKeepsNewlines() {
        let screen = TerminalScreen(text: "\u{1B}[0;31ma\u{1B}[0m\n\u{1B}[0;32mb\u{1B}[0m", cols: 80)

        #expect(screen.plainText == "a\nb")
    }
}
