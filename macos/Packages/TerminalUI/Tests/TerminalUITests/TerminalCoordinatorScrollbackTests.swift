import Testing
import Foundation
import SwiftTerm
@testable import TerminalUI

/// 「Codex/Cursor だけ会話履歴をマウススクロールできない」バグの直接原因を決定的に固定する
/// 特性化テスト（characterization test）。
///
/// 仮説検証の良枝/悪枝（ゴースト機序が reflow 再ラップか TUI フレーム蓄積か）は実 CLI の
/// 起動時バイト列に依存するため実機ログで切り分ける。一方、ここで固定するのは機序に依存しない
/// 「直接原因」: spawn 直前に scrollbackPolicy=.disableBeforeSpawn で `disableScrollback()` を
/// 呼ぶと（= claudeCode 以外）、SwiftTerm の `canScroll` が false に張り付き、ホイールスクロールの
/// 実体である `scrollUp` が no-op になること。
///
/// `canScroll` は SwiftTerm 公開プロパティで、内部的に
/// `!isDisplayBufferAlternate && displayBuffer.hasScrollback && lines.count > rows` を返す。
/// よってユーザーがスクロールできるか否かの公開プロキシとして使える。
@MainActor
struct TerminalCoordinatorScrollbackTests {

    /// viewport を確実に溢れさせ、normal buffer に履歴行を積むのに十分な行数。
    /// 既定 scrollback=500 行に対し十分小さく、既定 rows（25〜レイアウト後数十行）を必ず超える。
    private static let overflowLineCount = 200

    private static func feedOverflowingLines(_ coordinator: TerminalCoordinator) {
        var bytes = ""
        bytes.reserveCapacity(overflowLineCount * 8)
        for i in 0..<overflowLineCount {
            bytes += "line \(i)\r\n"
        }
        coordinator.feed(Data(bytes.utf8))
    }

    /// claudeCode 経路（scrollbackPolicy=.keep）相当: 既定 scrollback=500 が有効なため、
    /// viewport を溢れる出力後は履歴がたまり canScroll=true になる（= 遡れる）。
    @Test
    func keepScrollback_afterOverflowingOutput_canScroll() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView

        Self.feedOverflowingLines(coordinator)

        #expect(view.canScroll == true)
    }

    /// codex/cursor 経路（scrollbackPolicy=.disableBeforeSpawn）相当: spawn 直前に
    /// disableScrollback() を呼ぶと、同じだけ出力しても履歴がたまらず canScroll=false に張り付く。
    /// これが「Codex/Cursor だけ履歴スクロールできない」の直接原因。
    @Test
    func disableScrollback_afterOverflowingOutput_cannotScroll() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView

        coordinator.disableScrollback()
        Self.feedOverflowingLines(coordinator)

        #expect(view.canScroll == false)
    }

    /// disableScrollback 後はホイールスクロールの実体（scrollUp）が viewport を動かせない（no-op）。
    /// scrollPosition は public で、yDisp<=0 のとき 0 を返す。出力で溢れさせても 0 のまま、
    /// scrollUp を呼んでも 0 のままであることを示す。
    @Test
    func disableScrollback_scrollUpIsNoOp() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView

        coordinator.disableScrollback()
        Self.feedOverflowingLines(coordinator)

        #expect(view.scrollPosition == 0)
        view.scrollUp(lines: view.getTerminal().rows)
        #expect(view.scrollPosition == 0)
    }

    /// 対照: scrollback を保持していれば、同じ scrollUp が viewport を上へ動かせる（履歴を遡れる）。
    /// 溢れた出力直後は最下部（scrollPosition==1）にいる。scrollUp で 1 未満へ動くことを示す。
    @Test
    func keepScrollback_scrollUpMovesViewport() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView

        Self.feedOverflowingLines(coordinator)

        #expect(view.scrollPosition == 1)
        view.scrollUp(lines: 5)
        #expect(view.scrollPosition < 1)
    }
}
