import AppKit
import TerminalUI
import Testing

@MainActor
@Suite("パッケージ境界を越えた端末フォントの参照")
struct TerminalFontAccessTests {
    @Test("フォント変更とウィンドウの再接続後も実サイズを取得できる")
    func fontAcrossWindowAttachments() {
        _ = NSApplication.shared
        let coordinator = TerminalCoordinator(palette: .phloxDefault)
        let view = coordinator.terminalView
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 480),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }

        for size: CGFloat in [11, 13, 20] {
            coordinator.applyFontSize(size)
            #expect(view.font.pointSize == size)
            window.contentView = view
            view.layoutSubtreeIfNeeded()
            #expect(view.window === window)
            #expect(view.font.pointSize == size)
            window.contentView = nil
            #expect(view.window == nil)
            #expect(view.font.pointSize == size)
        }
    }
}
