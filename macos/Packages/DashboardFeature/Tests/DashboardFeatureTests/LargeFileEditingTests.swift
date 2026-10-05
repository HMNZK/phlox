import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("大きいファイルの編集・保存", .serialized)
@MainActor
struct LargeFileEditingTests {
    @Test(arguments: ["a", "界", "😀"], [0, 3])
    func highlightingFastPathsMatchByteBoundary(character: String, bomByteCount: Int) {
        let limit = WorkingTreeText.maximumHighlightedFileSize - bomByteCount
        let unitBytes = character.utf8.count
        for count in [limit / 3, limit / 3 + 1, limit / unitBytes, limit / unitBytes + 1, limit + 1] {
            let text = String(repeating: character, count: count)
            #expect(WorkingTreeText.shouldHighlight(text, bomByteCount: bomByteCount) == (text.utf8.count <= limit))
        }
    }

    @Test
    func documentHighlightingBoundaryTracksEditsAndBOM() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.swift")
        try (Data([0xef, 0xbb, 0xbf]) + Data(Self.source(bytes: 999_997).utf8)).write(to: file)
        let document = FileTabDocument(path: "source.swift", root: root.path)
        #expect(document.syntaxHighlightingEnabled)
        await document.loadIfNeeded()
        #expect(document.syntaxHighlightingEnabled)
        document.draft += "x"
        #expect(!document.syntaxHighlightingEnabled)
        #expect(!document.syntaxHighlightingEnabled)
        document.draft.removeLast()
        #expect(document.syntaxHighlightingEnabled)
    }

    @Test
    func fileTabSynchronizesExternalDraftAndPreservesUndo() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("let value = \"\u{212b}\"\n".utf8).write(to: root.appendingPathComponent("source.swift"))
        let document = FileTabDocument(path: "source.swift", root: root.path)
        await document.loadIfNeeded()
        let host = NSHostingView(rootView: FileTabView(document: document, lastWriter: { _ in nil },
            isFocused: false, openFile: { _, _ in }))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        func editor(_ view: NSView) -> CurrentLineTextView? {
            (view as? CurrentLineTextView) ?? view.subviews.lazy.compactMap { editor($0) }.first
        }
        let view = try #require(editor(host))
        let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
        defer { coordinator.highlights.cancel() }
        document.draft = "let value = \"\u{00c5}\"\n"
        try await wait { (view.string as NSString).isEqual(document.draft as NSString) }
        host.layoutSubtreeIfNeeded()
        #expect(Data(view.string.utf8) == Data(document.draft.utf8))
        view.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        #expect(document.draft.hasPrefix("xlet"))
        view.undoManager?.undo()
        #expect(Data(document.draft.utf8) == Data("let value = \"\u{00c5}\"\n".utf8))
    }

    @Test
    func fileTabPassesBOMToHighlightingBoundary() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try (Data([0xef, 0xbb, 0xbf]) + Data(Self.source(bytes: 999_998).utf8))
            .write(to: root.appendingPathComponent("source.swift"))
        let document = FileTabDocument(path: "source.swift", root: root.path)
        await document.loadIfNeeded()
        let host = NSHostingView(rootView: FileTabView(document: document, lastWriter: { _ in nil },
            isFocused: false, openFile: { _, _ in }))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        func editor(_ view: NSView) -> CurrentLineTextView? {
            (view as? CurrentLineTextView) ?? view.subviews.lazy.compactMap { editor($0) }.first
        }
        let view = try #require(editor(host))
        let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
        defer { coordinator.highlights.cancel() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(coordinator.highlights.path.isEmpty)
    }

    @Test
    func savesTwiceAfterGrowingPastEditingLimitAndReopensReadOnly() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("big.txt")
        try Data(repeating: 65, count: WorkingTreeText.maximumEditableFileSize).write(to: file)
        let document = FileTabDocument(path: "big.txt", root: root.path)
        await document.loadIfNeeded()
        document.draft += "x"
        #expect(try await document.save() == .saved)
        #expect(!document.isDirty)
        document.draft += "y"
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == Data(repeating: 65, count: WorkingTreeText.maximumEditableFileSize) + Data("xy".utf8))
        let reopened = FileTabDocument(path: "big.txt", root: root.path)
        await reopened.loadIfNeeded()
        #expect(reopened.isLoaded)
        #expect(reopened.isReadOnly)
        #expect(!reopened.isDirty)
        await #expect(throws: FileTabDocument.DocumentError.readOnly) { try await reopened.save() }
        #expect(try Data(contentsOf: file) == reopened.loadedDiskBytes)
    }

    @Test(arguments: [1_000_000, 1_000_001,
                      WorkingTreeText.maximumEditableFileSize - 1,
                      WorkingTreeText.maximumEditableFileSize,
                      WorkingTreeText.maximumEditableFileSize + 1,
                      WorkingTreeText.maximumReadableFileSize,
                      WorkingTreeText.maximumReadableFileSize + 1])
    func opensAndRoundTripsWithinHardLimit(bytes: Int) async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.swift")
        let bom = Data([0xef, 0xbb, 0xbf])
        let original = bom + Data(Self.source(bytes: bytes - bom.count, unit: "let café = \"é\"\r\n").utf8)
        #expect(original.count == bytes)
        try original.write(to: file)
        let document = FileTabDocument(path: file.lastPathComponent, root: root.path)
        await document.loadIfNeeded()
        if bytes > WorkingTreeText.maximumReadableFileSize {
            #expect(document.loadState == .tooLarge)
            #expect(document.draft.isEmpty)
            #expect(document.fileSize == bytes)
            return
        }
        #expect(document.isLoaded)
        #expect(!document.isDirty)
        #expect(WorkingTreeText.shouldHighlight(document.draft, bomByteCount: document.bom.count) == (bytes <= 1_000_000))
        if bytes > WorkingTreeText.maximumEditableFileSize {
            #expect(document.isReadOnly)
            #expect(document.bom == bom)
            #expect(document.loadedDiskBytes == original)
            let initial = document.draft
            document.draft = "変更"
            #expect(Data(document.draft.utf8) == Data(initial.utf8))
            #expect(!document.hasUnsavedChanges)
            #expect(!document.undoManager.canUndo)
            #expect(!document.undoManager.canRedo)
            await #expect(throws: FileTabDocument.DocumentError.readOnly) { try await document.save() }
            await #expect(throws: FileTabDocument.DocumentError.readOnly) { try await document.overwrite() }
            #expect(try Data(contentsOf: file) == original)
            return
        }
        #expect(!document.isReadOnly)
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == original)
        let initial = document.draft
        document.draft = "L" + initial.dropFirst()
        #expect(document.isDirty)
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == bom + Data(document.draft.utf8))
        document.draft = initial
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == original)
    }

    @Test(arguments: ["txt", "md", "html"])
    func readOnlyFileTabRejectsInputAndPasteButKeepsSelectionAndCopy(fileExtension suffix: String) async throws {
        _ = NSApplication.shared
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.\(suffix)")
        let original = Data(Self.source(bytes: 5_000_001).utf8)
        try original.write(to: file)
        let document = FileTabDocument(path: file.lastPathComponent, root: root.path)
        await document.loadIfNeeded()
        #expect(document.isReadOnly)
        if suffix == "md" {
            #expect(document.presentation == .source)
            #expect(!document.beginBlockEdit(range: 0..<3))
        } else { #expect(document.setPresentation(.source)) }
        let host = NSHostingView(rootView: FileTabView(document: document, lastWriter: { _ in nil },
            isFocused: false, openFile: { _, _ in }))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        func editor(_ view: NSView) -> CurrentLineTextView? {
            (view as? CurrentLineTextView) ?? view.subviews.lazy.compactMap { editor($0) }.first
        }
        let view = try #require(editor(host))
        let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
        defer { coordinator.highlights.cancel() }
        #expect(!view.isEditable)
        #expect(view.isSelectable)
        #expect(!view.allowsUndo)
        #expect(view.undoManager == nil)
        #expect(view.usesFindBar)
        #expect(view.isIncrementalSearchingEnabled)
        #expect(!view.shouldChangeText(in: NSRange(location: 0, length: 0), replacementString: "変更"))
        view.insertText("変更", replacementRange: NSRange(location: 0, length: 0))
        let pasteboard = NSPasteboard(name: .init("phlox-read-only-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        #expect(pasteboard.setString("貼付け", forType: .string))
        #expect(!view.readSelection(from: pasteboard))
        #expect(Data(view.string.utf8) == original)
        view.setSelectedRange(NSRange(location: 0, length: 3))
        #expect(view.selectedRange() == NSRange(location: 0, length: 3))
        pasteboard.clearContents()
        #expect(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        #expect(pasteboard.string(forType: .string) == "let")
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 800, height: 600),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        #expect(window.makeFirstResponder(view))
        let find = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "f",
            charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))
        view.keyDown(with: find)
        #expect(try #require(view.enclosingScrollView).isFindBarVisible)
        #expect(Data(view.string.utf8) == original)
        view.scrollRangeToVisible(NSRange(location: view.textStorage!.length - 1, length: 1))
        #expect(try #require(view.enclosingScrollView).contentView.bounds.minY > 0)
        #expect(!document.hasUnsavedChanges)
        await #expect(throws: FileTabDocument.DocumentError.readOnly) { try await document.save() }
        #expect(try Data(contentsOf: file) == original)
        try Data("外部変更".utf8).write(to: file)
        await document.loadIfNeeded()
        #expect(document.loadedDiskBytes == original)
        let reopened = FileTabDocument(path: file.lastPathComponent, root: root.path)
        await reopened.loadIfNeeded()
        #expect(reopened.draft == "外部変更")
        #expect(!reopened.isReadOnly)
    }

    @Test(arguments: [1_000_000, 1_000_001])
    func fileTabHighlightsWithNonContiguousLayout(bytes: Int) async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(Self.source(bytes: bytes).utf8).write(to: root.appendingPathComponent("source.swift"))
        let document = FileTabDocument(path: "source.swift", root: root.path)
        await document.loadIfNeeded()
        let host = NSHostingView(rootView: FileTabView(document: document, lastWriter: { _ in nil },
            isFocused: false, openFile: { _, _ in }))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        func editor(_ view: NSView) -> CurrentLineTextView? {
            if let text = view as? CurrentLineTextView { return text }
            return view.subviews.lazy.compactMap { editor($0) }.first
        }
        let view = try #require(editor(host))
        let coordinator = try #require(view.delegate as? CodeTextEditor.Coordinator)
        defer { coordinator.highlights.cancel() }
        #expect(view.layoutManager?.allowsNonContiguousLayout == true)
        var completed = false
        coordinator.highlights.onHighlightComplete = { _ in completed = true }
        if bytes <= WorkingTreeText.maximumHighlightedFileSize {
            try await wait { completed }
            let lastKeyword = (view.string as NSString).range(of: "let", options: .backwards).location
            #expect(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: lastKeyword, effectiveRange: nil) != nil)
        } else {
            try await Task.sleep(for: .milliseconds(100))
            #expect(!completed)
            #expect(coordinator.highlights.path.isEmpty)
        }
        #expect(!document.isDirty)
    }

    @Test(arguments: [1_000_000, 1_000_001])
    func includesBOMInHighlightingBoundary(bytes: Int) async throws {
        var text = Self.source(bytes: bytes - 3)
        let view = Self.view(text)
        let coordinator = CodeTextEditor.Coordinator(setText: { text = $0 })
        coordinator.bomByteCount = 3
        var completed = false
        var calculations = 0
        coordinator.highlights.onBackgroundCalculation = { _ in calculations += 1 }
        coordinator.highlights.onHighlightComplete = { _ in completed = true }
        coordinator.updateHighlights(view, path: "source.swift")
        defer { coordinator.highlights.cancel() }
        if bytes <= 1_000_000 {
            try await wait { completed }
            #expect(calculations == 1)
            #expect(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil)
        } else {
            #expect(coordinator.highlights.path.isEmpty, "色付け処理を予約しない")
            try await Task.sleep(for: .milliseconds(100))
            #expect(calculations == 0)
            #expect(!completed)
            #expect(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil)
        }
    }

    @Test
    func crossesSoftLimitAndRestoresHighlightingOnUndo() async throws {
        var text = Self.source(bytes: 1_000_000)
        let original = Data(text.utf8)
        let view = Self.view(text)
        let coordinator = CodeTextEditor.Coordinator(setText: { text = $0 })
        view.delegate = coordinator
        var completed = false
        var calculations = 0
        coordinator.highlights.onBackgroundCalculation = { _ in calculations += 1 }
        coordinator.highlights.onHighlightComplete = { _ in completed = true }
        coordinator.updateHighlights(view, path: "source.swift")
        defer { view.delegate = nil; coordinator.highlights.cancel() }
        try await wait { completed }
        let before = calculations
        completed = false
        view.insertText("x", replacementRange: NSRange(location: view.textStorage!.length, length: 0))
        #expect(text.utf8.count == 1_000_001)
        #expect(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(calculations == before)
        #expect(!completed)
        view.undoManager?.undo()
        #expect(Data(text.utf8) == original)
        try await wait { completed }
        #expect(calculations == before + 1)
        #expect(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil)
    }

    @Test
    func compositionCrossesSoftLimitAndHighlightingResumesAfterShrinking() async throws {
        var text = Self.source(bytes: 999_999)
        let original = Data(text.utf8)
        let view = Self.view(text)
        let coordinator = CodeTextEditor.Coordinator(setText: { text = $0 })
        view.delegate = coordinator
        view.onMarkedTextEnd = { coordinator.updateHighlights(view, path: "source.swift") }
        var completed = false
        var calculations = 0
        coordinator.highlights.onBackgroundCalculation = { _ in calculations += 1 }
        coordinator.highlights.onHighlightComplete = { _ in completed = true }
        coordinator.updateHighlights(view, path: "source.swift")
        defer { view.onMarkedTextEnd = nil; view.delegate = nil; coordinator.highlights.cancel() }
        try await wait { completed }
        let before = calculations
        completed = false
        let end = view.textStorage!.length
        view.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: end, length: 0))
        #expect(view.hasMarkedText())
        #expect(view.string.utf8.count > WorkingTreeText.maximumHighlightedFileSize)
        try await Task.sleep(for: .milliseconds(100))
        #expect(calculations == before)
        #expect(!completed)
        view.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(!view.hasMarkedText())
        #expect(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) == nil)
        #expect(calculations == before)
        view.insertText("", replacementRange: NSRange(location: end, length: 2))
        #expect(Data(text.utf8) == original)
        try await wait { completed }
        #expect(calculations == before + 1)
        #expect(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: 0, effectiveRange: nil) != nil)
    }

    @Test
    func largeSourceEditsAndUndoesWithoutHighlightWork() async throws {
        var text = Self.source(bytes: 1_000_001)
        let original = Data(text.utf8)
        let view = Self.view(text)
        let coordinator = CodeTextEditor.Coordinator(setText: { text = $0 })
        view.delegate = coordinator
        var calculations = 0
        coordinator.highlights.onBackgroundCalculation = { _ in calculations += 1 }
        coordinator.updateHighlights(view, path: "source.swift")
        defer { view.delegate = nil; coordinator.highlights.cancel() }
        view.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        #expect(Data(text.utf8) == Data("x".utf8) + original)
        view.undoManager?.undo()
        #expect(Data(text.utf8) == original)
        try await Task.sleep(for: .milliseconds(100))
        #expect(calculations == 0)
        #expect(coordinator.highlights.path.isEmpty)
    }

    @Test
    func textViewEditsPreserveDecomposedBytesThroughUndoAndSave() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("source.swift")
        let bom = Data([0xef, 0xbb, 0xbf])
        let original = bom + Data(Self.source(bytes: 1_000_001, unit: "let café = \"é\"\r\n").utf8)
        try original.write(to: file)
        let document = FileTabDocument(path: "source.swift", root: root.path)
        await document.loadIfNeeded()
        let view = Self.view(document.draft)
        let coordinator = CodeTextEditor.Coordinator(setText: { document.draft = $0 })
        coordinator.bomByteCount = bom.count
        view.delegate = coordinator
        coordinator.updateHighlights(view, path: document.path)
        defer { view.delegate = nil; coordinator.highlights.cancel() }
        let replacement = "e\u{0301}"
        view.insertText(replacement, replacementRange: NSRange(location: 0, length: 1))
        let edited = bom + Data(replacement.utf8) + original.dropFirst(bom.count + 1)
        #expect(document.isDirty)
        #expect(bom + Data(document.draft.utf8) == edited)
        view.undoManager?.undo()
        #expect(!document.isDirty)
        #expect(bom + Data(document.draft.utf8) == original)
        view.undoManager?.redo()
        #expect(document.isDirty)
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == edited)
        #expect(!document.isDirty)
        #expect(coordinator.highlights.path.isEmpty)
    }

    @Test
    func largeMarkdownRemainsSourceOnly() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("large.md")
        let bytes = Data(Self.source(bytes: 1_000_001, unit: "# 見出し\n本文\n").utf8)
        try bytes.write(to: file)
        let document = FileTabDocument(path: file.lastPathComponent, root: root.path)
        await document.loadIfNeeded()
        #expect(document.isLoaded)
        #expect(document.markdownPresentationLocked)
        #expect(document.presentation == .source)
        #expect(!document.setPresentation(.rendered))
        #expect(try await document.save() == .saved)
        #expect(try Data(contentsOf: file) == bytes)
    }

    private static func source(bytes: Int, unit: String = "let value = 42\n") -> String {
        String(repeating: unit, count: bytes / unit.utf8.count)
            + String(repeating: " ", count: bytes % unit.utf8.count)
    }

    private static func view(_ text: String) -> CurrentLineTextView {
        let view = CurrentLineTextView(usingTextLayoutManager: false)
        view.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        view.allowsUndo = true
        view.string = text
        return view
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CompletionError.timeout }
            try await Task.sleep(for: .milliseconds(1))
        }
    }

    private enum CompletionError: Error { case timeout }
}
