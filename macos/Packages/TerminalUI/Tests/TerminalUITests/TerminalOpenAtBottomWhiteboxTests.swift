import AppKit
import Foundation
import Testing
@testable import TerminalUI

@MainActor
struct TerminalOpenAtBottomWhiteboxTests {

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

    @Test("コンテナへの載せ替え後のスクロールは次のrunloopへ遅延する")
    func reparentDefersScrollMutation() throws {
        let source = try TerminalOpenAtBottomWhiteboxSource.text("TerminalView.swift")

        #expect(source.contains("""
        DispatchQueue.main.async { [weak coordinator] in
                    coordinator?.scrollToBottom()
                }
        """))
        // PM 追記: attach の戻り値を捨てると SwiftUI の更新ごとに最下部へ引き戻す退行になるが、
        // updateNSView は Context を組めないため振る舞いでは検証できない（変異で素通りを実証済み）。
        #expect(
            source.contains("guard TerminalMount.attach(coordinator.hostingView, to: nsView) else { return }"),
            "載せ替えが起きたときだけ最下部へ寄せる（attach の戻り値を捨てない）"
        )
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

private enum TerminalOpenAtBottomWhiteboxSource {
    static func text(_ relativePath: String) throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot.appendingPathComponent("Sources/TerminalUI/\(relativePath)"),
            encoding: .utf8
        )
    }
}
