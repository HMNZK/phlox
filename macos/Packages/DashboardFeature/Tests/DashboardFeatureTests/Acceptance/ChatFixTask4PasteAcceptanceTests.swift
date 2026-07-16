// task-4 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-4.md — チャット composer への画像ペースト経路（cmd+V）。
// 保留中は LOOPFLOW_PENDING_TASK4=1 で suite ごとスキップできる（PM の検証運用用。実装役は使わない）。
//
// 注意: NSPasteboard.general を汚さないため、一意な名前付きペーストボードを使い、
// テスト終了時に releaseGlobally する。

import AppKit
import Foundation
import Testing
@testable import SessionFeature

private let tinyPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

@Suite(
    "ChatFix task-4: composer 画像ペースト経路",
    .enabled(if: ProcessInfo.processInfo.environment["LOOPFLOW_PENDING_TASK4"] != "1")
)
struct ChatFixTask4PasteAcceptanceTests {

    private func makePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("phlox.test.task4.\(UUID().uuidString)"))
    }

    @Test @MainActor
    func pngPasteboard_invokesOnPasteImage_andSuppressesTextPaste() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(tinyPNG, forType: NSPasteboard.PasteboardType("public.png"))

        let textView = IMESafeTextView.SubmitAwareTextView()
        var received: (data: Data, mediaType: String)?
        textView.onPasteImage = { data, mediaType in
            received = (data, mediaType)
            return true // 対応エージェント（添付成功）
        }

        let handled = textView.handlePaste(from: pasteboard)
        #expect(handled == true)
        #expect(received?.data == tinyPNG)
        #expect(received?.mediaType == "image/png")
    }

    @Test @MainActor
    func pngPasteboard_unsupportedAgent_fallsBackToTextPaste() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setData(tinyPNG, forType: NSPasteboard.PasteboardType("public.png"))

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.onPasteImage = { _, _ in false } // 非対応エージェント（添付拒否）

        #expect(textView.handlePaste(from: pasteboard) == false)
    }

    @Test @MainActor
    func textOnlyPasteboard_doesNotInvokeOnPasteImage() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("plain text", forType: .string)

        let textView = IMESafeTextView.SubmitAwareTextView()
        var invoked = false
        textView.onPasteImage = { _, _ in
            invoked = true
            return true
        }

        #expect(textView.handlePaste(from: pasteboard) == false)
        #expect(invoked == false)
    }

    @Test @MainActor
    func tiffPasteboard_isConvertedToPNG() throws {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        // 有効な 1x1 TIFF を生成（NSImage 経由の変換経路を通す）
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        let tiff = try #require(image.tiffRepresentation)

        pasteboard.clearContents()
        pasteboard.setData(tiff, forType: NSPasteboard.PasteboardType("public.tiff"))

        let textView = IMESafeTextView.SubmitAwareTextView()
        var received: (data: Data, mediaType: String)?
        textView.onPasteImage = { data, mediaType in
            received = (data, mediaType)
            return true
        }

        #expect(textView.handlePaste(from: pasteboard) == true)
        #expect(received?.mediaType == "image/png")
        let pngMagic = Data([0x89, 0x50, 0x4E, 0x47])
        #expect(received?.data.prefix(4) == pngMagic)
    }
}
