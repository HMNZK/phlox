import AppKit
import Testing
@testable import TerminalUI

@MainActor
@Suite struct TerminalCoreGraphicsTests {
    @Test("接続・再接続後もCoreGraphicsと全角を含む内容を維持する")
    func coreGraphicsAcrossWindowAttachments() {
        _ = NSApplication.shared
        let coordinator = TerminalCoordinator(palette: .phloxDefault)
        let view = coordinator.terminalView
        coordinator.feed(Data("ASCII 日本語 0123456789".utf8))
        #expect(!view.isUsingMetalRenderer)

        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 480),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }

        for _ in 0..<2 {
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            #expect(view.window === window)
            #expect(!view.isUsingMetalRenderer)
            #expect(coordinator.visibleText().contains("ASCII 日本語 0123456789"))
            window.contentView = nil
            #expect(view.window == nil)
            #expect(!view.isUsingMetalRenderer)
        }
    }
}
