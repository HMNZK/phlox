import AppKit
import SwiftUI

/// 信号（閉じる・しまう・拡大）を 52pt のツールバーの縦中央に揃えるため、空の NSToolbar を付けて
/// タイトルバーを unified の高さにする。ツールバーの中身は SwiftUI 側で描く（01 A1）。
struct WindowChromeConfigurator: NSViewRepresentable {
    var files: FileTabDocuments? = nil

    func makeNSView(context: Context) -> NSView {
        let view = ChromeView()
        view.files = files
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ChromeView else { return }
        view.files = files
        view.registerFiles()
    }

    private final class ChromeView: NSView {
        weak var files: FileTabDocuments?

        func registerFiles() {
            guard let window, let files else { return }
            FileTabDocumentRegistry.shared.register(files: files, window: window)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            registerFiles()
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
