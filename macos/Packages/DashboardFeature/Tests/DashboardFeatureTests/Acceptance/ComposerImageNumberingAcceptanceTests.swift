// task-2 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-2.md — macOS composer の画像添付に番号を振り、
// 本文のカーソル位置へ `[Image #N]` を挿入する。
//
// アサーションは変更禁止。ただしテストハーネス自体の欠陥を見つけた場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 注意: NSPasteboard.general を汚さないため、一意な名前付きペーストボードを使い、
// テスト終了時に releaseGlobally する。

import AppKit
import Foundation
import Testing
@testable import SessionFeature

private let tinyPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

@Suite("task-2: composer 添付の番号付けと本文プレースホルダ")
struct ComposerImageNumberingAcceptanceTests {

    private func makeImagePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("phlox.test.numbering.\(UUID().uuidString)"))
        pasteboard.clearContents()
        pasteboard.setData(tinyPNG, forType: NSPasteboard.PasteboardType("public.png"))
        return pasteboard
    }

    private func image(_ byte: UInt8) -> Data {
        Data([byte])
    }

    // MARK: - 採番（ComposerAttachmentStore）

    @Test @MainActor
    func addImage_assignsSequentialNumbersAndReturnsTheAddedAttachment() {
        let store = ComposerAttachmentStore()

        let first = store.addImage(data: image(1), mediaType: "image/png")
        let second = store.addImage(data: image(2), mediaType: "image/png")

        #expect(first?.number == 1)
        #expect(second?.number == 2)
        #expect(store.attachments.map(\.number) == [1, 2])
    }

    @Test @MainActor
    func removingAnAttachment_doesNotRenumberTheRemainingOnes() throws {
        let store = ComposerAttachmentStore()
        store.addImage(data: image(1), mediaType: "image/png")
        let second = store.addImage(data: image(2), mediaType: "image/png")
        store.addImage(data: image(3), mediaType: "image/png")

        store.remove(id: try #require(second).id)

        #expect(store.attachments.map(\.number) == [1, 3])
        let fourth = store.addImage(data: image(4), mediaType: "image/png")
        #expect(fourth?.number == 4)
    }

    @Test @MainActor
    func clear_restartsNumberingFromOne() {
        let store = ComposerAttachmentStore()
        store.addImage(data: image(1), mediaType: "image/png")
        store.addImage(data: image(2), mediaType: "image/png")

        store.clear()

        #expect(store.addImage(data: image(3), mediaType: "image/png")?.number == 1)
    }

    @Test @MainActor
    func rejectedImage_returnsNilAndKeepsAttachmentsUnchanged() {
        let store = ComposerAttachmentStore()
        let tooLarge = Data(count: ComposerAttachmentStore.maxBytesPerImage + 1)

        let result = store.addImage(data: tooLarge, mediaType: "image/png")

        #expect(result == nil)
        #expect(store.attachments.isEmpty)
        #expect(store.lastError == "画像は1枚あたり4MiBまでです")
    }

    // MARK: - 本文からプレースホルダを消したら添付も外れる（task-4）

    @Test @MainActor
    func removingPlaceholderFromText_detachesThatImageOnly() {
        let store = ComposerAttachmentStore()
        store.addImage(data: image(1), mediaType: "image/png")
        store.addImage(data: image(2), mediaType: "image/png")

        let removed = store.removeAttachmentsMissing(
            fromOldText: "[Image #1] [Image #2] hi",
            newText: "[Image #2] hi"
        )

        #expect(removed == [1])
        #expect(store.attachments.map(\.number) == [2])
    }

    @Test @MainActor
    func removingAllPlaceholders_detachesEverything() {
        let store = ComposerAttachmentStore()
        store.addImage(data: image(1), mediaType: "image/png")
        store.addImage(data: image(2), mediaType: "image/png")

        store.removeAttachmentsMissing(fromOldText: "[Image #1] [Image #2] ", newText: "")

        #expect(store.attachments.isEmpty)
    }

    @Test @MainActor
    func unrelatedTextEdit_keepsAttachments() {
        let store = ComposerAttachmentStore()
        store.addImage(data: image(1), mediaType: "image/png")

        let removed = store.removeAttachmentsMissing(
            fromOldText: "[Image #1] hi",
            newText: "[Image #1] hello"
        )

        #expect(removed.isEmpty)
        #expect(store.attachments.map(\.number) == [1])
    }

    @Test @MainActor
    func attachmentNotReferencedByTheOldText_isNeverDetached() {
        // Control API 経由などで積まれた、本文に紐づかない添付を誤って外さない。
        let store = ComposerAttachmentStore()
        store.addImage(data: image(1), mediaType: "image/png")

        let removed = store.removeAttachmentsMissing(fromOldText: "hi", newText: "hello")

        #expect(removed.isEmpty)
        #expect(store.attachments.map(\.number) == [1])
    }

    @Test @MainActor
    func justInsertedPlaceholder_isNotDetached() {
        let store = ComposerAttachmentStore()
        store.addImage(data: image(1), mediaType: "image/png")

        let removed = store.removeAttachmentsMissing(fromOldText: "hi", newText: "hi [Image #1] ")

        #expect(removed.isEmpty)
        #expect(store.attachments.map(\.number) == [1])
    }

    // MARK: - チップ表示

    @Test @MainActor
    func chipPresentation_showsNumberBadgeAndKeepsExistingTitle() {
        let named = ComposerAttachment(number: 3, data: image(1), mediaType: "image/png", filename: "shot.png")
        let unnamed = ComposerAttachment(number: 1, data: image(1), mediaType: "image/png")

        #expect(ComposerAttachmentChipPresentation.badge(for: named) == "#3")
        #expect(ComposerAttachmentChipPresentation.badge(for: unnamed) == "#1")
        #expect(ComposerAttachmentChipPresentation.title(for: named) == "shot.png")
        #expect(ComposerAttachmentChipPresentation.title(for: unnamed) == "image/png")
    }

    // MARK: - ペースト → カーソル位置へ挿入

    @Test @MainActor
    func attachedOutcome_insertsPlaceholderAtCursorAndMovesCaret() {
        let pasteboard = makeImagePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "見て"
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.onPasteImageOutcome = { _, _ in .attached(number: 1) }

        let handled = textView.handlePaste(from: pasteboard)

        #expect(handled == true)
        #expect(textView.string == "見て [Image #1] ")
        #expect(textView.selectedRange().location == 14)
    }

    @Test @MainActor
    func attachedOutcome_insertsInTheMiddleOfExistingText() {
        let pasteboard = makeImagePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "ab"
        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.onPasteImageOutcome = { _, _ in .attached(number: 2) }

        #expect(textView.handlePaste(from: pasteboard) == true)
        #expect(textView.string == "a [Image #2] b")
        #expect(textView.selectedRange().location == 13)
    }

    @Test @MainActor
    func rejectedOutcome_suppressesTextPasteButLeavesTextUntouched() {
        let pasteboard = makeImagePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "見て"
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.onPasteImageOutcome = { _, _ in .rejected }

        #expect(textView.handlePaste(from: pasteboard) == true)
        #expect(textView.string == "見て")
    }

    @Test @MainActor
    func unsupportedOutcome_fallsBackToTextPasteAndLeavesTextUntouched() {
        let pasteboard = makeImagePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "見て"
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.onPasteImageOutcome = { _, _ in .unsupported }

        #expect(textView.handlePaste(from: pasteboard) == false)
        #expect(textView.string == "見て")
    }

    @Test @MainActor
    func outcomeHandler_takesPrecedenceOverLegacyHandler() {
        let pasteboard = makeImagePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        var legacyInvoked = false
        textView.onPasteImage = { _, _ in
            legacyInvoked = true
            return true
        }
        textView.onPasteImageOutcome = { _, _ in .attached(number: 1) }

        #expect(textView.handlePaste(from: pasteboard) == true)
        #expect(legacyInvoked == false)
        #expect(textView.string == "[Image #1] ")
    }

    @Test @MainActor
    func withoutOutcomeHandler_legacyPasteBehaviourIsUnchanged() {
        let pasteboard = makeImagePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "見て"
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.onPasteImage = { _, _ in true }

        #expect(textView.handlePaste(from: pasteboard) == true)
        #expect(textView.string == "見て")
    }

    @Test @MainActor
    func textOnlyPasteboard_doesNotInvokeOutcomeHandler() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("phlox.test.numbering.\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("plain text", forType: .string)

        let textView = IMESafeTextView.SubmitAwareTextView()
        var invoked = false
        textView.onPasteImageOutcome = { _, _ in
            invoked = true
            return .attached(number: 1)
        }

        #expect(textView.handlePaste(from: pasteboard) == false)
        #expect(invoked == false)
        #expect(textView.string == "")
    }
}
