import AppKit
import DesignSystem
import SwiftUI
import Testing
@testable import DashboardFeature

@Suite("閲覧のみの長い行の省略", .serialized)
struct ReadOnlyTextTests {
    @Test(arguments: [10_000, 10_001])
    func threshold(length: Int) {
        let source = String(repeating: "a", count: length)
        let preview = ReadOnlyText(source)
        let display = preview.display(locale: Locale(identifier: "ja"), bundle: .main)
        #expect(preview.hasOmittedLines == (length > 10_000))
        #expect(display.text == (length == 10_000 ? source : String(repeating: "a", count: 10_000) + "…（残り 1 文字を省略）"))
        #expect(display.markers.count == (length == 10_000 ? 0 : 1))
    }

    @Test(arguments: ["😀", "e\u{301}", "👨‍👩‍👧‍👦"])
    func keepsGraphemeBoundary(character: String) {
        let prefix = String(repeating: "a", count: 9_999)
        let preview = ReadOnlyText(prefix + character + "b\r\n最後")
        let display = preview.display(locale: Locale(identifier: "ja"), bundle: .main)
        #expect(display.text == prefix + "…（残り 2 文字を省略）\r\n最後")
        #expect(display.markers == [NSRange(location: 9_999, length: "…（残り 2 文字を省略）".utf16.count)])
    }

    @Test func preservesLineBreaksAndMultipleMarkers() {
        let first = String(repeating: "a", count: 10_000)
        let second = String(repeating: "😀", count: 5_000)
        let display = ReadOnlyText("先頭\r\n" + first + "a\r\n\r" + second + "😀😀\n末尾\n")
            .display(locale: Locale(identifier: "ja"), bundle: .main)
        #expect(display.text == "先頭\r\n" + first + "…（残り 1 文字を省略）\r\n\r" + second + "…（残り 2 文字を省略）\n末尾\n")
        #expect(display.markers.count == 2)
        #expect(ReadOnlyText("").display(locale: .current, bundle: .main).text.isEmpty)
    }

    @Test @MainActor func projectionKeepsDocumentAndDiskAndCopiesDisplayedText() async throws {
        _ = NSApplication.shared
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("long.txt")
        let source = "先頭\r\n" + String(repeating: "a", count: 5_000_001) + "隠す末尾\r\n最後\n"
        let original = Data([0xef, 0xbb, 0xbf]) + Data(source.utf8)
        try original.write(to: file)
        let document = FileTabDocument(path: file.lastPathComponent, root: root.path)
        await document.loadIfNeeded()
        let preview = try #require(document.readOnlyText)
        #expect(preview.hasOmittedLines)
        let display = preview.display(locale: Locale(identifier: "ja"), bundle: .main)
        let host = NSHostingView(rootView: FileTabView(document: document, lastWriter: { _ in nil },
            isFocused: false, openFile: { _, _ in }).environment(\.locale, Locale(identifier: "ja")))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        func editor(_ view: NSView) -> NSTextView? {
            if let view = view as? NSTextView { return view }
            return view.subviews.lazy.compactMap { editor($0) }.first
        }
        let view = try #require(editor(host))
        #expect(view.string == display.text)
        #expect(!(view.string as NSString).contains("隠す末尾"))
        #expect(view.usesFindBar && view.isIncrementalSearchingEnabled)
        let marker = try #require(display.markers.first)
        #expect(view.layoutManager?.temporaryAttribute(.foregroundColor, atCharacterIndex: marker.location,
            effectiveRange: nil) as? NSColor == NSColor(DSColor.textTertiary))
        view.setSelectedRange(NSRange(location: 0, length: view.string.utf16.count))
        let pasteboard = NSPasteboard(name: .init("phlox-long-line-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.declareTypes(view.writablePasteboardTypes, owner: nil)
        #expect(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        #expect(pasteboard.string(forType: .string) == display.text)
        document.draft = "変更は禁止"
        await #expect(throws: FileTabDocument.DocumentError.readOnly) { try await document.save() }
        await #expect(throws: FileTabDocument.DocumentError.readOnly) { try await document.overwrite() }
        #expect(document.draft == source)
        #expect(document.loadedDiskBytes == original)
        #expect(!document.hasUnsavedChanges)
        #expect(try Data(contentsOf: file) == original)
        try Data("外部変更".utf8).write(to: file)
        await document.loadIfNeeded()
        #expect(document.draft == source)
        #expect(document.loadedDiskBytes == original)
        let reopened = FileTabDocument(path: file.lastPathComponent, root: root.path)
        await reopened.loadIfNeeded()
        #expect(reopened.draft == "外部変更")
        #expect(reopened.readOnlyText == nil)
        withExtendedLifetime(host) {}
    }

    @Test @MainActor func editableLongLineIsNotProjected() async throws {
        let root = try makeFileTabTestRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = String(repeating: "a", count: 10_001)
        try Data(source.utf8).write(to: root.appendingPathComponent("editable.txt"))
        let document = FileTabDocument(path: "editable.txt", root: root.path)
        await document.loadIfNeeded()
        #expect(!document.isReadOnly)
        #expect(document.readOnlyText == nil)
        #expect(document.draft == source)
    }
}
