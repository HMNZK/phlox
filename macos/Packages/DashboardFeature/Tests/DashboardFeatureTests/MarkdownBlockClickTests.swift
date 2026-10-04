import AppKit
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("画面に出さないマークダウンのクリック", .serialized)
@MainActor
struct MarkdownBlockClickTests {
    @Test
    func rightClickHitTestingReachesSelectableText() async throws {
        let document = FileTabDocument(path: "selection.md", root: "/")
        document.draft = "本文を右クリック\n"
        let (window, view) = makeWindow(document: document, usesUndoScope: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(50))
        view.layoutSubtreeIfNeeded()
        let frame = try #require(accessibilityFrame(in: view, text: "本文を右クリック"))
        let point = window.convertPoint(fromScreen: NSPoint(x: frame.minX + 8, y: frame.midY))
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown,
            location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        try sendMarkdownMouseEvents([event], in: window, inspect: {
            let parent = try #require(view.superview)
            let target = view.hitTest(parent.convert(point, from: nil))
            let field = try #require(target as? NSTextField)
            #expect(field.isSelectable)
            #expect(field.stringValue == "本文を右クリック")
        })
        #expect(document.activeBlockEdit == nil)
    }

    @Test
    func doubleClickSelectsAWordWithoutBeginningAnEdit() async throws {
        let document = FileTabDocument(path: "selection.md", root: "/")
        document.draft = "selectable words\n"
        let (window, view) = makeWindow(document: document, usesUndoScope: true)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(50))
        view.layoutSubtreeIfNeeded()
        let frame = try #require(accessibilityFrame(in: view, text: "selectable words"))
        let point = window.convertPoint(fromScreen: NSPoint(x: frame.minX + 8, y: frame.midY))
        let events = try [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated().map { index, type in
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + Double(index) * 0.02,
                windowNumber: window.windowNumber, context: nil, eventNumber: index + 1,
                clickCount: 2, pressure: index == 0 ? 1 : 0))
        }
        try sendMarkdownMouseEvents(events, in: window)
        try await Task.sleep(for: .milliseconds(50))
        let selection = try #require(window.firstResponder as? NSTextView)
        #expect(selection.isFieldEditor)
        #expect(selection.selectedRange() == NSRange(location: 0, length: 10))
        #expect(selection.textStorage?.attributedSubstring(from: selection.selectedRange()).string == "selectable")
        #expect(document.activeBlockEdit == nil)
    }

    @Test
    func paragraphTextCanBeSelectedWithoutBeginningAnEdit() async throws {
        let document = FileTabDocument(path: "selection.md", root: "/")
        document.draft = "段落の文字を選択してコピーできます\n\n次の段落\n"
        let (window, view) = makeWindow(document: document, usesUndoScope: true)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(50))
        view.layoutSubtreeIfNeeded()
        func textFields(in view: NSView) -> [NSTextField] {
            (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { textFields(in: $0) }
        }
        let field = try #require(textFields(in: view).first { $0.stringValue == "段落の文字を選択してコピーできます" })
        #expect(field.isSelectable)
        #expect(!field.isEditable)
        // NSTextView.mouseDown は実イベントの tracking loop を起動するため使わない。
        // 描画された段落の選択用エディタへ直接、ブロック内の選択範囲を渡す。
        field.selectText(nil)
        let selection = try #require(field.currentEditor() as? NSTextView)
        selection.setSelectedRange(NSRange(location: 0, length: 6))
        #expect(selection.selectedRange() == NSRange(location: 0, length: 6))
        #expect(selection.string == "段落の文字を選択してコピーできます")
        #expect(selection.textStorage?.attributedSubstring(from: selection.selectedRange()).string == "段落の文字を")
        #expect(document.activeBlockEdit == nil)
        #expect(!selectedText(in: view).isEmpty)
        #expect(!selectedText(in: view).contains("次の段落"))
    }

    @Test
    func paragraphDragDoesNotTriggerBlockClickRecognizer() async throws {
        let document = FileTabDocument(path: "selection.md", root: "/")
        document.draft = "段落の文字を選択してコピーできます\n\n次の段落\n"
        let (window, view) = makeWindow(document: document, usesUndoScope: true)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(50))
        view.layoutSubtreeIfNeeded()
        let frame = try #require(accessibilityFrame(in: view, text: "段落の文字を選択してコピーできます"))
        let start = NSPoint(x: frame.minX + 2, y: frame.midY)
        let end = NSPoint(x: start.x + 80, y: start.y)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let events = try [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp].enumerated().map { index, type in
            try #require(NSEvent.mouseEvent(with: type,
                location: window.convertPoint(fromScreen: index == 0 ? start : end), modifierFlags: [],
                timestamp: timestamp + Double(index) * 0.1, windowNumber: window.windowNumber,
                context: nil, eventNumber: index + 1, clickCount: 1, pressure: index == 2 ? 0 : 1))
        }
        try sendMarkdownMouseEvents(events, in: window)
        try await Task.sleep(for: .milliseconds(50))
        #expect(document.activeBlockEdit == nil)
        #expect(!selectedText(in: view).isEmpty)
        #expect(!selectedText(in: view).contains("次の段落"))
        // 同じ文字のクリックでは編集を始める。ドラッグと編集が両立することを確認する。
        try await click(start, in: window)
        try await Task.sleep(for: .milliseconds(50))
        #expect(document.activeBlockEdit?.original == "段落の文字を選択してコピーできます\n\n")
    }

    @Test
    func paragraphTrackingDragReportsTheBlockBoundaryUntilRelease() async throws {
        let document = FileTabDocument(path: "selection.md", root: "/")
        document.draft = "段落の文字を選択してコピーできます\n\n次の段落\n"
        let (window, view) = makeWindow(document: document, usesUndoScope: false)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(50))
        view.layoutSubtreeIfNeeded()
        let frame = try #require(accessibilityFrame(in: view, text: "段落の文字を選択してコピーできます"))
        let start = NSPoint(x: frame.minX + 2, y: frame.midY)
        func observers(in view: NSView) -> [MarkdownBlockSelectionObserver.SelectionView] {
            (view as? MarkdownBlockSelectionObserver.SelectionView).map { [$0] }
                ?? view.subviews.flatMap { observers(in: $0) }
        }
        let observer = try #require(observers(in: view).first {
            $0.prepareClick != nil && $0.bounds.contains($0.convert(window.convertPoint(fromScreen: start), from: nil))
        })
        var boundaries: [Bool] = []
        observer.onBoundary = { boundaries.append($0) }
        let end = NSPoint(x: start.x + 80, y: frame.minY - 45)
        let timestamp = ProcessInfo.processInfo.systemUptime
        let events = try [NSEvent.EventType.leftMouseDown, .leftMouseDragged, .leftMouseUp].enumerated().map { index, type in
            try #require(NSEvent.mouseEvent(with: type,
                location: window.convertPoint(fromScreen: index == 0 ? start : end), modifierFlags: [],
                timestamp: timestamp + Double(index) * 0.1, windowNumber: window.windowNumber,
                context: nil, eventNumber: index + 1, clickCount: 1, pressure: index == 2 ? 0 : 1))
        }
        try sendMarkdownMouseEvents(events, in: window)
        try await Task.sleep(for: .milliseconds(50))
        #expect(boundaries.contains(true))
        #expect(boundaries.last == false)
        #expect(document.activeBlockEdit == nil)
        #expect(!selectedText(in: view).isEmpty)
    }

    @Test(arguments: [false, true], [false, true])
    func loadedParagraphClickCreatesTextEditor(usesUndoScope: Bool, clicksText: Bool) async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = "# 見出し\r\n\r\n編集前の本文\r\n\r\n[案内][guide]\r\n\r\n[guide]: linked.md\r\n"
        try Data(source.utf8).write(to: root.appendingPathComponent("document.md"))
        let document = FileTabDocument(path: "document.md", root: root.path)
        await document.loadIfNeeded()
        _ = document.setPresentation(.rendered)
        await document.refreshMarkdownAnalysis()
        let paragraph = try #require(document.markdownBlocks.first { $0.original.contains("編集前の本文") })
        #expect(!document.markdownPresentationLocked)
        let (window, view) = makeWindow(document: document, usesUndoScope: usesUndoScope)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(50))
        view.layoutSubtreeIfNeeded()
        let frame = try #require(accessibilityFrame(in: view, text: "編集前の本文"))
        // XCUITest と同じ読み上げ要素の中央と、文字のある位置を比較する。
        let point = NSPoint(x: clicksText ? frame.minX + 12 : frame.midX, y: frame.midY)
        try await click(point, in: window)
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(document.activeBlockEdit?.range == paragraph.range)
        #expect(editors(in: view).contains { $0.string == paragraph.original })
        #expect(document.draft.utf8.elementsEqual(source.utf8))
    }

    @Test
    func referenceLinkClickOpensWithoutEditing() async throws {
        let document = FileTabDocument(path: "document.md", root: "/")
        document.draft = "編集前の本文\n\n[案内][guide]\n\n[guide]: linked.md\n"
        var openedURLs: [URL] = []
        let (window, view) = makeWindow(document: document, usesUndoScope: true) {
            openedURLs.append($0)
            return .handled
        }
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(50))
        view.layoutSubtreeIfNeeded()
        let frame = try #require(accessibilityFrame(in: view, text: "案内", role: .link))
        try await click(NSPoint(x: frame.midX, y: frame.midY), in: window)
        try await Task.sleep(for: .milliseconds(100))
        #expect(openedURLs == [URL(string: "linked.md")!])
        #expect(document.activeBlockEdit == nil)
        #expect(editors(in: view).isEmpty)
        let paragraphFrame = try #require(accessibilityFrame(in: view, text: "編集前の本文"))
        try await click(NSPoint(x: paragraphFrame.midX, y: paragraphFrame.midY), in: window)
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(document.activeBlockEdit?.original == "編集前の本文\n\n")
        #expect(editors(in: view).contains { $0.string == "編集前の本文\n\n" })
    }

    @Test
    func escapeAfterSaveAndPresentationRoundTripEndsEditing() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("document.md")
        try Data("# 見出し\r\n\r\n編集前の本文\r\n\r\n[案内][guide]\r\n\r\n[guide]: linked.md\r\n".utf8).write(to: file)
        let document = FileTabDocument(path: "document.md", root: root.path)
        await document.loadIfNeeded()
        #expect(document.setPresentation(.rendered))
        await document.refreshMarkdownAnalysis()
        let view = NSHostingView(rootView: FileTabUndoScope(document: document) {
            FileTabView(document: document, lastWriter: { _ in nil }, isFocused: true, openFile: { _, _ in })
        })
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        let window = MarkdownTrackingWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        defer { window.close() }
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        let originalFrame = try #require(accessibilityFrame(in: view, text: "編集前の本文"))
        try await click(NSPoint(x: originalFrame.midX, y: originalFrame.midY), in: window)
        try await Task.sleep(for: .milliseconds(100))
        let editor = try #require(editors(in: view).first)
        #expect(window.firstResponder === editor)
        #expect(!accessibilityTextAreas(in: view).isEmpty)
        editor.selectAll(nil)
        editor.insertText("編集した本文\n\n追加行\n", replacementRange: editor.selectedRange())
        _ = try await document.save()
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
        let expected = "# 見出し\r\n\r\n編集した本文\n\n追加行\n[案内][guide]\r\n\r\n[guide]: linked.md\r\n"
        #expect(try Data(contentsOf: file) == Data(expected.utf8))
        #expect(document.activeBlockEdit == nil)
        #expect(editors(in: view).isEmpty)
        #expect(accessibilityTextAreas(in: view).isEmpty)
        #expect(window.firstResponder !== editor)
        #expect(editor.window == nil)
        #expect(window.performKeyEquivalent(with: try key(46, characters: "m", flags: [.control, .command], in: window)))
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(document.presentation == .source)
        #expect(editors(in: view).count == 1)
        #expect(window.performKeyEquivalent(with: try key(46, characters: "m", flags: [.control, .command], in: window)))
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(document.presentation == .rendered)
        #expect(editors(in: view).isEmpty)
        let frame = try #require(accessibilityFrame(in: view, text: "編集した本文"))
        try await click(NSPoint(x: frame.midX, y: frame.midY), in: window)
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        let reopened = try #require(editors(in: view).first as? CurrentLineTextView)
        #expect(editors(in: view).count == 1)
        #expect(reopened.blockEditID == document.activeBlockEdit?.id)
        // フォーカスと編集IDを確認し、別の入力欄やフォーカス遅延による失敗を区別する。
        #expect(window.firstResponder === reopened)
        #expect(!accessibilityTextAreas(in: view).isEmpty)
        window.sendEvent(try key(53, characters: "\u{001B}", in: window))
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        #expect(document.activeBlockEdit == nil)
        #expect(editors(in: view).isEmpty)
        #expect(accessibilityTextAreas(in: view).isEmpty)
        #expect(window.firstResponder !== reopened)
        #expect(reopened.window == nil)
        #expect(document.draft.utf8.elementsEqual(expected.utf8))
        #expect(!document.hasUnsavedChanges)
    }

    private func key(_ code: UInt16, characters: String, flags: NSEvent.ModifierFlags = [], in window: NSWindow) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: code))
    }

    @Test
    func largeDocumentInitialLayout() async throws {
        let source = (0..<1_999).map { "段落\($0) " + String(repeating: "a", count: 215) + "\n\n" }.joined()
        for sample in 1...3 {
            let document = FileTabDocument(path: "document.md", root: "/")
            document.draft = source
            await document.refreshMarkdownAnalysis()
            #expect(document.markdownBlocks.count == 1_999)
            #expect((440_000...460_000).contains(source.utf8.count))
            #expect(document.setPresentation(.rendered))
            #expect(!document.markdownPresentationLocked)
            let start = ProcessInfo.processInfo.systemUptime
            let (window, view) = makeWindow(document: document, usesUndoScope: true)
            // 初回の画面外レイアウト完了まで。解析と画像化の時間は含めない。
            let elapsed = ProcessInfo.processInfo.systemUptime - start
            print("初回表示: 試行\(sample)、\(source.utf8.count)バイト、\(document.markdownBlocks.count)ブロック、\(elapsed)秒")
            defer { window.close() }
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
            #expect(accessibilityFrame(in: view, text: "段落0 " + String(repeating: "a", count: 215)) != nil)
        }
    }

    private func makeWindow(document: FileTabDocument, usesUndoScope: Bool,
                            openURL: @escaping (URL) -> OpenURLAction.Result = { _ in .discarded }) -> (NSWindow, NSView) {
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let content = MarkdownBlockEditor(document: document, openURL: openURL)
        let view: NSView = usesUndoScope
            ? NSHostingView(rootView: FileTabUndoScope(document: document) { content }
                .simultaneousGesture(TapGesture().onEnded {}))
            : NSHostingView(rootView: content)
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 420)
        let window = MarkdownTrackingWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        // 前面化せず、表示領域外で AppKit のイベント配送だけを有効にする。
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderBack(nil)
        view.layoutSubtreeIfNeeded()
        return (window, view)
    }

    private func click(_ screenPoint: NSPoint, in window: NSWindow) async throws {
        let timestamp = ProcessInfo.processInfo.systemUptime
        let events = try [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated().map { index, type in
            try #require(NSEvent.mouseEvent(with: type,
                location: window.convertPoint(fromScreen: screenPoint), modifierFlags: [],
                timestamp: timestamp + Double(index) * 0.02, windowNumber: window.windowNumber,
                context: nil, eventNumber: index + 1, clickCount: 1, pressure: index == 0 ? 1 : 0))
        }
        try sendMarkdownMouseEvents(events, in: window)
    }

    private func editors(in view: NSView) -> [NSTextView] {
        (view as? CurrentLineTextView).map { [$0] } ?? view.subviews.flatMap { editors(in: $0) }
    }

    private func selectedText(in view: NSView) -> String {
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> String {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return "" }
            let selector = NSSelectorFromString("accessibilitySelectedText")
            if object.responds(to: selector),
               let text = object.perform(selector)?.takeUnretainedValue() as? String, !text.isEmpty {
                return text
            }
            let childrenSelector = NSSelectorFromString("accessibilityChildren")
            let children = object.responds(to: childrenSelector)
                ? object.perform(childrenSelector)?.takeUnretainedValue() as? [NSObject] ?? [] : []
            let descendants = children + ((object as? NSView)?.subviews ?? [])
            return descendants.map(visit).joined()
        }
        return visit(view)
    }

    private func accessibilityTextAreas(in view: NSView) -> [NSObject] {
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> [NSObject] {
            guard seen.insert(ObjectIdentifier(object)).inserted else { return [] }
            let role = NSSelectorFromString("accessibilityRole")
            let isTextArea = object.responds(to: role)
                && object.perform(role)?.takeUnretainedValue() as? String == NSAccessibility.Role.textArea.rawValue
            let children = NSSelectorFromString("accessibilityChildren")
            let descendants = object.responds(to: children)
                ? object.perform(children)?.takeUnretainedValue() as? [NSObject] ?? [] : []
            // AppKit のビュー階層ではなく、読み上げに公開される子だけを辿る。
            return (isTextArea ? [object] : []) + descendants.flatMap(visit)
        }
        return visit(view)
    }

    private func accessibilityFrame(in view: NSView, text: String, role: NSAccessibility.Role? = nil) -> NSRect? {
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
            if label == text, role == nil || value("accessibilityRole", of: object) as? String == role?.rawValue,
               object.responds(to: NSSelectorFromString("accessibilityFrame")) {
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
