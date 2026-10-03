import AppKit
import SwiftUI
import AgentDomain

/// 信号（閉じる・しまう・拡大）を 52pt のツールバーの縦中央に揃えるため、空の NSToolbar を付けて
/// タイトルバーを unified の高さにする。ツールバーの中身は SwiftUI 側で描く（01 A1）。
struct WindowChromeConfigurator: NSViewRepresentable {
    @Environment(\.locale) private var locale
    var files: FileTabDocuments? = nil
    var fileContext: (SessionID) -> UnsavedFileContext = { _ in UnsavedFileContext() }
    var projectName: () -> String = { "" }

    func makeNSView(context: Context) -> NSView {
        let view = ChromeView()
        view.files = files
        view.fileContext = fileContext
        view.projectName = projectName
        view.locale = locale
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? ChromeView else { return }
        view.files = files
        view.fileContext = fileContext
        view.projectName = projectName
        view.locale = locale
        view.registerFiles()
    }

    private final class ChromeView: NSView {
        weak var files: FileTabDocuments?
        var fileContext: (SessionID) -> UnsavedFileContext = { _ in UnsavedFileContext() }
        var projectName: () -> String = { "" }
        var locale = Locale(identifier: "ja")

        func registerFiles() {
            guard let window, let files else { return }
            FileTabDocumentRegistry.shared.register(files: files, window: window, context: fileContext, name: projectName, locale: locale)
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
