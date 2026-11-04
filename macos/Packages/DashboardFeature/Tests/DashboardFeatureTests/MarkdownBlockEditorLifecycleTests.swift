import AppKit
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("レビュー追加: 撤去後の再編集・移動・保存・undo", .serialized)
@MainActor
struct MarkdownBlockEditorLifecycleTests {
    static let source = "# 見出し\n\n本文A\n\n本文B\n"

    @Test("操作ロックの解除後も実際の編集欄で入力をUndoできる", arguments: [false, true])
    func fileOperationPreservesEditorUndo(sourceEditor: Bool) async throws {
        let (root, _, document, window, view) = try await setUp(usesFileTab: sourceEditor)
        defer { window.close(); try? FileManager.default.removeItem(at: root) }
        if sourceEditor {
            #expect(document.setPresentation(.source))
            try await Task.sleep(for: .milliseconds(100))
            view.layoutSubtreeIfNeeded()
        } else {
            try await clickText("本文A", view: view, window: window)
        }
        let editor = try #require(editors(in: view).first as? CurrentLineTextView)
        let before = editor.string
        editor.insertText("X", replacementRange: NSRange(location: 0, length: 0))
        editor.breakUndoCoalescing()
        #expect(editor.undoManager?.canUndo == true)
        for locked in [true, false] {
            document.fileOperationInProgress = locked
            try await Task.sleep(for: .milliseconds(100))
            view.layoutSubtreeIfNeeded()
            #expect(editor.isEditable == !locked)
            #expect(editor.string == "X" + before)
            if locked { #expect(editor.undoManager == nil) }
        }
        #expect(editor.undoManager?.canUndo == true)
        editor.undo(nil)
        #expect(editor.string == before)
        #expect(editor.undoManager?.canRedo == true)
        editor.redo(nil)
        #expect(editor.string == "X" + before)
    }

    @Test("恒久的な編集可否の切替では従来どおりUndo履歴を消す")
    func readOnlyTransitionClearsEditorUndo() async throws {
        var text = "本文"
        func content(editable: Bool) -> CodeTextEditor {
            CodeTextEditor(getText: { text }, setText: { text = $0 }, isEditable: editable)
        }
        let view = NSHostingView(rootView: content(editable: true))
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        view.layoutSubtreeIfNeeded()
        let editor = try #require(editors(in: view).first as? CurrentLineTextView)
        editor.insertText("X", replacementRange: NSRange(location: 0, length: 0))
        editor.breakUndoCoalescing()
        #expect(editor.undoManager?.canUndo == true)
        for editable in [false, true] {
            view.rootView = content(editable: editable)
            try await Task.sleep(for: .milliseconds(100))
            view.layoutSubtreeIfNeeded()
            #expect(editors(in: view).first === editor)
            #expect(editor.isEditable == editable)
            #expect(editor.allowsUndo == editable)
        }
        #expect(editor.undoManager?.canUndo == false)
        #expect(editor.string == "X本文")
    }

    @Test("ファイル操作中は実際のブロック編集欄が編集不可になり未確定入力を保持する")
    func fileOperationDisablesBlockEditor() async throws {
        let (root, _, document, window, view) = try await setUp()
        defer { window.close(); try? FileManager.default.removeItem(at: root) }
        try await clickText("本文A", view: view, window: window)
        let editor = try #require(editors(in: view).first as? CurrentLineTextView)
        #expect(editor.isEditable)
        // NSTextView 内に残る未確定入力をロック前に文書へ同期する。
        editor.string = "同期前の入力"
        document.synchronizeActiveBlockEditor?()
        #expect(document.activeBlockEdit?.current == "同期前の入力")
        document.fileOperationInProgress = true
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(!editor.isEditable)
        #expect(editor.string == "同期前の入力")
        #expect(document.activeBlockEdit?.current == "同期前の入力")
        document.fileOperationInProgress = false
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(editor.isEditable)
        #expect(editor.string == "同期前の入力")
    }

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
        #expect(reopened.undoManager?.canUndo == false)
        reopened.insertText("V", replacementRange: NSRange(location: 0, length: 0))
        reopened.breakUndoCoalescing()
        #expect(reopened.tryToPerform(NSSelectorFromString("undo:"), with: nil))
        #expect(reopened.string == "U本文A\n\n")
        #expect(document.draft == "# 見出し\n\nU本文A\n\n本文B\n")
    }

    @Test("文書の中ほどに段落を挿入した後も隣の段落を再編集できUndoで原文へ戻れる")
    func insertingParagraphsInTheMiddlePreservesNeighborEditingAndDocumentUndo() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("document.md")
        let source = (0..<60).map { "段落\($0)\n\n" }.joined()
        try Data(source.utf8).write(to: file)
        let document = FileTabDocument(path: "document.md", root: root.path)
        await document.loadIfNeeded()
        #expect(document.setPresentation(.rendered))
        await document.refreshMarkdownAnalysis()
        let app = NSApplication.shared
        let attribute = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        let previousAccessibility = app.perform(NSSelectorFromString("accessibilityAttributeValue:"), with: attribute.rawValue)?.takeUnretainedValue()
        app.accessibilitySetValue(true, forAttribute: attribute)
        defer { app.accessibilitySetValue(previousAccessibility, forAttribute: attribute) }
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
        try await scrollTextIntoView("段落30", view: view, window: window)

        try await clickText("段落30", view: view, window: window)
        let editor = try #require(editors(in: view).first)
        #expect(editor.string == "段落30\n\n")
        editor.insertText("\n\n追加した段落A\n\n追加した段落B", replacementRange: NSRange(location: 4, length: 0))
        try await escape(window: window, view: view)
        #expect(document.activeBlockEdit == nil)
        #expect(editors(in: view).isEmpty)
        #expect(document.draft.contains("段落29\n\n段落30\n\n追加した段落A\n\n追加した段落B\n\n段落31\n\n段落32\n\n"))
        try await scrollTextIntoView("段落31", view: view, window: window)
        try await clickText("段落31", view: view, window: window)
        let neighbor = try #require(editors(in: view).first)
        #expect(neighbor.string == "段落31\n\n")
        try await escape(window: window, view: view)
        #expect(document.activeBlockEdit == nil)
        #expect(editors(in: view).isEmpty)
        let responder = try #require(window.firstResponder)
        #expect(!(responder is CurrentLineTextView))
        #expect(responder.tryToPerform(NSSelectorFromString("undo:"), with: nil))
        #expect(document.draft == source)
    }

    @Test("段落と表のある長い文書を大きくスクロールしても表示範囲に本文が残る")
    func largeScrollKeepsMarkdownBodyVisible() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("document.md")
        let source = [2, 9, 3, 7, 1, 5].enumerated().map { section, length in
            let paragraph = String(repeating: "長い説明が折り返されても、前後の文章を読み続けられます。", count: length)
            let tableRows = (0..<(length + 2)).map {
                "| 表本文\(section)-\($0) | セルの文章は幅に合わせて折り返し、行ごとに異なる高さを持ちます。 |\n"
            }.joined()
            let bullets = (0..<length).map {
                "- 本文段落\(section)の項目\($0)には、表示幅に収まらない長さの説明を添えて折り返しを確かめます。\n"
            }.joined()
            let code = (0..<(length * 3)).map { "let value\(section)_\($0) = \($0)\n" }.joined()
            let numbered = (0..<(length + 1)).map {
                "\($0 + 1). 後続本文\(section)の手順\($0)を読み、次の項目へ進んでも本文の表示を保ちます。\n"
            }.joined()
            return "## 節\(section)\n\n本文段落\(section)の短文です。\n\n---\n\n"
                + "本文段落\(section)の長文です。\(paragraph)\n\n"
                + "| 項目 | 説明 |\n| --- | --- |\n\(tableRows)\n"
                + "後続本文\(section)の短文です。\n\n\(bullets)\n---\n\n"
                + "```swift\n\(code)```\n\n\(numbered)\n本文段落\(section)の結びです。\n\n"
        }.joined() + "## 末尾\n\n本文段落の末尾です。\n\n- 後続本文の終わりです。\n"
        try Data(source.utf8).write(to: file)
        let document = FileTabDocument(path: "document.md", root: root.path)
        await document.loadIfNeeded()
        #expect(document.setPresentation(.rendered))
        await document.refreshMarkdownAnalysis()
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
        try await waitUntil {
            view.layoutSubtreeIfNeeded()
            guard let scroll = scrollViews(in: view).first(where: {
                $0.hasVerticalScroller && !($0.documentView is NSTextView)
            }) else { return false }
            return !visibleMarkdownBody(in: view, scroll: scroll).isEmpty
        }
        let scroll = try #require(scrollViews(in: view).first {
            $0.hasVerticalScroller && !($0.documentView is NSTextView)
        })
        let initialBody = Set(visibleMarkdownBody(in: view, scroll: scroll))
        let target = scroll.contentView.bounds.height * 10

        try await waitUntil {
            view.layoutSubtreeIfNeeded()
            guard let content = scroll.documentView else { return false }
            let maximum = max(0, content.bounds.height - scroll.contentView.bounds.height)
            let next = scroll.contentView.bounds.minY + scroll.contentView.bounds.height / 2
            scroll.contentView.scroll(to: NSPoint(x: 0, y: min(target, next, maximum)))
            scroll.reflectScrolledClipView(scroll.contentView)
            view.layoutSubtreeIfNeeded()
            let visible = Set(visibleMarkdownBody(in: view, scroll: scroll))
            return scroll.contentView.bounds.minY >= target - 1
                && !visible.isEmpty && visible.isDisjoint(with: initialBody)
        }

        let content = try #require(scroll.documentView)
        let visibleBody = Set(visibleMarkdownBody(in: view, scroll: scroll))
        #expect(content.bounds.height - scroll.contentView.bounds.height > target)
        #expect(scroll.contentView.bounds.minY >= target - 1)
        #expect(!visibleBody.isEmpty)
        #expect(visibleBody.isDisjoint(with: initialBody))
        #expect(document.draft == source)
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

    private func visibleMarkdownBody(in view: NSView, scroll: NSScrollView) -> [String] {
        if let field = view as? NSTextField,
           !field.isHiddenOrHasHiddenAncestor,
           !field.visibleRect.isEmpty,
           field.convert(field.bounds, to: scroll.contentView).intersects(scroll.contentView.bounds),
           field.stringValue.hasPrefix("本文段落") || field.stringValue.hasPrefix("後続本文")
            || field.stringValue.hasPrefix("表本文") || field.stringValue.hasPrefix("let value") {
            return [field.stringValue]
        }
        return view.subviews.flatMap { visibleMarkdownBody(in: $0, scroll: scroll) }
    }

    private func scrollTextIntoView(_ text: String, view: NSView, window: NSWindow, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await waitUntil({
            view.layoutSubtreeIfNeeded()
            guard let outer = scrollViews(in: view).first, let content = outer.documentView else { return false }
            let maximum = max(0, content.bounds.height - outer.contentView.bounds.height)
            var next = min(maximum, outer.contentView.bounds.minY + outer.contentView.bounds.height / 2)
            if let frame = accessibilityFrame(in: view, text: text) {
                let point = window.convertPoint(fromScreen: NSPoint(x: frame.midX, y: frame.midY))
                if outer.contentView.bounds.contains(outer.contentView.convert(point, from: nil)) { return true }
                next = min(maximum, max(0, content.convert(point, from: nil).y - outer.contentView.bounds.height / 2))
            }
            outer.contentView.scroll(to: NSPoint(x: 0, y: next))
            outer.reflectScrolledClipView(outer.contentView)
            return false
        }, sourceLocation: sourceLocation)
    }

    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), sourceLocation: sourceLocation)
    }

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
