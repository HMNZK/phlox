import AppKit
import SwiftUI
import Testing
@testable import DashboardFeature

@Test("ソースの行間を広げても行番号と本文の文字を同じ高さへ描く", arguments: [(10, false), (30, false), (11, true)]) @MainActor
func codeEditorLineNumbersMatchTextBaselines(lineCount: Int, startsWithBlankLine: Bool) async throws {
    let source = (1...lineCount).map { startsWithBlankLine && $0 == 1 ? "" : String($0) }.joined(separator: "\n")
        + (startsWithBlankLine ? "" : "\n")
    let host = NSHostingView(rootView: CodeTextEditor(text: .constant(source)))
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
