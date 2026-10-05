import AppKit
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("レビュー追加: 撤去後の再編集・移動・保存・undo", .serialized)
@MainActor
struct MarkdownBlockEditorLifecycleTests {
    static let source = "# 見出し\n\n本文A\n\n本文B\n"

    @Test func editorAttachedAfterInitialUpdateReceivesKeyboardFocus() async throws {
        let id = UUID()
        let view = NSHostingView(rootView: CodeTextEditor(getText: { "本文" }, setText: { _ in }, blockEditID: id,
                                                        requestBlockFocus: true))
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let editor = try #require(editors(in: view).first as? CurrentLineTextView)
        #expect(editor.window == nil)
        #expect(editor.blockEditID == id)
        let window = BlockEditorKeyWindow(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        let container = BlockEditorFocusTarget(frame: view.frame)
        window.contentView = container
        window.orderBack(nil)
        #expect(window.makeFirstResponder(container))
        container.addSubview(view)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(window.isKeyWindow)
        #expect(window.firstResponder === editor)
        let expected = (editor.string as NSString).replacingCharacters(in: editor.selectedRange(), with: "x")
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "x", charactersIgnoringModifiers: "x",
            isARepeat: false, keyCode: 7))
        window.sendEvent(event)
        #expect(editor.string == expected)
    }

    @Test(arguments: [false, true])
    func clickInKeyWindowRoutesCharacterToEditor(usesFileTab: Bool) async throws {
        let (root, _, document, window, view) = try await setUp(keyWindow: true, usesFileTab: usesFileTab)
        defer { window.close(); try? FileManager.default.removeItem(at: root) }
        #expect(window.isKeyWindow)
        try await clickText("本文A", view: view, window: window)
        let editor = try #require(editors(in: view).first as? CurrentLineTextView)
        #expect(editor.blockEditID == document.activeBlockEdit?.id)
        #expect(window.firstResponder === editor)
        let original = editor.string
        let expected = (original as NSString).replacingCharacters(in: editor.selectedRange(), with: "x")
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "x", charactersIgnoringModifiers: "x",
            isARepeat: false, keyCode: 7))
        window.sendEvent(event)
        #expect(editor.string == expected)
        #expect(document.activeBlockEdit?.current == editor.string)
    }

    // 1. Esc → 表示切替なしで同じブロックを再クリック → 入力できる
    @Test func escThenReclickSameBlockInPlace() async throws {
        let (root, file, document, window, view) = try await setUp()
        defer { window.close(); try? FileManager.default.removeItem(at: root) }
        _ = file
        try await clickText("本文A", view: view, window: window)
        let first = try #require(editors(in: view).first)
        #expect(window.firstResponder === first)
        try await escape(window: window, view: view)
        #expect(document.activeBlockEdit == nil)
        #expect(editors(in: view).isEmpty)
        #expect(first.window == nil)
        // 撤去後の空の NSScrollView が見える状態で残っていない
        let emptyVisible = scrollViews(in: view).filter { $0.documentView == nil && $0.window != nil && !$0.isHiddenOrHasHiddenAncestor }
        #expect(emptyVisible.isEmpty)

        try await clickText("本文A", view: view, window: window)
        let all = editors(in: view)
        #expect(all.count == 1)
        let reopened = try #require(all.first as? CurrentLineTextView)
        #expect(reopened !== first)
        #expect(reopened.blockEditID != nil)
        #expect(reopened.blockEditID == document.activeBlockEdit?.id)
        #expect(reopened.enclosingScrollView?.documentView === reopened)
        #expect(reopened.window != nil)
        #expect(reopened.delegate != nil)
        #expect(window.firstResponder === reopened)
        reopened.insertText("追記", replacementRange: NSRange(location: 0, length: 0))
        #expect(document.activeBlockEdit?.current == "追記本文A\n\n")
        try await escape(window: window, view: view)
        #expect(document.draft == "# 見出し\n\n追記本文A\n\n本文B\n")
        #expect(editors(in: view).isEmpty)
    }

    // 2. 再クリック後の2回目の編集欄に対し、delegate を経由しない変更を ⌘S 相当で保存
    @Test func saveAfterReclickUsesLiveSynchronizer() async throws {
        let (root, file, document, window, view) = try await setUp()
        defer { window.close(); try? FileManager.default.removeItem(at: root) }
        try await clickText("本文A", view: view, window: window)
        try await escape(window: window, view: view)
        try await clickText("本文A", view: view, window: window)
        let reopened = try #require(editors(in: view).first)
        reopened.string = "同期A\n\n"  // textDidChange を通さない（IME 確定前と同じく同期閉包だけが頼り）
        _ = try await document.save()
        #expect(try String(contentsOf: file, encoding: .utf8) == "# 見出し\n\n同期A\n\n本文B\n")
    }

    // 3. A 編集中に B をクリック → A の入力が draft に入り、B の区間が正しく選ばれる
    @Test(arguments: [false, true])
    func moveToAnotherBlockKeepsEdit(changesLength: Bool) async throws {
        let (root, file, document, window, view) = try await setUp()
        defer { window.close(); try? FileManager.default.removeItem(at: root) }
        try await clickText("本文A", view: view, window: window)
        let editorA = try #require(editors(in: view).first)
        let newA = changesLength ? "長くした本文A\n\n" : "変更A\n\n"
        editorA.string = newA  // 同期閉包経由でのみ伝わる変更
        try await clickText("本文B", view: view, window: window)
        #expect(document.draft == "# 見出し\n\n\(newA)本文B\n")
        #expect(document.activeBlockEdit?.original == "本文B\n")
        let remaining = editors(in: view)
        #expect(remaining.count == 1)
        #expect(remaining.first?.string == "本文B\n")
        #expect(editorA.window == nil)
        #expect(window.firstResponder === remaining.first)
        _ = try await document.save()
        #expect(try String(contentsOf: file, encoding: .utf8) == "# 見出し\n\n\(newA)本文B\n")
    }

    // 4. undo のレスポンダ: Esc 後は文書の履歴、再編集中は入力欄の履歴（メニューと同じく first responder から undo: を送る）
    @Test func undoRoutingAfterRemoval() async throws {
        let (root, _, document, window, view) = try await setUp()
        defer { window.close(); try? FileManager.default.removeItem(at: root) }
        try await clickText("本文A", view: view, window: window)
        let first = try #require(editors(in: view).first)
        first.insertText("U", replacementRange: NSRange(location: 0, length: 0))
        try await escape(window: window, view: view)
        #expect(document.draft == "# 見出し\n\nU本文A\n\n本文B\n")
        #expect(window.delegate?.windowWillReturnUndoManager?(window) === document.undoManager)
        let responder = try #require(window.firstResponder)
        #expect(!(responder is CurrentLineTextView))
        #expect(responder.tryToPerform(NSSelectorFromString("undo:"), with: nil))
        #expect(document.draft == Self.source)
        #expect(responder.tryToPerform(NSSelectorFromString("redo:"), with: nil))
        #expect(document.draft == "# 見出し\n\nU本文A\n\n本文B\n")

        try await clickText("U本文A", view: view, window: window)
        let reopened = try #require(editors(in: view).first)
        #expect(window.firstResponder === reopened)
        #expect(window.delegate?.windowWillReturnUndoManager?(window) === reopened.undoManager)
        reopened.insertText("V", replacementRange: NSRange(location: 0, length: 0))
        reopened.breakUndoCoalescing()
        #expect(reopened.tryToPerform(NSSelectorFromString("undo:"), with: nil))
        #expect(reopened.string == "U本文A\n\n")
        #expect(document.draft == "# 見出し\n\nU本文A\n\n本文B\n")
    }

    // 5. 編集中のブロックを画面外へスクロール→戻す（dismantle 経路の removeBlockEditor）
    @Test func scrollEditingBlockAwayAndBack() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("document.md")
        let source = (0..<120).map { "段落\($0)\n\n" }.joined()
        try Data(source.utf8).write(to: file)
        let document = FileTabDocument(path: "document.md", root: root.path)
        await document.loadIfNeeded()
        _ = document.setPresentation(.rendered)
        await document.refreshMarkdownAnalysis()
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let view = NSHostingView(rootView: FileTabUndoScope(document: document) {
            MarkdownBlockEditor(document: document, openURL: { _ in .discarded })
        })
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        let window = MarkdownTrackingWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        try await clickText("段落0", view: view, window: window)
        let editor = try #require(editors(in: view).first)
        editor.insertText("追記", replacementRange: NSRange(location: 0, length: 0))
        let outer = try #require(scrollViews(in: view).first { !($0.documentView is NSTextView) })
        let bottom = (outer.documentView?.bounds.height ?? 0) - outer.contentView.bounds.height
        #expect(bottom > 2_000)
        outer.contentView.scroll(to: NSPoint(x: 0, y: bottom))
        outer.reflectScrolledClipView(outer.contentView)
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        #expect(editor.window == nil)
        // 既存挙動（HEAD でも同じ）: 画面外へ出ると確定される。入力は失われず、隠れた入力欄も残らない。
        #expect(document.activeBlockEdit == nil)
        #expect(document.draft.hasPrefix("追記段落0\n\n段落1"))
        outer.contentView.scroll(to: .zero)
        outer.reflectScrolledClipView(outer.contentView)
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        #expect(editors(in: view).isEmpty)
        _ = try await document.save()
        #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix("追記段落0\n\n段落1"))
    }

    // 6. リンクを含む段落: 行末の余白クリックは編集、リンクのクリックは開くだけ
    @Test func linkParagraphBlankAreaEditsAndLinkOpens() async throws {
        let document = FileTabDocument(path: "document.md", root: "/")
        document.draft = "前文 [案内](linked.md) 後文\n"
        var opened: [URL] = []
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let view = NSHostingView(rootView: FileTabUndoScope(document: document) {
            MarkdownBlockEditor(document: document, openURL: { opened.append($0); return .handled })
        })
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        let window = MarkdownTrackingWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        let link = try #require(linkFrame(in: view, text: "案内"))
        try await click(NSPoint(x: link.midX, y: link.midY), view: view, window: window)
        #expect(opened == [URL(string: "linked.md")!])
        #expect(document.activeBlockEdit == nil)
        #expect(editors(in: view).isEmpty)
        try await click(NSPoint(x: window.frame.maxX - 60, y: link.midY), view: view, window: window)
        #expect(opened.count == 1)
        #expect(document.activeBlockEdit?.original == "前文 [案内](linked.md) 後文\n")
        #expect(editors(in: view).count == 1)
    }

    private func linkFrame(in view: NSView, text: String) -> NSRect? {
        var seen = Set<ObjectIdentifier>()
        func value(_ name: String, of object: NSObject) -> Any? {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func visit(_ element: Any) -> NSRect? {
            guard let object = element as? NSObject, seen.insert(ObjectIdentifier(object)).inserted else { return nil }
            let label = value("accessibilityValue", of: object) as? String ?? value("accessibilityLabel", of: object) as? String
            if label == text, value("accessibilityRole", of: object) as? String == NSAccessibility.Role.link.rawValue {
                let frame = (object as AnyObject).accessibilityFrame()
                if !frame.isEmpty { return frame }
            }
            for child in value("accessibilityChildren", of: object) as? [Any] ?? [] { if let f = visit(child) { return f } }
            if let view = element as? NSView { for child in view.subviews { if let f = visit(child) { return f } } }
            return nil
        }
        return visit(view)
    }

    private func click(_ point: NSPoint, view: NSView, window: NSWindow) async throws {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let events = try [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated().map { index, type in
            try #require(NSEvent.mouseEvent(with: type,
                location: window.convertPoint(fromScreen: point), modifierFlags: [],
                timestamp: timestamp + Double(index) * 0.02, windowNumber: window.windowNumber,
                context: nil, eventNumber: index + 1, clickCount: 1, pressure: index == 0 ? 1 : 0))
        }
        try sendMarkdownMouseEvents(events, in: window)
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        ((view as? NSScrollView).map { [$0] } ?? []) + view.subviews.flatMap { scrollViews(in: $0) }
    }

    @Test func escapedBlockMovesWithArrowAndReopensWithReturn() async throws {
        let (root, _, document, window, view) = try await setUp()
        defer { window.close(); try? FileManager.default.removeItem(at: root) }
        try await clickText("本文A", view: view, window: window)
        try await escape(window: window, view: view)
        #expect(window.firstResponder is MarkdownBlockSelectionObserver.SelectionView)
        for (key, characters) in [(UInt16(125), "\u{F701}"), (UInt16(36), "\r")] {
            let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: key))
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(100))
            view.layoutSubtreeIfNeeded()
        }
        let editor = try #require(editors(in: view).first)
        #expect(editor.string == "本文B\n")
        #expect(window.firstResponder === editor)
        #expect(document.activeBlockEdit?.range.lowerBound == Self.source.utf8.count - "本文B\n".utf8.count)
    }

    // MARK: - helpers

    private func setUp(keyWindow: Bool = false, usesFileTab: Bool = false) async throws -> (URL, URL, FileTabDocument, NSWindow, NSView) {
        let root = try makeFileTabTestRoot()
        let file = root.appendingPathComponent("document.md")
        try Data(Self.source.utf8).write(to: file)
        let document = FileTabDocument(path: "document.md", root: root.path)
        await document.loadIfNeeded()
        _ = document.setPresentation(.rendered)
        await document.refreshMarkdownAnalysis()
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let view = NSHostingView(rootView: FileTabUndoScope(document: document) {
            if usesFileTab {
                FileTabView(document: document, lastWriter: { _ in nil }, isFocused: true, openFile: { _, _ in })
            } else {
                MarkdownBlockEditor(document: document, openURL: { _ in .discarded })
            }
        })
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        let window: NSWindow = keyWindow
            ? BlockEditorKeyWindow(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            : MarkdownTrackingWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        return (root, file, document, window, view)
    }

    private func clickText(_ text: String, view: NSView, window: NSWindow) async throws {
        view.layoutSubtreeIfNeeded()
        let frame = try #require(accessibilityFrame(in: view, text: text))
        try await click(NSPoint(x: frame.midX, y: frame.midY), view: view, window: window)
    }

    private func escape(window: NSWindow, view: NSView) async throws {
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: "\u{001B}", charactersIgnoringModifiers: "\u{001B}",
            isARepeat: false, keyCode: 53))
        window.sendEvent(event)
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
    }

    private func editors(in view: NSView) -> [NSTextView] {
        (view as? CurrentLineTextView).map { [$0] } ?? view.subviews.flatMap { editors(in: $0) }
    }

    private func accessibilityFrame(in view: NSView, text: String) -> NSRect? {
        var seen = Set<ObjectIdentifier>()
        func value(_ name: String, of object: NSObject) -> Any? {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector) else { return nil }
            return object.perform(selector)?.takeUnretainedValue()
        }
        func visit(_ element: Any) -> NSRect? {
            guard let object = element as? NSObject,
                  seen.insert(ObjectIdentifier(object)).inserted else { return nil }
            let label = value("accessibilityValue", of: object) as? String
                ?? value("accessibilityLabel", of: object) as? String
            if label == text, object.responds(to: NSSelectorFromString("accessibilityFrame")) {
                let frame = (object as AnyObject).accessibilityFrame()
                if !frame.isEmpty { return frame }
            }
            let children = value("accessibilityChildren", of: object) as? [Any] ?? []
            for child in children { if let frame = visit(child) { return frame } }
            if let view = element as? NSView {
                for child in view.subviews { if let frame = visit(child) { return frame } }
            }
            return nil
        }
        return visit(view)
    }
}

private final class BlockEditorKeyWindow: NSPanel {
    override var mouseLocationOutsideOfEventStream: NSPoint {
        markdownTrackingMouseLocation(in: self) ?? super.mouseLocationOutsideOfEventStream
    }
    override var canBecomeKey: Bool { false }
    // 製品のキーウィンドウ条件を検査し、OS の入力先は変えない。
    override var isKeyWindow: Bool { true }
}

private final class BlockEditorFocusTarget: NSView {
    override var acceptsFirstResponder: Bool { true }
}
