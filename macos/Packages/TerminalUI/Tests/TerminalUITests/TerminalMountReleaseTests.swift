import AppKit
import Testing
@testable import TerminalUI

// グリッドへ切り替えると、一時的な mount が最後に付いてすぐ破棄される。残ったタイル（画面にある A）には
// updateNSView が来ないので、所有者が外れた合図で A が自分から付け直す（06 の端末タイルが空になる不具合）。

@MainActor
@Test func releasedTerminalReattachesToMountStillOnScreen() async {
    let terminal = TerminalCoordinator()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [], backing: .buffered, defer: true)
    let containerA = TerminalMountContainer(frame: window.contentView!.bounds)
    window.contentView!.addSubview(containerA)
    let containerB = NSView(frame: .zero)
    let mountA = TerminalMountCoordinator(current: terminal)
    mountA.observeRelease(for: containerA)
    defer { mountA.stopObservingRelease() }

    #expect(TerminalMount.attach(terminal.hostingView, to: containerA))
    #expect(TerminalMount.attach(terminal.hostingView, to: containerB))
    #expect(TerminalMount.detach(terminal.hostingView, from: containerB))
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

    #expect(terminal.hostingView.superview === containerA)
}

@MainActor
@Test func releasedTerminalDoesNotReattachToMountOffScreen() async {
    let terminal = TerminalCoordinator()
    let containerA = TerminalMountContainer(frame: .zero)
    let containerB = NSView(frame: .zero)
    let mountA = TerminalMountCoordinator(current: terminal)
    mountA.observeRelease(for: containerA)
    defer { mountA.stopObservingRelease() }

    #expect(TerminalMount.attach(terminal.hostingView, to: containerA))
    #expect(TerminalMount.attach(terminal.hostingView, to: containerB))
    #expect(TerminalMount.detach(terminal.hostingView, from: containerB))
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

    #expect(terminal.hostingView.superview == nil)
}

@MainActor
@Test func releasedTerminalIsNotStolenFromMountAttachedWhileWaiting() async {
    let terminal = TerminalCoordinator()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [], backing: .buffered, defer: true)
    let containerA = TerminalMountContainer(frame: window.contentView!.bounds)
    window.contentView!.addSubview(containerA)
    let containerB = NSView(frame: .zero)
    let containerC = NSView(frame: .zero)
    let mountA = TerminalMountCoordinator(current: terminal)
    mountA.observeRelease(for: containerA)
    defer { mountA.stopObservingRelease() }

    #expect(TerminalMount.attach(terminal.hostingView, to: containerA))
    #expect(TerminalMount.attach(terminal.hostingView, to: containerB))
    #expect(TerminalMount.detach(terminal.hostingView, from: containerB))
    #expect(TerminalMount.attach(terminal.hostingView, to: containerC))
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

    #expect(terminal.hostingView.superview === containerC)
}

@MainActor
@Test func releasedTerminalReattachesWhenMountLaterMovesOnScreen() async {
    let terminal = TerminalCoordinator()
    let containerA = TerminalMountContainer(frame: .zero)
    let containerB = NSView(frame: .zero)
    let mountA = TerminalMountCoordinator(current: terminal)
    mountA.observeRelease(for: containerA)
    defer { mountA.stopObservingRelease() }

    #expect(TerminalMount.attach(terminal.hostingView, to: containerA))
    #expect(TerminalMount.attach(terminal.hostingView, to: containerB))
    #expect(TerminalMount.detach(terminal.hostingView, from: containerB))
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
    #expect(terminal.hostingView.superview == nil)

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [], backing: .buffered, defer: true)
    window.contentView!.addSubview(containerA)
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

    #expect(terminal.hostingView.superview === containerA)
}

@MainActor
@Test func terminalReplacedInReusedContainerReattachesToMountStillOnScreen() async {
    let terminalX = TerminalCoordinator()
    let terminalY = TerminalCoordinator()
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [], backing: .buffered, defer: true)
    let containerA = TerminalMountContainer(frame: window.contentView!.bounds)
    window.contentView!.addSubview(containerA)
    let reused = NSView(frame: .zero)
    let mountA = TerminalMountCoordinator(current: terminalX)
    mountA.observeRelease(for: containerA)
    defer { mountA.stopObservingRelease() }

    #expect(TerminalMount.attach(terminalX.hostingView, to: containerA))
    #expect(TerminalMount.attach(terminalX.hostingView, to: reused))
    #expect(TerminalMount.attach(terminalY.hostingView, to: reused))
    await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }

    #expect(terminalX.hostingView.superview === containerA)
    #expect(terminalY.hostingView.superview === reused)
}
