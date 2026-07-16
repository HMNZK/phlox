import Testing
import Foundation
import SwiftTerm
@testable import TerminalUI

/// EL (Erase in Line) による isWrapped クリア挙動の特性化テスト。
///
/// cmdEraseInLine が isWrapped をいつクリアし、いつ保持するかを固定する。
/// reflow はカーソルを含む折返しグループを結合しないため、結合判定前にカーソルを対象行の外へ移す。
@MainActor
struct TerminalEraseLineWrapFlagTests {

    private static func moveCursorAwayFromReflowGroup(_ coordinator: TerminalCoordinator) {
        coordinator.feed(Data("\r\n\r\nprompt>".utf8))
    }

    /// EL2 (CSI 2K) で行全体を消して書き直した行は、幅拡大時に直前行と結合されない。
    @Test
    func el2_fullLineEraseRewrite_keepsLinesSeparateOnWiden() {
        let coordinator = TerminalCoordinator()
        let terminal = coordinator.terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows

        let overflowing = String(repeating: "A", count: cols + 5)
        coordinator.feed(Data(overflowing.utf8))

        let redraw = "\u{1b}[H\u{1b}[2KDIFF-LINE-47\r\n\u{1b}[2KDIFF-LINE-48"
        coordinator.feed(Data(redraw.utf8))
        Self.moveCursorAwayFromReflowGroup(coordinator)

        terminal.resize(cols: cols + 30, rows: rows)

        let after = coordinator.visibleText().components(separatedBy: "\n")
        let line47 = after.first(where: { $0.contains("DIFF-LINE-47") })
        #expect(line47 != nil)
        #expect(line47?.contains("DIFF-LINE-48") == false,
                "EL2 再描画後に stale isWrapped が残り、幅拡大で行が結合している")
    }

    /// EL0 (CSI K) をカーソル列 0 で実行して書き直した行も、幅拡大時に直前行と結合されない。
    @Test
    func el0_atColumnZeroRewrite_keepsLinesSeparateOnWiden() {
        let coordinator = TerminalCoordinator()
        let terminal = coordinator.terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows

        let overflowing = String(repeating: "A", count: cols + 5)
        coordinator.feed(Data(overflowing.utf8))

        let redraw = "\u{1b}[H\u{1b}[KDIFF-LINE-47\r\n\u{1b}[KDIFF-LINE-48"
        coordinator.feed(Data(redraw.utf8))
        Self.moveCursorAwayFromReflowGroup(coordinator)

        terminal.resize(cols: cols + 30, rows: rows)

        let after = coordinator.visibleText().components(separatedBy: "\n")
        let line47 = after.first(where: { $0.contains("DIFF-LINE-47") })
        #expect(line47 != nil)
        #expect(line47?.contains("DIFF-LINE-48") == false,
                "EL0 (列 0) 再描画後に stale isWrapped が残り、幅拡大で行が結合している")
    }

    /// EL0 をカーソル列 > 0 (行の途中) で実行した場合は isWrapped が保持され、幅拡大時に結合される。
    @Test
    func el0_midLinePartialErase_preservesWrapAndJoinsOnWiden() {
        let coordinator = TerminalCoordinator()
        let terminal = coordinator.terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows
        let totalLength = cols + 5

        let overflowing = String(repeating: "B", count: totalLength)
        coordinator.feed(Data(overflowing.utf8))

        // 折返し行 (2 行目) の途中 (列 3) で EL0 し、末尾だけ書き換える (isWrapped は保持される想定)
        let partialRedraw = "\u{1b}[H\u{1b}[1B\u{1b}[4G\u{1b}[KXXX"
        coordinator.feed(Data(partialRedraw.utf8))
        Self.moveCursorAwayFromReflowGroup(coordinator)

        terminal.resize(cols: cols + 30, rows: rows)

        let after = coordinator.visibleText().components(separatedBy: "\n")
        // 部分 EL0 で末尾 2 文字は XXX に置換されるが、isWrapped 保持なら先頭行と結合して cols 超の B が 1 行に載る
        let joined = after.first(where: { $0.filter { $0 == "B" }.count > cols })
        #expect(joined != nil,
                "EL0 (列 > 0) で isWrapped が保持されず、正当な折返し行が幅拡大で結合されない")
    }

    /// EL を使わない正当な soft wrap 行は、幅拡大時に 1 行へ結合される。
    @Test
    func genuineSoftWrap_withoutEL_joinsOnWiden() {
        let coordinator = TerminalCoordinator()
        let terminal = coordinator.terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows

        let overflowing = String(repeating: "C", count: cols + 5)
        coordinator.feed(Data(overflowing.utf8))
        Self.moveCursorAwayFromReflowGroup(coordinator)

        terminal.resize(cols: cols + 30, rows: rows)

        let after = coordinator.visibleText().components(separatedBy: "\n")
        let joined = after.first(where: { $0.contains(String(repeating: "C", count: cols + 5)) })
        #expect(joined != nil, "EL を挟まない正当な soft wrap 行が reflow で結合されなくなっている")
    }
}
