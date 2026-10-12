import AppKit
import SwiftUI
import AgentDomain

/// SwiftUI のヘッダーをタイトルバーまで描く。空の NSToolbar は内容を覆うため付けない。
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
            guard let window else { return }
            window.toolbarStyle = .unifiedCompact
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
        }
    }
}
