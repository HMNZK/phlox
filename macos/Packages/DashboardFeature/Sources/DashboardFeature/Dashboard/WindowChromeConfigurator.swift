import AppKit
import SwiftUI

/// 信号（閉じる・しまう・拡大）を 52pt のツールバーの縦中央に揃えるため、空の NSToolbar を付けて
/// タイトルバーを unified の高さにする。ツールバーの中身は SwiftUI 側で描く（01 A1）。
struct WindowChromeConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ChromeView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ChromeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.toolbar == nil else { return }
            let toolbar = NSToolbar(identifier: "phlox.main")
            toolbar.displayMode = .iconOnly
            window.toolbar = toolbar
            window.toolbarStyle = .unified
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
        }
    }
}
