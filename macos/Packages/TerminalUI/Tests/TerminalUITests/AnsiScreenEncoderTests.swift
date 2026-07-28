import AppKit
import Foundation
import SwiftTerm
import Testing
@testable import TerminalUI

/// 画面を持たない端末。上限の検証だけが目的なので、通知は全部既定実装に任せる。
private final class SilentTerminalDelegate: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
}

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

    // MARK: - scrollback（受け手が自分で遡れること）

    @Test("画面から流れ去った行も書き出す（受け手が自分でスクロールして読めること）")
    func includesRowsThatScrolledOffTheViewport() {
        let coordinator = TerminalCoordinator()
        let rows = coordinator.currentRows
        // viewport の3倍を流し込み、先頭が確実に画面外へ出た状態を作る。
        for index in 1...(Int(rows) * 3) {
            coordinator.feed(Data("line-\(index)\r\n".utf8))
        }

        let ansi = stripSGR(coordinator.ansiScreenText())

        #expect(ansi.contains("line-1"), "最初の行まで遡れること。行数=\(ansi.split(separator: "\n").count)")
        #expect(ansi.contains("line-\(Int(rows) * 3)"), "最新の行も含むこと")
        #expect(!coordinator.visibleText().contains("line-1"), "前提: viewport には残っていないこと")
    }

    @Test("書き出す行数には上限があり、超えた分は古い側から落とす")
    func capsTheNumberOfRows() {
        let terminal = Terminal(delegate: SilentTerminalDelegate())
        for index in 1...50 {
            terminal.feed(text: "line-\(index)\r\n")
        }

        let ansi = stripSGR(AnsiScreenEncoder.encode(terminal, maxRows: 10))
        let lines = ansi.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.count <= 10, "上限を超えないこと。行数=\(lines.count)")
        #expect(ansi.contains("line-50"), "最新側を残すこと")
        #expect(!ansi.contains("line-1\r"), "古い側を落とすこと")
        #expect(!lines.contains("line-1"), "古い側を落とすこと。lines=\(lines.prefix(3))")
    }

    private func stripSGR(_ text: String) -> String {
        text.replacing(/\u{1b}\[[0-9;]*m/, with: "")
    }

    private func debug(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1b}", with: "<ESC>")
    }
}
