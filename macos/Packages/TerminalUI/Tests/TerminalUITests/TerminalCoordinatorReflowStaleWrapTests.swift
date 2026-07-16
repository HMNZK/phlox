import Testing
import Foundation
import SwiftTerm
@testable import TerminalUI

/// 「Claude Code の画面がリサイズ後に複数カラム状に崩れる」バグの回帰テスト。
///
/// 機序(調査で証明済み):
/// 1. 行が端末幅を溢れて soft wrap すると、続き行に isWrapped=true が立つ。
/// 2. Ink 系 TUI (Claude Code) は再描画時に EL (CSI 2K) で行を消して別の内容を書き直すが、
///    修正前の SwiftTerm cmdEraseInLine は isWrapped をクリアしない (clearWrap を渡していない)。
/// 3. その後ビューが広くなると reflowWider (isReflowEnabled = scrollback 有効 = claudeCode の
///    scrollbackPolicy .keep) が stale な isWrapped を根拠に「別々の論理行」を 1 本の横長行へ
///    結合し、行断片が左・中・右に並ぶ多段カラム状の崩れになる。
///
/// 修正: cmdEraseInLine が行全体消去 (EL 2) と行頭からの消去 (EL 0 かつ cursor.x==0) のとき
/// isWrapped をクリアする (xterm.js と同等の挙動)。このテストは修正後の期待値を固定する。
@MainActor
struct TerminalCoordinatorReflowStaleWrapTests {

    /// overflow で isWrapped が立った行を EL(2K) で消して別内容を書き直した場合、
    /// 幅を広げても 2 つの独立した行は結合されない(修正後の期待値)。
    @Test
    func eraseLineRewriteAfterOverflow_keepsLinesSeparateOnWiden() {
        let coordinator = TerminalCoordinator()
        let terminal = coordinator.terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows

        // 1. 端末幅を 5 セル溢れる行を出力 → 2 行目に soft wrap (isWrapped=true)
        let overflowing = String(repeating: "A", count: cols + 5)
        coordinator.feed(Data(overflowing.utf8))

        // 2. Ink 風の再描画: ホームへ戻り、各行を EL(2K) で消して別の内容を書く
        let redraw = "\u{1b}[H\u{1b}[2KDIFF-LINE-47\r\n\u{1b}[2KDIFF-LINE-48"
        coordinator.feed(Data(redraw.utf8))

        // カーソルを折返しグループの外へ移す (reflow はカーソルを含むグループを結合しないため、
        // 実症状もカーソルから離れた transcript 行で起きる)
        coordinator.feed(Data("\r\n\r\nprompt>".utf8))

        // この時点では 2 行は別々に見える
        let before = coordinator.visibleText().components(separatedBy: "\n")
        #expect(before.first?.contains("DIFF-LINE-47") == true)
        #expect(before.first?.contains("DIFF-LINE-48") == false)

        // 3. 幅を広げる (シングル表示化・サイドバー閉などに相当)
        terminal.resize(cols: cols + 30, rows: rows)

        // 修正後の期待値: EL が isWrapped をクリアするため、47/48 は結合されない
        let after = coordinator.visibleText().components(separatedBy: "\n")
        let line47 = after.first(where: { $0.contains("DIFF-LINE-47") })
        #expect(line47 != nil)
        #expect(line47?.contains("DIFF-LINE-48") == false,
                "stale isWrapped による不正結合が再発している (cmdEraseInLine の clearWrap 退行を疑う)")
    }

    /// 対照: overflow を経ていなければ、同じ EL 再描画 + 幅拡大でも行は結合されない。
    @Test
    func noOverflow_eraseLineRewriteThenWiden_keepsLinesSeparate() {
        let coordinator = TerminalCoordinator()
        let terminal = coordinator.terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows

        let redraw = "\u{1b}[H\u{1b}[2KDIFF-LINE-47\r\n\u{1b}[2KDIFF-LINE-48"
        coordinator.feed(Data(redraw.utf8))
        coordinator.feed(Data("\r\n\r\nprompt>".utf8))

        terminal.resize(cols: cols + 30, rows: rows)

        let after = coordinator.visibleText().components(separatedBy: "\n")
        let line47 = after.first(where: { $0.contains("DIFF-LINE-47") })
        #expect(line47?.contains("DIFF-LINE-48") == false)
    }

    /// 対照: scrollback 無効 (codex/cursor の .disableBeforeSpawn 経路) なら reflow 自体が
    /// 走らないため、同じ手順でも結合は起きない。
    @Test
    func staleWrapFlag_withScrollbackDisabled_doesNotJoinOnWiden() {
        let coordinator = TerminalCoordinator()
        coordinator.disableScrollback()
        let terminal = coordinator.terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows

        let overflowing = String(repeating: "A", count: cols + 5)
        coordinator.feed(Data(overflowing.utf8))
        let redraw = "\u{1b}[H\u{1b}[2KDIFF-LINE-47\r\n\u{1b}[2KDIFF-LINE-48"
        coordinator.feed(Data(redraw.utf8))
        coordinator.feed(Data("\r\n\r\nprompt>".utf8))

        terminal.resize(cols: cols + 30, rows: rows)

        let after = coordinator.visibleText().components(separatedBy: "\n")
        let line47 = after.first(where: { $0.contains("DIFF-LINE-47") })
        #expect(line47?.contains("DIFF-LINE-48") == false)
    }

    /// 正当な soft wrap (EL を挟まない本物の折返し) は修正後も従来どおり結合される
    /// (reflow 本来の機能を壊していないことの確認)。
    @Test
    func genuineSoftWrap_stillJoinsOnWiden() {
        let coordinator = TerminalCoordinator()
        let terminal = coordinator.terminalView.getTerminal()
        let cols = terminal.cols
        let rows = terminal.rows

        // 端末幅 + 5 セルの本物の長い行 (EL での書き換えなし)
        let overflowing = String(repeating: "B", count: cols + 5)
        coordinator.feed(Data(overflowing.utf8))
        coordinator.feed(Data("\r\n\r\nprompt>".utf8))

        terminal.resize(cols: cols + 30, rows: rows)

        // 全 B が 1 行に結合されている
        let after = coordinator.visibleText().components(separatedBy: "\n")
        let joined = after.first(where: { $0.contains(String(repeating: "B", count: cols + 5)) })
        #expect(joined != nil, "正当な soft wrap 行が reflow で結合されなくなっている (reflow 機能の退行)")
    }
}
