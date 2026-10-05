import AppKit
import SwiftUI
import Testing
@testable import DashboardFeature

@MainActor
struct FileTabUndoScopeTests {
    @Test(arguments: [true, false])
    func reinstallingWindowDelegatesKeepsAnAcyclicChain(registryFirst: Bool) throws {
        let document = try committedDocument(path: "a.md")
        let hosting = DocumentHostingView(rootView: Text("文書"), document: document)
        let files = FileTabDocuments()
        let registry = FileTabDocumentRegistry()
        let original = OriginalFileWindowDelegate()
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        window.delegate = original
        defer { window.close() }
        if registryFirst { registry.register(files: files, window: window) }
        container.addSubview(hosting)
        if !registryFirst { registry.register(files: files, window: window) }
        let head = try #require(window.delegate)
        for _ in 0..<3 {
            if registryFirst {
                registry.register(files: files, window: window)
                hosting.viewDidMoveToWindow()
            } else {
                hosting.viewDidMoveToWindow()
                registry.register(files: files, window: window)
            }
            #expect(window.delegate === head)
            #expect(head.responds(to: #selector(NSWindowDelegate.windowDidResize(_:))))
            #expect(!head.responds(to: NSSelectorFromString("unimplementedFileTabDelegateMethod:")))
        }
        head.windowDidResize?(Notification(name: NSWindow.didResizeNotification, object: window))
        #expect(original.resizeCount == 1)
        #expect(window.makeFirstResponder(window))
        #expect(window.undoManager === document.undoManager)
    }

    @Test(arguments: [true, false])
    func windowUndoUsesFocusedFilePane(focusesRight: Bool) throws {
        let left = try committedDocument(path: "left.md")
        let right = try committedDocument(path: "right.md")
        let leftView = DocumentHostingView(rootView: Text("左"), document: left, isFocused: !focusesRight)
        let rightView = DocumentHostingView(rootView: Text("右"), document: right, isFocused: focusesRight)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.close() }
        container.addSubview(leftView)
        container.addSubview(rightView)
        #expect(window.makeFirstResponder(window))
        let focused = focusesRight ? right : left
        let other = focusesRight ? left : right
        #expect(window.undoManager === focused.undoManager)
        #expect(window.tryToPerform(NSSelectorFromString("undo:"), with: nil))
        #expect(focused.draft == "元")
        #expect(other.draft == "変更")
        #expect(window.tryToPerform(NSSelectorFromString("redo:"), with: nil))
        #expect(focused.draft == "変更")
        // 表示後に操作中の側が変わった場合も、その時点の選択を使う。
        leftView.isFocused.toggle()
        rightView.isFocused.toggle()
        #expect(window.undoManager === other.undoManager)
        #expect(window.tryToPerform(NSSelectorFromString("undo:"), with: nil))
        #expect(other.draft == "元")
        #expect(focused.draft == "変更")
    }

    @Test(arguments: [true, false])
    func windowUndoUsesOnlyFilePane(isFocused: Bool) throws {
        let document = try committedDocument(path: "only.md")
        let hosting = DocumentHostingView(rootView: Text("文書"), document: document, isFocused: isFocused)
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        let window = NSWindow(contentRect: container.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = container
        defer { window.close() }
        container.addSubview(hosting)
        container.addSubview(NSView())
        #expect(window.makeFirstResponder(window))
        #expect(window.undoManager === document.undoManager)
        #expect(window.tryToPerform(NSSelectorFromString("undo:"), with: nil))
        #expect(document.draft == "元")
        #expect(window.tryToPerform(NSSelectorFromString("redo:"), with: nil))
        #expect(document.draft == "変更")
    }

    private func committedDocument(path: String) throws -> FileTabDocument {
        let document = FileTabDocument(path: path, root: "/tmp")
        document.draft = "元"
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        document.updateActiveBlockEdit(id: try #require(document.activeBlockEdit?.id), current: "変更")
        #expect(document.commitActiveBlockEdit())
        return document
    }

    @Test(arguments: ["a.swift", "a.txt", "a.html", "a.md"])
    func sourceMenuUndoAndRedo(path: String) throws {
        try menuUndoAndRedo(path: path, blockEditing: false)
    }

    @Test func blockMenuUndoAndRedo() throws {
        try menuUndoAndRedo(path: "a.md", blockEditing: true)
    }

    @Test(arguments: [false, true])
    func inputResponderUndoAndRedoWithoutWindowDelegate(blockEditing: Bool) throws {
        try menuUndoAndRedo(path: "a.md", blockEditing: blockEditing, useInputResponder: true)
    }

    private func menuUndoAndRedo(path: String, blockEditing: Bool, useInputResponder: Bool = false) throws {
        let document = FileTabDocument(path: path, root: "/")
        document.draft = "元"
        #expect(document.setPresentation(.source))
        if blockEditing { #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count)) }
        let getText = { blockEditing ? (document.activeBlockEdit?.current ?? document.draft) : document.draft }
        let content = CodeTextEditor(
            getText: getText, setText: {
            if blockEditing, let id = document.activeBlockEdit?.id { document.updateActiveBlockEdit(id: id, current: $0) }
            else { document.draft = $0 }
        }, blockEditID: document.activeBlockEdit?.id,
            synchronizeBlockEdit: { document.updateActiveBlockEdit(id: $0, current: $1) },
            commitBlockEdit: { document.commitActiveBlockEdit(id: $0) })
            .frame(width: 300, height: 200)
        let hosting = DocumentHostingView(rootView: content, document: document)
        hosting.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        func findEditor(_ view: NSView) -> CurrentLineTextView? {
            if let editor = view as? CurrentLineTextView { return editor }
            return view.subviews.lazy.compactMap(findEditor).first
        }
        let editor = try #require(findEditor(hosting))
        if useInputResponder { window.delegate = nil }
        #expect(window.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.insertText("字", replacementRange: editor.selectedRange())
        #expect(editor.string == "元字")
        #expect(getText() == "元字")
        if blockEditing { #expect(document.draft == "元") }
        editor.breakUndoCoalescing()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        let undo = NSMenuItem(title: "取り消す", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = NSMenuItem(title: "やり直す", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        #expect(editor.validateUserInterfaceItem(undo))
        #expect(!editor.validateUserInterfaceItem(redo))
        #expect((useInputResponder ? editor : window).tryToPerform(undo.action!, with: nil))
        #expect(editor.string == "元")
        #expect(getText() == "元")
        #expect(editor.validateUserInterfaceItem(redo))
        #expect((useInputResponder ? editor : window).tryToPerform(redo.action!, with: nil))
        #expect(editor.string == "元字")
        #expect(getText() == "元字")
        if blockEditing { #expect(document.draft == "元") }
    }

    @Test("表示中のファイルタブから文書の undo 履歴を返す", arguments: [true, false])
    func hostingViewUsesDocumentHistory(focusHosting: Bool) throws {
        try documentUndoAndRedo(focusHosting: focusHosting)
    }

    @Test func documentResponderUndoAndRedoWithoutWindowDelegate() throws {
        try documentUndoAndRedo(focusHosting: true, useDocumentResponder: true)
    }

    private func documentUndoAndRedo(focusHosting: Bool, useDocumentResponder: Bool = false) throws {
        let document = FileTabDocument(path: "a.md", root: "/tmp")
        document.draft = "元"
        #expect(document.beginBlockEdit(range: 0..<document.draft.utf8.count))
        let id = try #require(document.activeBlockEdit?.id)
        document.updateActiveBlockEdit(id: id, current: "変更")
        #expect(document.commitActiveBlockEdit())
        let hosting = DocumentHostingView(rootView: Text("文書"), document: document)
        #expect(hosting.undoManager === document.undoManager)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        if useDocumentResponder { window.delegate = nil }
        defer { window.close() }
        #expect(window.makeFirstResponder(focusHosting ? hosting : nil))
        let undo = NSMenuItem(title: "取り消す", action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = NSMenuItem(title: "やり直す", action: NSSelectorFromString("redo:"), keyEquivalent: "Z")
        #expect(hosting.validateUserInterfaceItem(undo))
        #expect(!hosting.validateUserInterfaceItem(redo))
        #expect((useDocumentResponder ? hosting : window).tryToPerform(undo.action!, with: nil))
        #expect(document.draft == "元")
        #expect(hosting.validateUserInterfaceItem(redo))
        #expect((useDocumentResponder ? hosting : window).tryToPerform(redo.action!, with: nil))
        #expect(document.draft == "変更")
    }
}

@MainActor
private final class OriginalFileWindowDelegate: NSObject, NSWindowDelegate {
    var resizeCount = 0

    func windowDidResize(_ notification: Notification) { resizeCount += 1 }
}
