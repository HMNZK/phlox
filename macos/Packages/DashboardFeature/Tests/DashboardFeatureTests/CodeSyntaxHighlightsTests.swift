import AppKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite(.serialized)
@MainActor
struct CodeSyntaxHighlightsTests {
    private final class MarkedView: NSTextView {
        var marked = false
        override func hasMarkedText() -> Bool { marked }
    }

    private func components(_ color: NSColor) -> [CGFloat]? {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return nil }
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
    }

    private func color(in view: NSTextView, at index: Int = 0) -> [CGFloat]? {
        let value =
        (view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: index,
                                                effectiveRange: nil) as? NSColor)
            ?? (view.textStorage?.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor)
        return value.flatMap(components)
    }

    private func settle(_ highlights: CodeSyntaxHighlights, view: NSTextView, path: String) async -> Bool {
        var done = false
        highlights.onHighlightComplete = { _ in done = true }
        highlights.update(view, path: path)
        for _ in 0..<200 {
            if done { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    @Test func displayAttributesPreserveBytesSelectionTypingAndUndo() async {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.textColor = NSColor(DSColor.textPrimary)
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 160))
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 1_200)
        scroll.documentView = view
        view.string = "let é = \"😀\"\r\n// 原文\r"
        view.selectedRanges = [NSValue(range: NSRange(location: 4, length: 2)),
                               NSValue(range: NSRange(location: 18, length: 2))]
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 30))
        view.typingAttributes = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                                 .foregroundColor: NSColor.cyan, .kern: 1.5]
        let originalTyping = NSDictionary(dictionary: view.typingAttributes)
        let original = Array(view.string.utf8)
        let originalAttributes = NSAttributedString(attributedString: view.textStorage!)
        let selected = view.selectedRanges
        let origin = scroll.contentView.bounds.origin
        let highlights = CodeSyntaxHighlights()
        #expect(await settle(highlights, view: view, path: "a.swift"))
        #expect(Array(view.string.utf8) == original)
        #expect(view.textStorage!.isEqual(to: originalAttributes))
        #expect(view.selectedRanges == selected)
        #expect(scroll.contentView.bounds.origin == origin)
        #expect(!view.undoManager!.canUndo)
        #expect(NSDictionary(dictionary: view.typingAttributes).isEqual(originalTyping))
        #expect(color(in: view) == components(NSColor(DSColor.codeSyntaxKeyword)))
    }

    @Test func markedTextStartedWhileCalculationIsPendingDefersCompletion() async {
        let view = MarkedView(usingTextLayoutManager: false)
        view.string = "let value = 1"
        let highlights = CodeSyntaxHighlights()
        var completions = 0
        highlights.onHighlightComplete = { _ in completions += 1 }
        highlights.update(view, path: "a.swift", debounce: true)
        view.marked = true
        try? await Task.sleep(for: .milliseconds(100))
        #expect(completions == 0)
        #expect(!highlights.isApplying)
        view.marked = false
        #expect(await settle(highlights, view: view, path: "a.swift"))
    }

    @Test func newerInputAndPathDiscardPendingCalculation() async {
        let view = NSTextView(usingTextLayoutManager: false)
        view.textColor = NSColor(DSColor.textPrimary)
        let highlights = CodeSyntaxHighlights()
        view.string = "let old = 1"
        highlights.update(view, path: "a.swift", debounce: true)
        view.string = "let new = 2"
        #expect(await settle(highlights, view: view, path: "a.txt"))
        #expect(view.string == "let new = 2")
        #expect(color(in: view) == components(NSColor(DSColor.textPrimary)))
        #expect(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0,
                                                       effectiveRange: nil) == nil)
    }

    @Test func markedTextDefersBindingAndAttributesUntilConfirmation() async {
        let view = MarkedView(usingTextLayoutManager: false)
        view.textColor = NSColor(DSColor.textPrimary)
        let highlights = CodeSyntaxHighlights()
        view.string = "let value = 1"
        let originalColor = color(in: view)
        view.marked = true
        CodeTextEditor.synchronizeText("別の本文", with: view)
        highlights.update(view, path: "a.swift")
        #expect(view.string == "let value = 1")
        #expect(color(in: view) == originalColor)
        view.marked = false
        #expect(await settle(highlights, view: view, path: "a.swift"))
        #expect(color(in: view) == components(NSColor(DSColor.codeSyntaxKeyword)))
    }

    @Test func highlightingDoesNotChangeDocumentVersionDirtyOrSavedBytes() async throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/highlight-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data([0xEF, 0xBB, 0xBF]) + Data("let text = \"é😀\"\r\n".utf8)
        let file = root.appendingPathComponent("sample.swift")
        try bytes.write(to: file)
        let document = FileTabDocument(path: "sample.swift", root: root.path)
        await document.loadIfNeeded()
        let version = document.version
        let view = NSTextView(usingTextLayoutManager: false)
        view.string = document.draft
        var bindingUpdates = 0
        let coordinator = CodeTextEditor.Coordinator(text: Binding(get: { document.draft }, set: {
            bindingUpdates += 1
            document.draft = $0
        }))
        view.delegate = coordinator
        #expect(await settle(coordinator.highlights, view: view, path: document.path))
        #expect(bindingUpdates == 0)
        #expect(document.version == version)
        #expect(!document.hasUnsavedChanges)
        #expect(Data(document.draft.utf8) == Data(view.string.utf8))
        try await document.save()
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test func themeChangeRecolorsAndDefersWhileMarked() async {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        var theme = arguments
        theme[ThemeStore.themeKey] = AppTheme.phloxLight.id
        defaults.setVolatileDomain(theme, forName: UserDefaults.argumentDomain)
        let view = MarkedView(usingTextLayoutManager: false)
        view.textColor = NSColor(DSColor.textPrimary)
        view.string = "let value = 1"
        let coordinator = CodeTextEditor.Coordinator(text: .constant(view.string))
        let highlights = coordinator.highlights
        coordinator.updateHighlights(view, path: "a.swift")
        #expect(await settle(highlights, view: view, path: "a.swift"))
        let light = color(in: view)
        let lightPlain = color(in: view, at: 3)
        view.marked = true
        theme[ThemeStore.themeKey] = AppTheme.phlox.id
        defaults.setVolatileDomain(theme, forName: UserDefaults.argumentDomain)
        coordinator.updateHighlights(view, path: "a.swift")
        #expect(color(in: view) == light)
        #expect(color(in: view, at: 3) == lightPlain)
        view.marked = false
        coordinator.updateHighlights(view, path: "a.swift")
        #expect(await settle(highlights, view: view, path: "a.swift"))
        let dark = color(in: view)
        #expect(dark == components(NSColor(DSColor.codeSyntaxKeyword)))
        #expect(dark != light)
        #expect(color(in: view, at: 3) == components(NSColor(DSColor.textPrimary)))
        #expect(color(in: view, at: 3) != lightPlain)
    }

    @Test func editingNotificationAndUndoRedoKeepInputHistory() async {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.textColor = NSColor(DSColor.textPrimary)
        view.allowsUndo = true
        view.isRichText = false
        view.string = "let value = "
        var draft = view.string
        let coordinator = CodeTextEditor.Coordinator(text: Binding(get: { draft }, set: { draft = $0 }))
        view.delegate = coordinator
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.undoManager?.beginUndoGrouping()
        view.insertText("42", replacementRange: view.selectedRange())
        view.undoManager?.endUndoGrouping()
        #expect(draft == "let value = 42")
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        #expect(color(in: view, at: 12) == components(NSColor(DSColor.codeSyntaxNumber)))
        view.undoManager?.undo()
        #expect(view.string == "let value = ")
        #expect(draft == view.string)
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        #expect(color(in: view, at: 11) == components(NSColor(DSColor.textPrimary)))
        view.undoManager?.redo()
        #expect(view.string == "let value = 42")
        #expect(draft == view.string)
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        #expect(color(in: view, at: 12) == components(NSColor(DSColor.codeSyntaxNumber)))
        coordinator.highlights.cancel()
    }

    private func expectFreshColors(_ view: NSTextView, path: String) async {
        let fresh = NSTextView(usingTextLayoutManager: false)
        fresh.textColor = NSColor(DSColor.textPrimary)
        fresh.string = view.string
        #expect(await settle(CodeSyntaxHighlights(), view: fresh, path: path))
        for index in 0..<view.string.utf16.count {
            #expect(color(in: view, at: index) == color(in: fresh, at: index))
        }
    }

    @Test func imeCancelAtEndThenDeleteDoesNotCrash() async {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.string = "let abc"
        let coordinator = CodeTextEditor.Coordinator(text: .constant(view.string))
        view.delegate = coordinator
        coordinator.updateBodyColor(view)
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        view.setSelectedRange(NSRange(location: view.string.utf16.count, length: 0))
        view.setMarkedText("か", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.setMarkedText("", selectedRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.unmarkText()
        view.deleteBackward(nil)
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        await expectFreshColors(view, path: "a.swift")
    }

    @Test func markedReplacementKeepsUnchangedAttributes() async {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.string = "let title = \"\"\n" + String(repeating: "let tail = 42\n", count: 1_000)
        let coordinator = CodeTextEditor.Coordinator(text: .constant(view.string))
        view.delegate = coordinator
        coordinator.updateBodyColor(view)
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        let range = NSRange(location: 13, length: 0)
        view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: range)
        view.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("日本語", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.hasMarkedText())
        #expect(view.string.hasPrefix("let title = \"日本語\"\n"))
        // 未編集行の属性を目印にし、確定時に全文へ再適用されないことを確かめる。
        let untouched = view.string.utf16.count - 3
        view.layoutManager?.addTemporaryAttribute(.foregroundColor, value: NSColor.systemPurple,
                                                 forCharacterRange: NSRange(location: untouched, length: 1))
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        #expect(color(in: view, at: untouched) == components(NSColor.systemPurple))
    }

    @Test func incrementalEditsMatchFullCalculationAcrossUnicodeAndDistantComments() async {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.string = "let é = \"😀\"\r\nlet tail = 42\r\n"
        let coordinator = CodeTextEditor.Coordinator(text: .constant(view.string))
        view.delegate = coordinator
        coordinator.updateBodyColor(view)
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        let edits: [(NSRange, String)] = [
            (NSRange(location: 0, length: 0), "/*"),
            (NSRange(location: 2, length: 0), "😀é\r\n"),
            (NSRange(location: 0, length: 2), ""),
            (NSRange(location: 0, length: 0), "\"\"\""),
            (NSRange(location: 0, length: 3), "")
        ]
        for (range, replacement) in edits {
            view.insertText(replacement, replacementRange: range)
            #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
            await expectFreshColors(view, path: "a.swift")
        }
    }

    @Test func sameBodyReplacementAndMarkedConfirmationRestoreRemovedAttributes() async {
        let view = MarkedView(usingTextLayoutManager: false)
        view.string = "let value = 42"
        let coordinator = CodeTextEditor.Coordinator(text: .constant(view.string))
        view.delegate = coordinator
        coordinator.updateBodyColor(view)
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        view.insertText("let", replacementRange: NSRange(location: 0, length: 3))
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        await expectFreshColors(view, path: "a.swift")
        view.marked = true
        coordinator.updateHighlights(view, path: "a.swift")
        view.layoutManager?.removeTemporaryAttribute(.foregroundColor,
            forCharacterRange: NSRange(location: 0, length: view.string.utf16.count))
        #expect(color(in: view) == components(NSColor(DSColor.textPrimary)))
        view.marked = false
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        await expectFreshColors(view, path: "a.swift")
    }

    @Test func partialApplicationCancellationAndViewReplacementRequireFullColors() async {
        let view = NSTextView(usingTextLayoutManager: false)
        view.textColor = NSColor(DSColor.textPrimary)
        view.string = String(repeating: "let value = 42 // text\n", count: 2_000)
        let highlights = CodeSyntaxHighlights()
        var canceled = false
        highlights.onApplicationBatch = { _ in
            if !canceled {
                canceled = true
                highlights.cancel()
            }
        }
        highlights.update(view, path: "a.swift")
        for _ in 0..<200 {
            if canceled { break }
            try? await Task.sleep(for: .milliseconds(10))
        }
        #expect(canceled)
        highlights.onApplicationBatch = nil
        #expect(await settle(highlights, view: view, path: "a.swift"))
        await expectFreshColors(view, path: "a.swift")
        let other = NSTextView(usingTextLayoutManager: false)
        other.textColor = NSColor(DSColor.textPrimary)
        other.string = view.string
        #expect(await settle(highlights, view: other, path: "a.swift"))
        await expectFreshColors(other, path: "a.swift")
    }

    @Test func debouncedDeleteReinsertAndDistantAppendRestoreEveryEditedParagraph() async {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.allowsUndo = true
        view.string = "let x = 1\r\nlet é = \"😀\"\r\nlet y = 2"
        let coordinator = CodeTextEditor.Coordinator(text: .constant(view.string))
        view.delegate = coordinator
        coordinator.updateBodyColor(view)
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        view.insertText("", replacementRange: NSRange(location: 0, length: 3))
        view.insertText("let", replacementRange: NSRange(location: 0, length: 0))
        view.insertText("0", replacementRange: NSRange(location: view.string.utf16.count, length: 0))
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        await expectFreshColors(view, path: "a.swift")
        view.insertText("😀", replacementRange: NSRange(location: 4, length: 1))
        view.insertText("", replacementRange: NSRange(location: 0, length: 3))
        view.insertText("let", replacementRange: NSRange(location: 0, length: 0))
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        await expectFreshColors(view, path: "a.swift")
        view.undoManager?.undo()
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        await expectFreshColors(view, path: "a.swift")
    }

    @Test func deletedAnchorTracksEarlierUnicodeEditsAndMultipleCarets() async {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.isRichText = false
        view.string = "let emoji = \"😀é\"\r\nlet tail = 42\r\nlet end = 3"
        let coordinator = CodeTextEditor.Coordinator(text: .constant(view.string))
        view.delegate = coordinator
        coordinator.updateBodyColor(view)
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        let tail = (view.string as NSString).range(of: "let tail")
        view.insertText("", replacementRange: NSRange(location: tail.location, length: 3))
        view.insertText("// 😀é\r\n", replacementRange: NSRange(location: 0, length: 0))
        let end = view.string.utf16.count
        view.insertText("0", replacementRange: NSRange(location: end, length: 0))
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        await expectFreshColors(view, path: "a.swift")
        view.selectedRanges = [NSValue(range: NSRange(location: 0, length: 0)),
                               NSValue(range: NSRange(location: view.string.utf16.count, length: 0))]
        view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(await settle(coordinator.highlights, view: view, path: "a.swift"))
        await expectFreshColors(view, path: "a.swift")
    }

    @Test func dynamicBodyColorRepaintsSameViewLikeStaticThemeColor() throws {
        let defaults = UserDefaults.standard
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        var theme = arguments
        func setTheme(_ value: AppTheme) {
            theme[ThemeStore.themeKey] = value.id
            defaults.setVolatileDomain(theme, forName: UserDefaults.argumentDomain)
        }
        func makeView() -> NSTextView {
            let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 360, height: 100))
            view.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            view.backgroundColor = .white
            return view
        }
        func pixels(_ view: NSTextView) throws -> Data {
            view.layoutManager?.ensureLayout(for: view.textContainer!)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let bytes = try #require(bitmap.bitmapData)
            return Data(bytes: bytes, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        }
        setTheme(.phloxLight)
        let view = makeView()
        let coordinator = CodeTextEditor.Coordinator(text: .constant("本文 é😀"))
        coordinator.updateBodyColor(view)
        view.string = "本文 é😀"
        let light = try pixels(view)
        for value in [AppTheme.phloxLight, .phlox] {
            setTheme(value)
            coordinator.updateBodyColor(view)
            let control = makeView()
            control.textColor = NSColor(DSColor.textPrimary)
            control.string = view.string
            #expect(try pixels(view) == pixels(control))
        }
        #expect(try pixels(view) != light)
    }

}
