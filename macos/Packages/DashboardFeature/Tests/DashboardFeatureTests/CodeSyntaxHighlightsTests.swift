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

    @Test func headingFontsUseOneStorageEditPerBatch() async throws {
        final class Counter: NSObject, NSTextStorageDelegate {
            var edits = 0
            func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                             range: NSRange, changeInLength delta: Int) {
                if editedMask.contains(.editedAttributes) { edits += 1 }
            }
        }
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.string = (1...2_000).map { "## H\($0)\nbody\n" }.joined()
        let counter = Counter()
        view.textStorage?.delegate = counter
        let highlights = CodeSyntaxHighlights()
        var batches = 0
        highlights.onApplicationBatch = { _ in batches += 1 }
        #expect(await settle(highlights, view: view, path: "README.md"))
        #expect(counter.edits <= batches, "見出しごとに再レイアウトを起こさない")
    }

    @Test func japaneseHeadingClearsAfterEditingAndExternalSync() async throws {
        func weight(_ view: NSTextView, _ index: Int) -> CGFloat {
            if let container = view.textContainer { view.layoutManager?.ensureLayout(for: container) }
            let font = view.textStorage?.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            return (font?.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any])?[.weight] as? CGFloat ?? 0
        }
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.string = "# 日本語の見出し\n"
        let highlights = CodeSyntaxHighlights()
        #expect(await settle(highlights, view: view, path: "README.md"))
        #expect(weight(view, 2) > 0)
        highlights.recordEdit(NSRange(location: 0, length: 2), replacementLength: 0)
        view.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")
        #expect(await settle(highlights, view: view, path: "README.md"))
        #expect(weight(view, 0) == 0, "見出しでなくなった日本語を太字のまま残さない")

        let synced = CurrentLineTextView(usingTextLayoutManager: false)
        synced.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        synced.string = "# Title\n本文です\n"
        let other = CodeSyntaxHighlights()
        #expect(await settle(other, view: synced, path: "README.md"))
        #expect(CodeTextEditor.synchronizeText("# Title\n本文です。\n", with: synced, beforeReplacement: { other.invalidate() }))
        #expect(await settle(other, view: synced, path: "README.md"))
        #expect(weight(synced, 8) == 0, "外部同期後に本文の日本語を太字にしない")
    }

    @Test(arguments: ["\n", "\r\n", "\r", "\u{0085}", "\u{2028}", "\u{2029}"])
    func markdownHeadingEndsAtUnicodeLineBoundary(newline: String) async throws {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        let regular = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.font = regular
        let source = "# 日本語 😀é\(newline)body 😀é\(newline)"
        view.string = source
        #expect(await settle(CodeSyntaxHighlights(), view: view, path: "README.md"))
        let storage = try #require(view.textStorage)
        let heading = try #require(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        let traits = heading.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
        #expect((traits?[.weight] as? CGFloat ?? 0) > 0)
        let body = (source as NSString).range(of: "body").location
        #expect(storage.attribute(.font, at: body, effectiveRange: nil) as? NSFont == regular)
        #expect(storage.string.utf8.elementsEqual(source.utf8))
    }

    @Test func markdownHeadingRequiresASCIISpaceOrTab() async throws {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        let regular = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.font = regular
        let source = "#\u{00A0}nonbreaking\n#\u{3000}fullwidth\n# space\n#\ttab\n#\n"
        view.string = source
        #expect(await settle(CodeSyntaxHighlights(), view: view, path: "README.md"))
        let storage = try #require(view.textStorage)
        for text in ["#\u{00A0}nonbreaking", "#\u{3000}fullwidth"] {
            let location = (source as NSString).range(of: text).location
            #expect(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont == regular)
        }
        for text in ["# space", "#\ttab", "#\n"] {
            let location = (source as NSString).range(of: text).location
            let font = try #require(storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont)
            let traits = font.fontDescriptor.object(forKey: .traits) as? [NSFontDescriptor.TraitKey: Any]
            #expect((traits?[.weight] as? CGFloat ?? 0) > 0)
        }
        #expect(storage.string.utf8.elementsEqual(source.utf8))
    }

    @Test func markdownHeadingsKeepMonospacedMetricsAndClearAfterEditing() async throws {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        let regular = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        view.font = regular
        view.string = "# Title `code`\n本文\n```markdown\n# fenced\n```\n#not-heading\n    # indented\n```text\n```\n## After\n"
        let storage = try #require(view.textStorage)
        let saved = NSAttributedString(attributedString: storage)
        let typing = view.typingAttributes
        let highlights = CodeSyntaxHighlights()
        #expect(await settle(highlights, view: view, path: "README.md"))
        let heading = try #require(storage.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        #expect(heading.fontDescriptor.symbolicTraits.contains(.monoSpace))
        #expect(heading != regular)
        for sample in ["Title code", "0123456789", "# 日本語"] {
            let width = (sample as NSString).size(withAttributes: [.font: regular]).width
            #expect(abs(width - (sample as NSString).size(withAttributes: [.font: heading]).width) < 0.01)
        }
        for text in ["本文", "# fenced", "#not-heading", "# indented"] {
            let range = (view.string as NSString).range(of: text)
            #expect(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
                == saved.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        }
        let after = (view.string as NSString).range(of: "After").location
        #expect(storage.attribute(.font, at: after, effectiveRange: nil) as? NSFont == heading)
        #expect(storage.string == saved.string)
        #expect(storage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
            == saved.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(NSDictionary(dictionary: view.typingAttributes).isEqual(NSDictionary(dictionary: typing)))
        let range = NSRange(location: 0, length: 2)
        highlights.recordEdit(range, replacementLength: 0)
        storage.replaceCharacters(in: range, with: "")
        #expect(await settle(highlights, view: view, path: "README.md"))
        #expect(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont == regular)
    }

    @Test(arguments: ["Title", "日本語の見出し"])
    func sourceHeadingDrawsHeavierWithoutMovingGlyphs(title: String) async throws {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.backgroundColor = .white
        view.textColor = .black
        view.string = "# \(title)\n"
        let layout = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: 2, length: title.utf16.count), actualCharacterRange: nil)
        let bounds = layout.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
        func ink() throws -> Int {
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            return (Int(bounds.minY * scale)..<Int(bounds.maxY * scale)).reduce(0) { count, y in
                count + (Int(bounds.minX * scale)..<Int(bounds.maxX * scale)).filter { x in
                    guard let rgb = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                    return rgb.redComponent < 0.9 && rgb.greenComponent < 0.9 && rgb.blueComponent < 0.9
                }.count
            }
        }
        let regularInk = try ink()
        #expect(await settle(CodeSyntaxHighlights(), view: view, path: "README.md"))
        #expect(layout.boundingRect(forGlyphRange: glyphs, in: container)
            .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y) == bounds)
        #expect(try ink() > regularInk, "表示用の太字属性が実際の画素にも反映される")
    }

    @Test(arguments: [false, true])
    func japaneseBodyPixelsStayRegularWhenHeadingChanges(dark: Bool) async throws {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: 300, height: 80)
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.backgroundColor = dark ? .black : .white
        view.textColor = dark ? .white : .black
        view.string = "# Title\n本文です\n"
        let layout = try #require(view.layoutManager)
        let container = try #require(view.textContainer)
        func bodyPixels() throws -> [UInt8] {
            layout.ensureLayout(for: container)
            let range = (view.string as NSString).range(of: "本文です")
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let bounds = layout.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
            let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / view.bounds.width
            var pixels: [UInt8] = []
            for y in Int(bounds.minY * scale)..<Int(bounds.maxY * scale) {
                for x in Int(bounds.minX * scale)..<Int(bounds.maxX * scale) {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    pixels.append(UInt8((color.redComponent * 255).rounded()))
                }
            }
            return pixels
        }
        let regular = try bodyPixels()
        let highlights = CodeSyntaxHighlights()
        #expect(await settle(highlights, view: view, path: "README.md"))
        #expect(try bodyPixels() == regular, "見出しの太字を日本語の本文へ波及させない")
        #expect(CodeTextEditor.synchronizeText("# Title\n本文です。\n", with: view,
                                              beforeReplacement: { highlights.invalidate() }))
        #expect(await settle(highlights, view: view, path: "README.md"))
        #expect(try bodyPixels() == regular, "外部同期後も日本語の本文を通常字体で描く")
        highlights.recordEdit(NSRange(location: 0, length: 2), replacementLength: 0)
        view.textStorage?.replaceCharacters(in: NSRange(location: 0, length: 2), with: "")
        #expect(await settle(highlights, view: view, path: "README.md"))
        #expect(try bodyPixels() == regular, "見出し解除後も本文の画素を通常字体に保つ")
    }

    @Test func blockInlineCodeUsesBodyColorWithoutChangingLinksOrSource() async {
        let source = "# 見出し\n`swift test` [設計](docs/design.md)\n"
        for block in [false, true] {
            let view = CurrentLineTextView(usingTextLayoutManager: false)
            view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            view.textColor = NSColor(DSColor.textPrimary)
            view.blockEditID = block ? UUID() : nil
            view.string = source
            let highlights = CodeSyntaxHighlights()
            #expect(await settle(highlights, view: view, path: "README.md"))
            let code = (source as NSString).range(of: "`swift test`").location
            let link = (source as NSString).range(of: "docs/design.md").location
            #expect(color(in: view, at: code) == components(NSColor(block ? DSColor.textPrimary : DSColor.codeSyntaxString)))
            #expect(color(in: view, at: link) == components(NSColor(DSColor.codeSyntaxString)))
            if block {
                #expect(view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
                    == NSFont.monospacedSystemFont(ofSize: 11, weight: .regular))
            }
        }
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
