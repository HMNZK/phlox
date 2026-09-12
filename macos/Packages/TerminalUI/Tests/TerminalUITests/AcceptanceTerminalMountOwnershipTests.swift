// task-39（BUG-01）受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-39.md
// 目的: 永続 hostingView の所有権を最後に有効な接続を要求した mount に固定し、
//   旧 mount の後着 update / detach が奪い返せないこと。正当な再利用（生存 A の再接続、
//   新 C、同一コンテナのセッション切替）は妨げない。
//
// 期待する所有者・Bool・固定文字列は契約の事後条件表と成功基準 1 から置く。
// 実装の owner getter・判定関数・ソース解析から期待値を生成しない。
// コンテナは実ウィンドウに載せない（window == nil でも新 mount が接続できること）。

import AppKit
import Foundation
import Testing
@testable import TerminalUI

@MainActor
@Suite("task-39: terminal mount ownership", .serialized)
struct AcceptanceTerminalMountOwnershipTests {
    /// 成功基準 1「端末の保持」で feed する契約側の固定文字列。
    private static let keptOutput = "KEEP-OUTPUT-TASK39"

    private func makeCoordinator() -> TerminalCoordinator {
        TerminalCoordinator()
    }

    private func makeContainer() -> NSView {
        NSView(frame: .zero)
    }

    /// 端末とコンテナを結ぶ、現在有効なピン制約。
    private func activePinConstraints(between terminal: NSView, and container: NSView) -> [NSLayoutConstraint] {
        container.constraints.filter { constraint in
            guard constraint.isActive else { return false }
            let first = constraint.firstItem as AnyObject?
            let second = constraint.secondItem as AnyObject?
            return (first === terminal && second === container)
                || (first === container && second === terminal)
        }
    }

    // MARK: - 事後条件表 8 行（各 1 ケース）

    @Test("未接続の端末を A に attach すると true で superview は A")
    func unconnectedTerminalAttachesToA() {
        let coordinator = makeCoordinator()
        let containerA = makeContainer()
        #expect(containerA.window == nil)
        #expect(coordinator.hostingView.window == nil)
        #expect(coordinator.hostingView.superview == nil)

        let attached = TerminalMount.attach(coordinator.hostingView, to: containerA)

        #expect(attached == true)
        #expect(coordinator.hostingView.superview === containerA)
        #expect(containerA.subviews.count == 1)
        #expect(containerA.subviews.first === coordinator.hostingView)
    }

    @Test("同じ端末を新 mount B に attach すると true で superview は B")
    func newMountBTakesOwnership() {
        let coordinator = makeCoordinator()
        let containerA = makeContainer()
        let containerB = makeContainer()
        #expect(containerB.window == nil)
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerA) == true)

        let attached = TerminalMount.attach(coordinator.hostingView, to: containerB)

        #expect(attached == true)
        #expect(coordinator.hostingView.superview === containerB)
        #expect(containerA.subviews.isEmpty)
        #expect(containerB.subviews.first === coordinator.hostingView)
    }

    @Test("A の後着 update が再び attach しても false で superview は B のまま")
    func staleOwnerACannotStealFromB() {
        let coordinator = makeCoordinator()
        let containerA = makeContainer()
        let containerB = makeContainer()
        let first = TerminalMount.attach(coordinator.hostingView, to: containerA)
        let second = TerminalMount.attach(coordinator.hostingView, to: containerB)

        let stale = TerminalMount.attach(coordinator.hostingView, to: containerA)

        #expect(first == true)
        #expect(second == true)
        #expect(stale == false)
        #expect(coordinator.hostingView.superview === containerB)
        #expect(containerB.subviews.first === coordinator.hostingView)
        #expect(containerA.subviews.isEmpty)
    }

    @Test("B の連続 update は false で superview・subview 数・有効制約は変わらない")
    func consecutiveUpdateOnBIsNoOp() {
        let coordinator = makeCoordinator()
        let containerA = makeContainer()
        let containerB = makeContainer()
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerA) == true)
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerB) == true)

        let pinsBefore = activePinConstraints(between: coordinator.hostingView, and: containerB)
        let subviewsBefore = containerB.subviews.count
        let consecutive = TerminalMount.attach(coordinator.hostingView, to: containerB)
        let pinsAfter = activePinConstraints(between: coordinator.hostingView, and: containerB)

        #expect(consecutive == false)
        #expect(coordinator.hostingView.superview === containerB)
        #expect(containerB.subviews.count == subviewsBefore)
        #expect(pinsAfter.count == pinsBefore.count)
        #expect(pinsAfter.elementsEqual(pinsBefore, by: { $0 === $1 }))
    }

    @Test("B 所有中に A が detach しても false で B の接続は維持")
    func staleOwnerACannotDetachWhileBOwns() {
        let coordinator = makeCoordinator()
        let containerA = makeContainer()
        let containerB = makeContainer()
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerA) == true)
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerB) == true)

        let detached = TerminalMount.detach(coordinator.hostingView, from: containerA)

        #expect(detached == false)
        #expect(coordinator.hostingView.superview === containerB)
        #expect(containerB.subviews.first === coordinator.hostingView)
    }

    @Test("B が detach すると true で superview は nil、再 detach は false")
    func ownerBDetachReleasesAndSecondDetachFails() {
        let coordinator = makeCoordinator()
        let containerA = makeContainer()
        let containerB = makeContainer()
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerA) == true)
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerB) == true)

        let firstDetach = TerminalMount.detach(coordinator.hostingView, from: containerB)
        let secondDetach = TerminalMount.detach(coordinator.hostingView, from: containerB)

        #expect(firstDetach == true)
        #expect(coordinator.hostingView.superview == nil)
        #expect(containerB.subviews.isEmpty)
        #expect(secondDetach == false)
        #expect(coordinator.hostingView.superview == nil)
    }

    @Test("B 解放後に生存している A が改めて attach すると true で superview は A")
    func survivingACanReattachAfterBRelease() {
        let coordinator = makeCoordinator()
        let containerA = makeContainer()
        let containerB = makeContainer()
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerA) == true)
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerB) == true)
        #expect(TerminalMount.detach(coordinator.hostingView, from: containerB) == true)

        let reattached = TerminalMount.attach(coordinator.hostingView, to: containerA)

        #expect(reattached == true)
        #expect(coordinator.hostingView.superview === containerA)
        #expect(containerA.subviews.first === coordinator.hostingView)
        #expect(containerB.subviews.isEmpty)
    }

    @Test("B 解放後に新しい C が attach すると true で superview は C")
    func newCCanAttachAfterBRelease() {
        let coordinator = makeCoordinator()
        let containerA = makeContainer()
        let containerB = makeContainer()
        let containerC = makeContainer()
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerA) == true)
        #expect(TerminalMount.attach(coordinator.hostingView, to: containerB) == true)
        #expect(TerminalMount.detach(coordinator.hostingView, from: containerB) == true)

        let attached = TerminalMount.attach(coordinator.hostingView, to: containerC)

        #expect(attached == true)
        #expect(coordinator.hostingView.superview === containerC)
        #expect(containerC.subviews.first === coordinator.hostingView)
        #expect(containerA.subviews.isEmpty)
        #expect(containerB.subviews.isEmpty)
        #expect(containerC.window == nil)
    }

    // MARK: - 成功基準 1 の追加必須ケース

    @Test("同じコンテナで端末 X→Y→X を接続でき、X の遅れた detach は Y を外さない")
    func sameContainerSessionSwitchXYX() {
        let terminalX = makeCoordinator()
        let terminalY = makeCoordinator()
        let container = makeContainer()

        #expect(TerminalMount.attach(terminalX.hostingView, to: container) == true)
        #expect(TerminalMount.attach(terminalY.hostingView, to: container) == true)
        #expect(terminalX.hostingView.superview == nil)
        #expect(terminalY.hostingView.superview === container)
        #expect(container.subviews.count == 1)
        #expect(container.subviews.first === terminalY.hostingView)

        let staleRelease = TerminalMount.detach(terminalX.hostingView, from: container)
        #expect(staleRelease == false)
        #expect(terminalY.hostingView.superview === container)
        #expect(container.subviews.first === terminalY.hostingView)

        #expect(TerminalMount.attach(terminalX.hostingView, to: container) == true)
        #expect(terminalX.hostingView.superview === container)
        #expect(terminalY.hostingView.superview == nil)
        #expect(container.subviews.count == 1)
        #expect(container.subviews.first === terminalX.hostingView)
    }

    @Test("載せ替え後も coordinator・hostingView・terminalView と feed 済み出力を保持する")
    func remountKeepsIdentityAndFedOutput() {
        let coordinator = makeCoordinator()
        let hostingView = coordinator.hostingView
        let terminalView = coordinator.terminalView
        coordinator.feed(Data("\(Self.keptOutput)\n".utf8))
        #expect(coordinator.visibleText().contains(Self.keptOutput))

        let containerA = makeContainer()
        let containerB = makeContainer()
        #expect(TerminalMount.attach(hostingView, to: containerA) == true)
        #expect(TerminalMount.attach(hostingView, to: containerB) == true)

        #expect(coordinator.hostingView === hostingView)
        #expect(coordinator.terminalView === terminalView)
        #expect(coordinator.visibleText().contains(Self.keptOutput))
        #expect(coordinator.hostingView.superview === containerB)
    }

    // MARK: - 契約改訂 2（独立レビュー指摘1）

    /// 実破棄経路。SwiftUI が破棄時に渡すのは `makeCoordinator()` 時点のオブジェクト。
    /// mount 状態は `TerminalMountCoordinator` が保持し、`updateNSView` 相当で
    /// `mount.current` を差し替えたあと、その mount を `dismantleNSView` に渡す。
    @Test("coordinator を X→Y に差し替えた mount の破棄で Y が解放され X は影響しない")
    func dismantleAfterCoordinatorSwapReleasesYNotX() {
        let x = makeCoordinator()
        let y = makeCoordinator()
        let c = makeContainer()
        let oldTile = makeContainer()
        let mount: TerminalMountCoordinator = TerminalView(coordinator: x).makeCoordinator()
        #expect(c.window == nil)

        #expect(TerminalMount.attach(x.hostingView, to: c) == true)
        #expect(TerminalMount.attach(y.hostingView, to: oldTile) == true)
        mount.current = y
        #expect(TerminalMount.attach(y.hostingView, to: c) == true)
        #expect(y.hostingView.superview === c)
        #expect(x.hostingView.superview == nil)

        withExtendedLifetime(c) {
            TerminalView.dismantleNSView(c, coordinator: mount)
            #expect(y.hostingView.superview == nil)
            #expect(x.hostingView.superview == nil)
            #expect(c.subviews.isEmpty)
            #expect(TerminalMount.attach(y.hostingView, to: oldTile) == true)
            #expect(y.hostingView.superview === oldTile)
        }
    }

    @Test("A→B の後に A を破棄しても hostingView.superview は B のまま")
    func dismantleStaleADoesNotReleaseB() {
        let x = makeCoordinator()
        let containerA = makeContainer()
        let containerB = makeContainer()
        let mountA: TerminalMountCoordinator = TerminalView(coordinator: x).makeCoordinator()

        #expect(TerminalMount.attach(x.hostingView, to: containerA) == true)
        #expect(TerminalMount.attach(x.hostingView, to: containerB) == true)
        #expect(x.hostingView.superview === containerB)

        TerminalView.dismantleNSView(containerA, coordinator: mountA)

        #expect(x.hostingView.superview === containerB)
        #expect(containerB.subviews.first === x.hostingView)
        #expect(containerA.subviews.isEmpty)
    }

    @Test("X を A→B、Y を A に載せた後、X の A 再 attach は false で X は B・Y は A のまま")
    func staleReattachOfXDoesNotRemoveYFromA() {
        let terminalX = makeCoordinator()
        let terminalY = makeCoordinator()
        let containerA = makeContainer()
        let containerB = makeContainer()
        #expect(containerA.window == nil)
        #expect(containerB.window == nil)

        #expect(TerminalMount.attach(terminalX.hostingView, to: containerA) == true)
        #expect(TerminalMount.attach(terminalX.hostingView, to: containerB) == true)
        #expect(TerminalMount.attach(terminalY.hostingView, to: containerA) == true)

        let stale = TerminalMount.attach(terminalX.hostingView, to: containerA)

        #expect(stale == false)
        #expect(terminalX.hostingView.superview === containerB)
        #expect(terminalY.hostingView.superview === containerA)
        #expect(containerA.subviews.first === terminalY.hostingView)
        #expect(containerB.subviews.first === terminalX.hostingView)
    }
}
