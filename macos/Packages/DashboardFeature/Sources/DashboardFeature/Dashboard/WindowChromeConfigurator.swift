import AppKit
import SwiftUI
import AgentDomain

/// 信号（閉じる・しまう・拡大）を 38pt のツールバーの縦中央に揃えるため、空の NSToolbar を付ける。
/// ツールバーの中身は SwiftUI 側で描く（12 Header and Usage Bar）。
struct WindowChromeConfigurator: NSViewRepresentable {
    @Environment(\.locale) private var locale
    var files: FileTabDocuments? = nil
    var fileContext: (ProjectID) -> UnsavedFileContext = { _ in UnsavedFileContext() }
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
        var fileContext: (ProjectID) -> UnsavedFileContext = { _ in UnsavedFileContext() }
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
            window.toolbarStyle = .unifiedCompact
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
        }
    }
}
