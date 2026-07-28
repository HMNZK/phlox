import Foundation
import Testing
@testable import TerminalScreenIOS

@Suite("Mac の端末画面（SGR 付きテキスト）を行ごと・装飾ごとの塊へ分解する")
struct AnsiTextParserTests {

    private let palette = TerminalScreenPalette.phloxDefault

    private func lines(_ text: String) -> [AnsiTextParser.Line] {
        AnsiTextParser.lines(of: text, palette: palette)
    }

    private func runs(_ text: String) -> [AnsiRun] {
        lines(text).flatMap { $0 }
    }

    private func plainText(_ text: String) -> String {
        lines(text).map { $0.map(\.text).joined() }.joined(separator: "\n")
    }

    // MARK: - 本文を落とさない（この不変条件が崩れると画面が欠ける）

    @Test("装飾を剥がした本文は1文字も欠けない")
    func keepsEveryVisibleCharacter() {
        let screen = "\u{1B}[0;36mSTATUS.md\u{1B}[0m: 現在の状態\n\u{1B}[0;32m$0.13\u{1B}[0m"

        #expect(plainText(screen) == "STATUS.md: 現在の状態\n$0.13")
    }

    @Test("改行はそのまま残る（行が消えると端末の見た目が崩れる）")
    func keepsLineBreaks() {
        #expect(plainText("\u{1B}[0m1行目\n\n3行目") == "1行目\n\n3行目")
    }

    @Test("40行の画面は40行のまま（行数を落とさない）")
    func keepsEveryRowOfATallScreen() {
        let screen = (1...40).map { "\u{1B}[0;33m行\($0)\u{1B}[0m" }.joined(separator: "\n")

        #expect(lines(screen).count == 40)
    }

    // MARK: - 行分け（1行ずつ遅延描画するための単位）

    @Test("空行は空の塊列になる（1行ぶんの場所を保つ）")
    func blankRowBecomesAnEmptyLine() {
        let result = lines("上\n\n下")

        #expect(result.count == 3)
        #expect(result[1].isEmpty)
    }

    @Test("装飾は改行をまたいで持ち越す（端末の SGR は改行で戻らない）")
    func styleCarriesAcrossLineBreaks() throws {
        let result = lines("\u{1B}[31m赤い1行目\n赤い2行目")

        #expect(result.count == 2)
        #expect(try #require(result[0].first).style.foreground == palette.ansi[1])
        #expect(try #require(result[1].first).style.foreground == palette.ansi[1])
    }

    @Test("1000行の履歴でも行数がそのまま保たれる")
    func keepsEveryRowOfALongScrollback() {
        let screen = (1...1000).map { "line-\($0)" }.joined(separator: "\n")

        let result = lines(screen)

        #expect(result.count == 1000)
        #expect(result.first?.first?.text == "line-1")
        #expect(result.last?.first?.text == "line-1000")
    }

    // MARK: - 色

    @Test("30〜37 はパレットの ANSI 色になる")
    func basicForegroundColorsComeFromThePalette() throws {
        let run = try #require(runs("\u{1B}[36mcyan").first)

        #expect(run.style.foreground == palette.ansi[6])
    }

    @Test("90〜97 は明るい方の 8 色になる")
    func brightForegroundColorsUseTheUpperHalfOfThePalette() throws {
        let run = try #require(runs("\u{1B}[91mbright").first)

        #expect(run.style.foreground == palette.ansi[9])
    }

    @Test("40〜47 は背景色になる")
    func basicBackgroundColorsComeFromThePalette() throws {
        let run = try #require(runs("\u{1B}[44mblock").first)

        #expect(run.style.background == palette.ansi[4])
    }

    @Test("38;5;n の色立方体は xterm と同じ RGB へ解ける")
    func extended256ColorResolvesToTheXtermCube() throws {
        // 208 = 16 + 36*5 + 6*2 + 0 → (255, 135, 0)
        let run = try #require(runs("\u{1B}[38;5;208morange").first)

        #expect(run.style.foreground == TerminalScreenPalette.Channel(255, 135, 0))
    }

    @Test("38;5;n の 0〜15 はパレットを使う（テーマの色に揃える）")
    func extended256ColorBelowSixteenUsesThePalette() throws {
        let run = try #require(runs("\u{1B}[38;5;5mmagenta").first)

        #expect(run.style.foreground == palette.ansi[5])
    }

    @Test("38;5;n の無彩色階段はグレースケールへ解ける")
    func extended256GrayscaleResolvesToGray() throws {
        // 244 = 232 + 12 → 8 + 120 = 128
        let run = try #require(runs("\u{1B}[38;5;244mdim").first)

        #expect(run.style.foreground == TerminalScreenPalette.Channel(128, 128, 128))
    }

    @Test("38;2;r;g;b はその RGB をそのまま使う")
    func trueColorUsesTheGivenChannels() throws {
        let run = try #require(runs("\u{1B}[38;2;12;34;56mtrue").first)

        #expect(run.style.foreground == TerminalScreenPalette.Channel(12, 34, 56))
    }

    @Test("39 / 49 は端末の既定色へ戻す")
    func defaultColorCodesClearTheExplicitColor() throws {
        let run = try #require(runs("\u{1B}[36;44m\u{1B}[39;49mplain").first)

        #expect(run.style.foreground == nil)
        #expect(run.style.background == nil)
    }

    // MARK: - 装飾

    @Test("太字・淡色・斜体・下線・反転・取り消し線を読み取る")
    func readsEveryDecorationFlag() throws {
        let run = try #require(runs("\u{1B}[1;2;3;4;7;9mdecorated").first)

        #expect(run.style.isBold)
        #expect(run.style.isDim)
        #expect(run.style.isItalic)
        #expect(run.style.isUnderlined)
        #expect(run.style.isInverse)
        #expect(run.style.isStruckThrough)
    }

    @Test("22 は太字と淡色の両方を戻す")
    func code22ClearsBothBoldAndDim() throws {
        let run = try #require(runs("\u{1B}[1;2m\u{1B}[22mnormal").first)

        #expect(!run.style.isBold)
        #expect(!run.style.isDim)
    }

    @Test("0 はすべての装飾と色を初期状態へ戻す")
    func resetClearsEverything() throws {
        let run = try #require(runs("\u{1B}[1;4;31;44m\u{1B}[0mplain").first)

        #expect(run.style == AnsiStyle())
    }

    @Test("パラメータ無しの ESC[m はリセットとして扱う")
    func emptyParameterListMeansReset() throws {
        let run = try #require(runs("\u{1B}[31m\u{1B}[mplain").first)

        #expect(run.style.foreground == nil)
    }

    // MARK: - SGR 以外

    @Test("カーソル表示切替のような SGR 以外の CSI は本文にも装飾にも出さない")
    func ignoresNonSgrControlSequences() throws {
        let run = try #require(runs("\u{1B}[?25l\u{1B}[2J\u{1B}[31mred").first)

        #expect(run.text == "red")
        #expect(run.style.foreground == palette.ansi[1])
    }

    @Test("私的パラメータ（?付き）を色として解釈しない")
    func doesNotMistakePrivateParametersForColors() throws {
        let run = try #require(runs("\u{1B}[?7hplain").first)

        #expect(run.style == AnsiStyle())
        #expect(run.text == "plain")
    }

    @Test("未知の SGR は無視し、生の数字を本文へ漏らさない")
    func unknownSgrCodesDoNotLeakIntoTheText() {
        #expect(plainText("\u{1B}[53mover") == "over")
    }

    @Test("エスケープを含まない本文は1つの塊のまま返す")
    func plainScreenBecomesASingleRun() throws {
        let result = runs("no escapes here")

        #expect(result.count == 1)
        #expect(result[0].text == "no escapes here")
        #expect(result[0].style == AnsiStyle())
    }

    @Test("空の本文では行も塊も作らない")
    func emptyScreenProducesNoLines() {
        #expect(lines("").isEmpty)
    }
}
