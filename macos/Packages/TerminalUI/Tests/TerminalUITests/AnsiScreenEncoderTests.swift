import AppKit
import Foundation
import Testing
@testable import TerminalUI

@MainActor
struct AnsiScreenEncoderTests {

    @Test("色付きの出力は色を保ったまま書き出される")
    func keepsForegroundColor() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("\u{1b}[31mred\u{1b}[0m plain".utf8))

        let ansi = coordinator.ansiScreenText()

        #expect(ansi.contains("\u{1b}[0;31mred"), "赤の SGR が残ること。ansi=\(debug(ansi))")
        #expect(ansi.contains("plain"))
    }

    @Test("プレーンテキスト化では落ちる装飾が残る")
    func keepsBoldWherePlainTextLosesIt() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("\u{1b}[1mbold\u{1b}[0m".utf8))

        #expect(coordinator.visibleText() == "bold", "前提: プレーンテキストでは装飾が落ちる")
        #expect(coordinator.ansiScreenText().contains("\u{1b}[0;1mbold"))
    }

    @Test("同じ属性が続く間は SGR を繰り返さない")
    func emitsOneEscapePerAttributeRun() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("\u{1b}[32mgreen\u{1b}[0m".utf8))

        let ansi = coordinator.ansiScreenText()
        let greenCount = ansi.components(separatedBy: "\u{1b}[0;32m").count - 1

        #expect(greenCount == 1, "5文字それぞれに SGR を出さないこと。ansi=\(debug(ansi))")
    }

    @Test("装飾のない出力はプレーンテキストと同じ本文を持つ")
    func plainOutputCarriesSameCharacters() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("line one\r\nline two\r\n".utf8))

        let stripped = stripSGR(coordinator.ansiScreenText())

        #expect(stripped == coordinator.visibleText())
    }

    @Test("行末の既定属性の空白は落とすが、背景色の付いた空白は残す")
    func keepsColoredTrailingSpaces() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("\u{1b}[44m  \u{1b}[0m".utf8))

        let ansi = coordinator.ansiScreenText()

        #expect(ansi.contains("\u{1b}[0;44m  "), "背景色付きの空白は見た目に出るので残すこと。ansi=\(debug(ansi))")
    }

    @Test("全角文字でも桁がずれない")
    func doesNotDuplicateWideCharacterCells() {
        let coordinator = TerminalCoordinator()
        coordinator.feed(Data("あい|".utf8))

        #expect(stripSGR(coordinator.ansiScreenText()) == "あい|")
    }

    @Test("何も出力していない端末は空文字を返す")
    func emptyTerminalEncodesToEmptyString() {
        #expect(TerminalCoordinator().ansiScreenText() == "")
    }

    private func stripSGR(_ text: String) -> String {
        text.replacing(/\u{1b}\[[0-9;]*m/, with: "")
    }

    private func debug(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1b}", with: "<ESC>")
    }
}
