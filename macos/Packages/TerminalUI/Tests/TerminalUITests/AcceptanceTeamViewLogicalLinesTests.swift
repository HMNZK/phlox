// task-28（BUG-02）の受け入れテスト。
//
// ベースライン（実装前）での red 理由: `TerminalCoordinator.visibleText(joinWrappedRows:)` は本タスクが新設を
// 要求する API で、baseline_commit の時点では存在しない。したがって本ファイルはテストターゲットに置いた時点で
// コンパイル不能（参照未解決）で red になる（task-27 と同じ「新 API 不在でコンパイル不能」の red）。
//
// 契約: `visibleText()`（既定）は従来どおり物理行を LF で連結する（`phlox read` 等の互換）。
// `visibleText(joinWrappedRows: true)` は、SwiftTerm がソフトラップで折り返した続き行（`BufferLine.isWrapped`）
// を直前の行へ連結して**論理行**を返す。明示改行（CR/LF）由来の行は決して連結しない。連結境界の空白は
// 保持し、末尾の空白だけを論理行の末尾で 1 回落とす。
// 根拠: `docs/agent-output/investigation-bug-02.md` 推奨アクション 3（PTY を resize せず抽出層で isWrapped を復元）。

import Foundation
import SwiftTerm
import Testing
@testable import TerminalUI

@MainActor
@Suite("task-28: team view logical lines", .serialized)
struct AcceptanceTeamViewLogicalLinesTests {
    private func makeCoordinator() -> (TerminalCoordinator, cols: Int) {
        let coordinator = TerminalCoordinator()
        return (coordinator, coordinator.terminalView.getTerminal().cols)
    }

    @Test("端末幅を溢れてソフトラップした行は 1 本の論理行に戻る")
    func softWrappedRowsJoinIntoOneLogicalLine() {
        let (c, cols) = makeCoordinator()
        let long = String(repeating: "A", count: cols + 5)
        c.feed(Data((long + "\r\nB").utf8))

        let physical = c.visibleText().components(separatedBy: "\n")
        #expect(physical.count == 3)
        #expect(physical[0].count == cols)
        #expect(physical[1] == "AAAAA")
        #expect(physical[2] == "B")

        let logical = c.visibleText(joinWrappedRows: true).components(separatedBy: "\n")
        #expect(logical == [long, "B"])
    }

    @Test("3 行にまたがるソフトラップも 1 本に戻り、明示改行の行は連結されない")
    func multiRowWrapJoinsButHardNewlinesDoNot() {
        let (c, cols) = makeCoordinator()
        let long = String(repeating: "X", count: cols * 2 + 3)
        c.feed(Data(("first\r\n" + long + "\r\nlast").utf8))
        let logical = c.visibleText(joinWrappedRows: true).components(separatedBy: "\n")
        #expect(logical == ["first", long, "last"])
    }

    @Test("連結境界の空白は保持され、末尾空白だけ落ちる")
    func whitespaceAtWrapBoundaryIsPreserved() {
        let (c, cols) = makeCoordinator()
        let head = String(repeating: "A", count: cols - 3) + "   " // 行末 3 スペースで行がちょうど埋まる
        c.feed(Data((head + "BB   \r\n").utf8))
        let logical = c.visibleText(joinWrappedRows: true).components(separatedBy: "\n")
        #expect(logical.first == head + "BB")
    }

    @Test("既定の visibleText() は物理行のまま（互換維持）")
    func defaultVisibleTextIsUnchanged() {
        let (c, cols) = makeCoordinator()
        c.feed(Data(String(repeating: "Z", count: cols + 1).utf8))
        #expect(c.visibleText() == c.visibleText(joinWrappedRows: false))
        #expect(c.visibleText().components(separatedBy: "\n").count == 2)
    }

    @Test("折り返しの無い画面では両者が一致する")
    func noWrapMeansIdenticalOutput() {
        let (c, _) = makeCoordinator()
        c.feed(Data("alpha\r\nbeta\r\n\r\ngamma".utf8))
        #expect(c.visibleText(joinWrappedRows: true) == c.visibleText())
        #expect(c.visibleText().components(separatedBy: "\n") == ["alpha", "beta", "", "gamma"])
    }
    @Test("viewport 先頭行が継続行でも落ちず、独立した論理行として扱う（2026-09-12 敵対レビュー MUST-2）")
    func continuationRowAtViewportTopDoesNotCrash() {
        let (c, cols) = makeCoordinator()
        let rows = c.terminalView.getTerminal().rows
        for i in 0..<(rows - 1) { c.feed(Data("f\(i)\r\n".utf8)) }
        c.feed(Data(String(repeating: "W", count: cols * 3 + 2).utf8))
        c.feed(Data("\r\n".utf8))
        for i in 0..<(rows - 3) { c.feed(Data("g\(i)\r\n".utf8)) }
        // 先頭行は継続行（頭は scrollback 側）。クラッシュせず、画面内に残った継続 2 行ぶんが 1 本にまとまる。
        let logical = c.visibleText(joinWrappedRows: true).components(separatedBy: "\n")
        #expect(logical.first == String(repeating: "W", count: cols + 2))
        #expect(logical.contains("g0"))
    }

    @Test("スクロール発生後にカーソルを画面上部へ戻して書いた折り返しも復元される（Vendor Buffer の yBase 加算。敵対レビュー HIGH-4）")
    func wrapAfterScrollbackWithCursorMovedUpIsRestored() {
        let (c, cols) = makeCoordinator()
        let rows = c.terminalView.getTerminal().rows
        for i in 0..<(rows + 5) { c.feed(Data("line\(i)\r\n".utf8)) } // yBase > 0 にする
        c.feed(Data("\u{1b}[2;1H".utf8)) // 2 行目・1 列目へ
        let long = String(repeating: "Q", count: cols + 4)
        c.feed(Data(long.utf8))
        let terminal = c.terminalView.getTerminal()
        #expect(terminal.getLine(row: 2)?.isWrapped == true, "継続行（3 行目）に isWrapped が立つ")
        #expect(terminal.getLine(row: 1)?.isWrapped == false)
        let logical = c.visibleText(joinWrappedRows: true).components(separatedBy: "\n")
        #expect(logical.contains(long), "折り返しが 1 本の論理行に戻る")
        #expect(!logical.contains("QQQQ"), "続き 4 文字だけの行が残らない")
    }
}
