import Testing
import Foundation
import SwiftTerm
@testable import TerminalUI

/// 「ClaudeCode 処理中に上スクロールしても出力のたび最下部へ戻る」バグを固定する
/// 特性化テスト（characterization test）。
///
/// 真因: `Terminal.scroll()` が linefeed のたび `if !userScrolling { buffer.yDisp = buffer.yBase }`
/// で最下部へスナップするが、`terminal.userScrolling` がどこからも true にされず死にフラグだった。
/// 修正後は `scrollTo(row:)` が「要求 row が最下部(yBase)より上か」を `terminal.userScrolling`
/// に連動させ、上スクロール中は追従停止・最下部復帰で追従再開する。
///
/// `scrollPosition` は public で、最下部（yDisp>=maxScrollback）で 1、最下部より上で 1 未満を返す。
/// よって追従/非追従の観測プロキシとして使える。
@MainActor
struct TerminalFollowOnOutputTests {

    /// viewport を確実に溢れさせ、normal buffer に履歴行を積むのに十分な行数。
    /// 既存 `TerminalCoordinatorScrollbackTests` と同じ 200 行。
    private static let overflowLineCount = 200

    private static func feedOverflowingLines(_ coordinator: TerminalCoordinator) {
        feedLines(coordinator, count: overflowLineCount)
    }

    private static func feedLines(_ coordinator: TerminalCoordinator, count: Int) {
        var bytes = ""
        bytes.reserveCapacity(count * 8)
        for i in 0..<count {
            bytes += "line \(i)\r\n"
        }
        coordinator.feed(Data(bytes.utf8))
    }

    /// 退行固定: keep-scrollback で viewport を溢れさせ最下部（scrollPosition==1）→
    /// scrollUp(lines: 5) で上へ離す（scrollPosition < 1）→ さらに出力を feed →
    /// 上スクロール中は最下部へ戻らず、離れた位置を保つ（scrollPosition が 1 へ戻らない）。
    @Test
    func keepScrollback_userScrolledUp_outputDoesNotSnapToBottom() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView

        Self.feedOverflowingLines(coordinator)
        #expect(view.scrollPosition == 1)

        view.scrollUp(lines: 5)
        let positionAfterScrollUp = view.scrollPosition
        #expect(positionAfterScrollUp < 1)

        // さらに出力が来ても最下部へスナップしない。
        Self.feedLines(coordinator, count: 10)

        #expect(view.scrollPosition < 1)
    }

    /// 追従の対照: keep-scrollback で最下部（scrollPosition==1）にいる状態で出力を feed →
    /// scrollPosition == 1 のまま（自動追従が壊れていない）。
    @Test
    func keepScrollback_atBottom_outputKeepsFollowing() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView

        Self.feedOverflowingLines(coordinator)
        #expect(view.scrollPosition == 1)

        Self.feedLines(coordinator, count: 10)

        #expect(view.scrollPosition == 1)
    }

    /// 再開: 上へ離した後 scrollDown で最下部へ戻す → さらに出力を feed →
    /// 再び scrollPosition == 1 に追従する（最下部復帰で追従再開）。
    @Test
    func keepScrollback_returnToBottom_resumesFollowing() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView

        Self.feedOverflowingLines(coordinator)
        #expect(view.scrollPosition == 1)

        view.scrollUp(lines: 5)
        #expect(view.scrollPosition < 1)

        // 最下部へ戻す。scrollback 全幅分 scrollDown すれば確実に最下部に着く。
        view.scrollDown(lines: Self.overflowLineCount)
        #expect(view.scrollPosition == 1)

        // 最下部復帰後は再び追従する。
        Self.feedLines(coordinator, count: 10)

        #expect(view.scrollPosition == 1)
    }
}
