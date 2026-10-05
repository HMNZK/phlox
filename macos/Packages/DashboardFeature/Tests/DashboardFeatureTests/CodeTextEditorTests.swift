import AppKit
import SwiftUI
import Testing
@testable import DashboardFeature

@Test @MainActor func reusedTextAccessDoesNotRevertTypedText() async throws {
    _ = NSApplication.shared
    var text = "let value = 42\n"
    let getText = { text }
    let setText: (String) -> Void = { text = $0 }
    let host = NSHostingView(rootView: CodeTextEditor(getText: getText, setText: setText, path: "a.swift"))
    host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    host.layoutSubtreeIfNeeded()
    func editor(_ view: NSView) -> CurrentLineTextView? {
        (view as? CurrentLineTextView) ?? view.subviews.lazy.compactMap { editor($0) }.first
    }
    let view = try #require(editor(host))
    let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
    defer { coordinator.highlights.cancel() }
    view.insertText("x", replacementRange: NSRange(location: 0, length: 0))
    #expect(text == "xlet value = 42\n")
    host.rootView = CodeTextEditor(getText: getText, setText: setText, path: "b.swift")
    host.layoutSubtreeIfNeeded()
    #expect(view.string == text, "古い値で入力を巻き戻さない")
    view.insertText("y", replacementRange: NSRange(location: 0, length: 0))
    #expect(text == "yxlet value = 42\n")
}

private struct FrozenEditorParent: View, Equatable {
    let getText: () -> String
    let setText: (String) -> Void
    nonisolated static func == (lhs: FrozenEditorParent, rhs: FrozenEditorParent) -> Bool { true }
    var body: some View { CodeTextEditor(getText: getText, setText: setText, path: "a.swift") }
}

// 親を作り直さず環境だけが変わる更新でも、生成時の本文で入力を巻き戻さない。
@Test @MainActor func environmentOnlyUpdateWithOldStructKeepsTypedText() throws {
    _ = NSApplication.shared
    var text = "let value = 42\n"
    let parent = FrozenEditorParent(getText: { text }, setText: { text = $0 })
    let host = NSHostingView(rootView: AnyView(parent.equatable().environment(\.locale, Locale(identifier: "ja"))))
    host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    host.layoutSubtreeIfNeeded()
    func editor(_ view: NSView) -> CurrentLineTextView? {
        (view as? CurrentLineTextView) ?? view.subviews.lazy.compactMap { editor($0) }.first
    }
    let view = try #require(editor(host))
    defer { (view.delegate as? CodeTextEditor.Coordinator)?.highlights.cancel() }
    view.insertText("x", replacementRange: NSRange(location: 0, length: 0))
    host.rootView = AnyView(parent.equatable().environment(\.locale, Locale(identifier: "en")))
    host.layoutSubtreeIfNeeded()
    #expect(view.string == text, "親を作り直さない更新でも入力を巻き戻さない")
    view.insertText("y", replacementRange: NSRange(location: 0, length: 0))
    #expect(text == "yxlet value = 42\n")
}

@Test(arguments: [false, true]) @MainActor
func codeEditorTogglesEditabilityWithoutWritingDisplayBack(omitsLongLine: Bool) throws {
    _ = NSApplication.shared
    var text = String(repeating: "a", count: 10_001) + "\n"
    let getText = { text }
    let setText: (String) -> Void = { text = $0 }
    let host = NSHostingView(rootView: CodeTextEditor(getText: getText, setText: setText, path: "a.swift"))
    host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    host.layoutSubtreeIfNeeded()
    func editor(_ view: NSView) -> CurrentLineTextView? {
        (view as? CurrentLineTextView) ?? view.subviews.lazy.compactMap { editor($0) }.first
    }
    let view = try #require(editor(host))
    let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
    defer { coordinator.highlights.cancel() }
    view.insertText("x", replacementRange: NSRange(location: 0, length: 0))
    let typed = text
    host.rootView = CodeTextEditor(getText: getText, setText: setText, path: "a.swift", isEditable: false,
                                  readOnlyText: omitsLongLine ? ReadOnlyText(text) : nil)
    host.layoutSubtreeIfNeeded()
    #expect(!view.isEditable)
    #expect(view.isSelectable)
    #expect(text == typed)
    if omitsLongLine { #expect(view.string != text) }
    host.rootView = CodeTextEditor(getText: getText, setText: setText, path: "a.swift")
    host.layoutSubtreeIfNeeded()
    #expect(view.isEditable)
    #expect(view.string == typed)
    #expect(text == typed)
    view.insertText("y", replacementRange: NSRange(location: 0, length: 0))
    #expect(text == "y" + typed)
}

@Test("大きいソースの先頭・中央・末尾まで非連続レイアウトでスクロールできる", arguments: [false, true]) @MainActor
func codeEditorScrollsAcrossLargeSources(longLine: Bool) async throws {
    let source = longLine ? String(repeating: "A", count: 1_000_001) + "\n" : String(repeating: "let value = 42\n", count: 80_000)
    let host = NSHostingView(rootView: CodeTextEditor(getText: { source }, setText: { _ in }, path: "large.swift"))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 200),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    try await Task.sleep(for: .milliseconds(10))
    host.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let view = try #require(descendants(host).compactMap { $0 as? CurrentLineTextView }.first)
    let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
    defer { coordinator.highlights.cancel() }
    let layout = try #require(view.layoutManager)
    let container = try #require(view.textContainer)
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    for location in [0, view.textStorage!.length / 2, view.textStorage!.length - 2] {
        view.scrollRangeToVisible(NSRange(location: location, length: 1))
        host.layoutSubtreeIfNeeded()
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let visible = view.visibleRect.offsetBy(dx: -view.textContainerOrigin.x, dy: -view.textContainerOrigin.y)
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        #expect(NSLocationInRange(location, characters), "要求した位置を可視範囲へ移せる")
    }
}

@Test("本文の編集・undo・外部更新後も行番号が新しい本文と一致する", arguments: ["\n", "\r\n", "\r", "\u{2028}"]) @MainActor
func codeEditorRefreshesLineNumbersAfterTextChanges(separator: String) async throws {
    _ = NSApplication.shared
    var source = (1...20).map { "行\($0)" }.joined(separator: separator) + separator
    let host = NSHostingView(rootView: CodeTextEditor(getText: { source }, setText: { source = $0 }))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 160),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    try await Task.sleep(for: .milliseconds(10))
    host.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let textView = try #require(descendants(host).compactMap { $0 as? CurrentLineTextView }.first)
    let coordinator = try #require(textView.delegate as? CodeTextEditor.Coordinator)
    defer { coordinator.highlights.cancel() }

    func rulerPixels(_ view: NSView) throws -> [UInt8] {
        view.layoutSubtreeIfNeeded()
        let ruler = try #require(descendants(view).compactMap { $0 as? LineNumberRuler }.first)
        ruler.needsDisplay = true
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.bitmapData)
        let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let rect = view.convert(ruler.bounds, from: ruler)
        let left = max(0, Int(rect.minX * scale))
        let right = min(bitmap.pixelsWide, Int(rect.maxX * scale))
        let bytesPerPixel = bitmap.bitsPerPixel / 8
        var pixels: [UInt8] = []
        for y in 0..<bitmap.pixelsHigh {
            let offset = y * bitmap.bytesPerRow + left * bytesPerPixel
            pixels.append(contentsOf: UnsafeBufferPointer(start: data + offset, count: (right - left) * bytesPerPixel))
        }
        return pixels
    }

    func matchesFreshEditor() async throws {
        let fresh = NSHostingView(rootView: CodeTextEditor(getText: { textView.string }, setText: { _ in }))
        let reference = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: 160),
                                 styleMask: [.borderless], backing: .buffered, defer: false)
        reference.isReleasedWhenClosed = false
        reference.contentView = fresh
        defer { reference.contentView = nil; reference.close() }
        try await Task.sleep(for: .milliseconds(10))
        let freshView = try #require(descendants(fresh).compactMap { $0 as? CurrentLineTextView }.first)
        let freshCoordinator = try #require(freshView.delegate as? CodeTextEditor.Coordinator)
        defer { freshCoordinator.highlights.cancel() }
        textView.enclosingScrollView?.contentView.scroll(to: .zero)
        freshView.enclosingScrollView?.contentView.scroll(to: .zero)
        let middle = NSRange(location: textView.textStorage!.length / 2, length: 0)
        textView.scrollRangeToVisible(middle)
        freshView.scrollRangeToVisible(middle)
        try #require(try rulerPixels(host) == rulerPixels(fresh))
    }

    _ = try rulerPixels(host)
    if separator == "\r" {
        textView.insertText("\n", replacementRange: NSRange(location: 3, length: 0))
        try await matchesFreshEditor()
    }
    textView.insertText(String(repeating: "追加" + separator, count: 3), replacementRange: NSRange(location: 0, length: 0))
    try await matchesFreshEditor()
    textView.undoManager?.undo()
    try await matchesFreshEditor()
    source = (1...20).dropFirst(5).map { "行\($0)" }.joined(separator: separator) + separator
    #expect(CodeTextEditor.synchronizeText(source, with: textView))
    try await matchesFreshEditor()
}

@Test("ソースの行間を広げても行番号と本文の文字を同じ高さへ描く", arguments: [(10, false, "\n"), (30, false, "\n"), (11, true, "\n"),
    (10, false, "\u{0085}"), (10, false, "\u{2028}"), (10, false, "\u{2029}")]) @MainActor
func codeEditorLineNumbersMatchTextBaselines(lineCount: Int, startsWithBlankLine: Bool, separator: String) async throws {
    let source = (1...lineCount).map { startsWithBlankLine && $0 == 1 ? "" : String($0) }.joined(separator: separator)
        + (startsWithBlankLine ? "" : separator)
    let host = NSHostingView(rootView: CodeTextEditor(getText: { source }, setText: { _ in }))
    let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 300, height: lineCount <= 11 ? 300 : 160),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    defer { window.contentView = nil; window.close() }
    try await Task.sleep(for: .milliseconds(100))
    host.layoutSubtreeIfNeeded()
    func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap(descendants)
    }
    let textView = try #require(descendants(host).compactMap { $0 as? NSTextView }.first)
    let ruler = try #require(textView.enclosingScrollView?.verticalRulerView as? LineNumberRuler)
    #expect(textView.visibleRect.minY == 0, "初期表示で先頭行を切り取らない")
    textView.textColor = .red
    ruler.numberColor = .red
    textView.needsDisplay = true
    ruler.needsDisplay = true
    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
    let rulerBounds = host.convert(ruler.bounds, from: ruler)
    let textBounds = host.convert(NSRect(x: textView.textContainerOrigin.x, y: 0, width: 20, height: host.bounds.height),
                                  from: textView)
    #expect(textBounds.minX >= rulerBounds.maxX, "行番号欄が本文を隠さない")
    func inkRows(in rect: NSRect, height: CGFloat = 48) -> [Int] {
        let left = max(0, Int(rect.minX * scale))
        let right = min(bitmap.pixelsWide, Int(rect.maxX * scale))
        return (0..<min(bitmap.pixelsHigh, Int(height * scale))).filter { y in
            (left..<right).contains { x in
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return color.redComponent > 0.7 && color.greenComponent < 0.4 && color.blueComponent < 0.4
            }
        }
    }
    let text = inkRows(in: textBounds)
    let numbers = inkRows(in: rulerBounds).filter { !startsWithBlankLine || $0 >= (text.first ?? 0) }
    #expect(!text.isEmpty)
    #expect(numbers == text)
    if !startsWithBlankLine {
        #expect(abs(CGFloat(text.first ?? 0) / scale - 13) <= 0.5,
                "1行目の文字の上端は見本3cのヘッダー下から13ptに揃える")
    }
    if lineCount == 10 || startsWithBlankLine {
        let rows = inkRows(in: rulerBounds, height: 260)
        let starts = rows.indices.filter { $0 == 0 || rows[$0] > rows[$0 - 1] + 1 }.map { rows[$0] }
        #expect(starts.count == 11, "途中と末尾の空行にも番号を描く")
        if starts.count == 11 {
            // 同じ「1」の上端で比較し、数字ごとの字形の差を含めない。
            #expect(abs(CGFloat(starts[10] - starts[0]) - 192.5 * scale) <= 1,
                    "見本の19.25pt行間で、空行も本文と同じ間隔で描く")
        }
    }
}

@Test @MainActor func codeEditorSynchronizesCanonicallyEquivalentBytes() {
    let textView = NSTextView(usingTextLayoutManager: false)
    textView.string = "\u{00E9}"
    let replacement = "e\u{0301}"
    #expect(textView.string == replacement)

    CodeTextEditor.synchronizeText(replacement, with: textView)

    #expect(textView.string.utf8.elementsEqual(replacement.utf8))
}

@Test @MainActor func codeEditorKeepsSelectionWhenBytesHaveNotChanged() {
    let textView = NSTextView(usingTextLayoutManager: false)
    textView.string = "同じ本文"
    textView.setSelectedRange(NSRange(location: 2, length: 1))

    CodeTextEditor.synchronizeText("同じ本文", with: textView)

    #expect(textView.selectedRange() == NSRange(location: 2, length: 1))
}

@Test @MainActor func blockEditorSynchronizesBeforeCommittingAndCommitsOnlyOnce() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    let id = UUID()
    textView.blockEditID = id
    textView.string = "通知を待たず同期"
    var operations: [String] = []
    textView.synchronizeBlockEdit = { received, value in
        #expect(received == id)
        #expect(value == "通知を待たず同期")
        operations.append("同期")
    }
    textView.commitBlockEdit = { received in
        #expect(received == id)
        operations.append("確定")
        return true
    }

    #expect(textView.synchronizeAndCommitBlockEdit())
    #expect(textView.synchronizeAndCommitBlockEdit())
    #expect(operations == ["同期", "確定"])
}

@Test @MainActor func blockEditorRemovalSynchronizesWithoutCommitting() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    textView.blockEditID = UUID()
    textView.string = "撤去時の未確定文字"
    var synchronized: String?
    var commits = 0
    textView.synchronizeBlockEdit = { _, value in synchronized = value }
    textView.commitBlockEdit = { _ in commits += 1; return true }

    textView.dismantleBlockEdit()
    #expect(textView.synchronizeAndCommitBlockEdit())

    #expect(synchronized == "撤去時の未確定文字")
    #expect(commits == 0)
}

@Test @MainActor func blockEditorRetainsEditWhenCommitIsRejected() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    let id = UUID()
    textView.blockEditID = id
    textView.string = "保持する文字"
    var synchronized: String?
    textView.synchronizeBlockEdit = { _, value in synchronized = value }
    textView.commitBlockEdit = { _ in false }

    #expect(!textView.synchronizeAndCommitBlockEdit())
    #expect(textView.blockEditID == id)
    #expect(synchronized == "保持する文字")
}

@Test @MainActor func blockEditorEndsLocalUndoHistoryOnCommit() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    textView.blockEditID = UUID()
    let undo = textView.undoManager!
    undo.registerUndo(withTarget: textView) { view in view.string = "前の文字" }
    textView.commitBlockEdit = { _ in true }
    #expect(undo.canUndo)

    #expect(textView.synchronizeAndCommitBlockEdit())

    #expect(!undo.canUndo)
}

@Test @MainActor func blockEditorUnmarksJapaneseCompositionBeforeSynchronizing() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    textView.blockEditID = UUID()
    textView.setMarkedText("日本語の変換", selectedRange: NSRange(location: 6, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
    #expect(textView.hasMarkedText())
    var synchronized: String?
    textView.synchronizeBlockEdit = { _, value in
        #expect(!textView.hasMarkedText())
        synchronized = value
    }
    textView.commitBlockEdit = { _ in true }

    #expect(textView.synchronizeAndCommitBlockEdit())
    #expect(synchronized == "日本語の変換")
}

@Test @MainActor func blockEditorWindowRemovalDoesNotCommitPendingInput() {
    let textView = CurrentLineTextView(usingTextLayoutManager: false)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView?.addSubview(textView)
    textView.blockEditID = UUID()
    textView.string = "戻ると復元する入力"
    var synchronized: String?
    var commits = 0
    textView.synchronizeBlockEdit = { _, value in synchronized = value }
    textView.commitBlockEdit = { _ in commits += 1; return true }
    window.makeFirstResponder(textView)

    textView.removeFromSuperview()

    #expect(synchronized == "戻ると復元する入力")
    #expect(commits == 0)
}
