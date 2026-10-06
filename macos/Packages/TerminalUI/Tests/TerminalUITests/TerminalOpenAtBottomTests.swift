import AppKit
import Foundation
import Testing
@testable import TerminalUI

@MainActor
struct TerminalOpenAtBottomTests {

    @Test("明示的な最下部復帰だけが読み戻し後の追従を再開する")
    func explicitOpenAtBottomResumesFollow() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView
        feedLines(coordinator, count: 200)
        view.scrollUp(lines: 5)
        #expect(view.scrollPosition < 1)

        coordinator.scrollToBottom()
        feedLines(coordinator, count: 1)

        #expect(view.scrollPosition == 1)
    }

    @Test("セッション再起動後も明示的な最下部復帰は追従を再開する")
    func resumesFollowingAfterRestart() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView
        feedLines(coordinator, count: 200)
        view.scrollUp(lines: 5)
        #expect(view.scrollPosition < 1, "前提: 上へ離れている")
        coordinator.resetBuffer()

        coordinator.scrollToBottom()
        feedLines(coordinator, count: 200)

        #expect(
            view.scrollPosition == 1,
            "任意の事前状態から呼んでも以後の出力へ追従すること"
        )
    }

    @Test("同じコンテナへの再更新では載せ替えない")
    func sameContainerDoesNotRemount() {
        let coordinator = TerminalCoordinator()
        let container = NSView()

        #expect(TerminalMount.attach(coordinator.hostingView, to: container) == true)
        #expect(TerminalMount.attach(coordinator.hostingView, to: container) == false)
    }

    @Test("別コンテナへ移したときだけ載せ替える")
    func newContainerRemounts() {
        let coordinator = TerminalCoordinator()
        let firstContainer = NSView()
        let secondContainer = NSView()

        #expect(TerminalMount.attach(coordinator.hostingView, to: firstContainer) == true)
        #expect(TerminalMount.attach(coordinator.hostingView, to: secondContainer) == true)
        #expect(coordinator.hostingView.superview === secondContainer)
    }

    @Test("載せ替え直後のスクロールは同期せず、次のrunloopで最下部へ戻す")
    func reparentDefersScrollToBottom() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView
        feedLines(coordinator, count: 200)
        view.scrollUp(lines: 5)
        var scheduled: [() -> Void] = []

        TerminalMount.attachAndScheduleScrollToBottom(coordinator, to: NSView()) { scheduled.append($0) }

        #expect(scheduled.count == 1)
        #expect(view.scrollPosition < 1, "スケジュールされただけでは動かさない")
        scheduled.forEach { $0() }
        #expect(view.scrollPosition == 1)
    }

    @Test("同じコンテナへの再更新ではスクロールを予約せず、読み戻し位置を保つ")
    func sameContainerUpdateDoesNotScheduleScroll() {
        let coordinator = TerminalCoordinator()
        let view = coordinator.terminalView
        let container = NSView()
        feedLines(coordinator, count: 200)
        TerminalMount.attachAndScheduleScrollToBottom(coordinator, to: container) { _ in }
        view.scrollUp(lines: 5)
        var scheduled: [() -> Void] = []

        TerminalMount.attachAndScheduleScrollToBottom(coordinator, to: container) { scheduled.append($0) }

        #expect(scheduled.isEmpty)
        #expect(view.scrollPosition < 1)
    }

    private func feedLines(_ coordinator: TerminalCoordinator, count: Int) {
        var output = ""
        output.reserveCapacity(count * 8)
        for index in 0..<count {
            output += "line \(index)\r\n"
        }
        coordinator.feed(Data(output.utf8))
    }
}
