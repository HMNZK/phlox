import Testing
import Foundation
import SwiftTerm
@testable import TerminalUI

// task-3 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-3.md
// 目的（A-3）: デスクトップでターミナル表示のセッションを開く／切り替えたとき、最下部（最新）から
//   表示する。TerminalCoordinator はセッション寿命を通じて同じ SwiftTerm.TerminalView を保持するため、
//   上へ読み戻した位置がそのまま残る（＝最新でない位置で開く）のを断つ。
//
// `scrollPosition` は SwiftTerm の公開プロパティで、最下部（yDisp >= maxScrollback）で 1、
// それより上で 1 未満を返す。既存の TerminalCoordinatorScrollbackTests /
// TerminalFollowOnOutputTests と同じ観測プロキシを使う。
@MainActor
struct AcceptanceTerminalOpenAtBottomTests {

    /// viewport を確実に溢れさせ、normal buffer に履歴行を積むのに十分な行数（既存テストと同じ 200 行）。
    private static let overflowLineCount = 200

    private static func feedLines(_ coordinator: TerminalCoordinator, count: Int) {
        var bytes = ""
        bytes.reserveCapacity(count * 8)
        for i in 0..<count {
            bytes += "line \(i)\r\n"
        }
        coordinator.feed(Data(bytes.utf8))
    }

    @Test("上へ読み戻した位置から最下部（最新）へ戻る")
    func returnsToLatestFromScrolledUpPosition() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView
        Self.feedLines(coordinator, count: Self.overflowLineCount)
        view.scrollUp(lines: 5)
        #expect(view.scrollPosition < 1, "前提: 上へ離れていること")

        coordinator.scrollToBottom()

        #expect(
            view.scrollPosition == 1,
            "セッションを開いたときは最下部（最新）から表示すること"
        )
    }

    @Test("最下部へ戻したら以降の出力へ再び追従する")
    func resumesFollowingAfterReturningToBottom() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView
        Self.feedLines(coordinator, count: Self.overflowLineCount)
        view.scrollUp(lines: 5)
        #expect(view.scrollPosition < 1, "前提: 上へ離れていること")

        coordinator.scrollToBottom()
        Self.feedLines(coordinator, count: 10)

        #expect(
            view.scrollPosition == 1,
            "最下部復帰で userScrolling が解除され、新しい出力に追従すること"
        )
    }

    @Test("すでに最下部なら位置を変えない")
    func keepsPositionWhenAlreadyAtBottom() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView
        Self.feedLines(coordinator, count: Self.overflowLineCount)
        #expect(view.scrollPosition == 1, "前提: 溢れた直後は最下部")

        coordinator.scrollToBottom()

        #expect(view.scrollPosition == 1)
    }

    @Test("scrollback を無効化したセッションでも最下部のまま壊れない")
    func staysConsistentWithScrollbackDisabled() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView
        coordinator.disableScrollback()
        Self.feedLines(coordinator, count: Self.overflowLineCount)

        coordinator.scrollToBottom()

        #expect(
            view.scrollPosition == 0,
            "scrollback 無効時は scrollPosition が 0 のまま（履歴が無いので動かせない）であること"
        )
    }
}
