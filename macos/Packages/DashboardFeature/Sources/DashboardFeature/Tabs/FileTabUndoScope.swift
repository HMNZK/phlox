import AppKit
import SwiftUI

/// ウィンドウの既存 delegate とファイルの履歴の仲介を、撤去時にもつなぎ直す。
protocol FileTabWindowDelegateChain: NSWindowDelegate {
    var original: (any NSWindowDelegate)? { get set }
}

@MainActor
func fileTabWindowDelegateChainContains(_ target: any NSWindowDelegate, in head: (any NSWindowDelegate)?) -> Bool {
    var delegate = head
    while let current = delegate {
        if current === target { return true }
        delegate = (current as? any FileTabWindowDelegateChain)?.original
    }
    return false
}

/// 読み取り専用の SwiftUI 環境値ではなく、表示中の responder から文書の履歴を返す。
struct FileTabUndoScope<Content: View>: NSViewRepresentable {
    let document: FileTabDocument
    var isFocused = true
    @ViewBuilder var content: () -> Content
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    func makeNSView(context: Context) -> DocumentHostingView<AnyView> {
        DocumentHostingView(rootView: rootView, document: document, isFocused: isFocused)
    }

    func updateNSView(_ view: DocumentHostingView<AnyView>, context: Context) {
        view.document = document
        view.isFocused = isFocused
        view.rootView = rootView
    }

    private var rootView: AnyView {
        AnyView(content().environment(\.locale, locale).environment(\.colorScheme, colorScheme))
    }
}

/// NSHostingView のメニュー検証は上書きできないため、親の NSView で履歴を受け持つ。
final class DocumentHostingView<Content: View>: NSView, NSUserInterfaceValidations {
    var document: FileTabDocument
    var isFocused: Bool
    private let hosting: NSHostingView<Content>
    private var undoDelegate: FileTabWindowUndoDelegate?
    var rootView: Content {
        get { hosting.rootView }
        set { hosting.rootView = newValue }
    }
    override var undoManager: UndoManager? { document.undoManager }
    override var acceptsFirstResponder: Bool { true }

    @objc func undo(_ sender: Any?) { document.undoManager.undo() }
    @objc func redo(_ sender: Any?) { document.undoManager.redo() }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(undo(_:)) { return document.undoManager.canUndo }
        if item.action == #selector(redo(_:)) { return document.undoManager.canRedo }
        return hosting.validateUserInterfaceItem(item)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let undoDelegate {
            if window?.delegate === undoDelegate { window?.delegate = undoDelegate.original }
            else {
                var delegate = window?.delegate as? any FileTabWindowDelegateChain
                while let current = delegate {
                    if current.original === undoDelegate {
                        current.original = undoDelegate.original
                        break
                    }
                    delegate = current.original as? any FileTabWindowDelegateChain
                }
            }
        }
        undoDelegate = nil
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let delegate = undoDelegate ?? FileTabWindowUndoDelegate(scope: self, original: nil,
            isFocused: { [weak self] in self?.isFocused == true }) { [weak self] in
            self?.document.undoManager
        }
        guard !fileTabWindowDelegateChainContains(delegate, in: window.delegate) else { return }
        delegate.original = window.delegate
        undoDelegate = delegate
        window.delegate = delegate
    }

    init(rootView: Content, document: FileTabDocument, isFocused: Bool = true) {
        self.document = document
        self.isFocused = isFocused
        hosting = NSHostingView(rootView: rootView)
        super.init(frame: .zero)
        hosting.sizingOptions = []
        hosting.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.topAnchor.constraint(equalTo: topAnchor),
            hosting.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) は使用できません") }
}

/// NSWindow 自身が undo: を受けた場合も、入力欄または文書の履歴を使う。
private final class FileTabWindowUndoDelegate: NSObject, FileTabWindowDelegateChain {
    weak var original: (any NSWindowDelegate)?
    private weak var scope: NSView?
    private let documentManager: @MainActor () -> UndoManager?
    private let isFocused: @MainActor () -> Bool

    init(scope: NSView, original: (any NSWindowDelegate)?, isFocused: @escaping @MainActor () -> Bool,
         documentManager: @escaping @MainActor () -> UndoManager?) {
        self.scope = scope
        self.original = original
        self.documentManager = documentManager
        self.isFocused = isFocused
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        var responder = window.firstResponder
        while let current = responder, current !== window {
            if let editor = current as? CurrentLineTextView { return editor.undoManager }
            if current === scope { return documentManager() }
            responder = current.nextResponder
        }
        if window.firstResponder === window || window.firstResponder == nil {
            // 表示順ではなく、左右のうち操作中の区画の文書を優先する。
            var delegate: (any NSWindowDelegate)? = self
            while let current = delegate {
                if let fileDelegate = current as? FileTabWindowUndoDelegate, fileDelegate.isFocused() {
                    return fileDelegate.documentManager()
                }
                delegate = (current as? any FileTabWindowDelegateChain)?.original
            }
            return documentManager()
        }
        return original?.windowWillReturnUndoManager?(window)
    }

    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || original?.responds(to: selector) == true
    }

    override func forwardingTarget(for selector: Selector!) -> Any? {
        original?.responds(to: selector) == true ? original : super.forwardingTarget(for: selector)
    }
}
