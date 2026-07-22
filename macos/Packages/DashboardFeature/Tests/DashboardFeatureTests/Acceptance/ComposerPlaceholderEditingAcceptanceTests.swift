// task-5 / task-6 受け入れテスト（PM 著・実装役は編集禁止）
// 契約:
//   tasks/task-5.md — 本文の `[Image #N]` は打鍵1回でトークンごとまとめて消える
//   tasks/task-6.md — `[Image #N]` を含む選択のコピーで、画像もクリップボードへ載る
//
// アサーションは変更禁止。ただしテストハーネス自体の欠陥を見つけた場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 注意: NSPasteboard.general を汚さないため、一意な名前付きペーストボードを使い、
// テスト終了時に releaseGlobally する。

import AgentDomain
import AppKit
import Foundation
import Testing
@testable import SessionFeature

@Suite("task-5/6: プレースホルダのトークン単位削除と画像コピー")
struct ComposerPlaceholderEditingAcceptanceTests {

    private func makeTextView(_ text: String, cursor: Int, numbers: [Int]) -> IMESafeTextView.SubmitAwareTextView {
        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = text
        textView.setSelectedRange(NSRange(location: cursor, length: 0))
        textView.attachedImageNumbers = { numbers }
        return textView
    }

    private func makePasteboard() -> NSPasteboard {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("phlox.test.editing.\(UUID().uuidString)"))
        pasteboard.clearContents()
        return pasteboard
    }

    // MARK: - Backspace はトークンごと消す（task-5）

    @Test @MainActor
    func backspaceAtTheEndOfAPlaceholder_deletesTheWholeToken() {
        let textView = makeTextView("[Image #1] テスト", cursor: 10, numbers: [1])

        textView.deleteBackward(nil)

        #expect(textView.string == "テスト")
        #expect(textView.selectedRange().location == 0)
    }

    @Test @MainActor
    func backspaceInTheMiddleOfAPlaceholder_deletesTheWholeToken() {
        // "[Image #1] テスト [Image #2]" の "#2" の "2" の直後。
        let textView = makeTextView("[Image #1] テスト [Image #2]", cursor: 24, numbers: [1, 2])

        textView.deleteBackward(nil)

        #expect(textView.string == "[Image #1] テスト")
    }

    @Test @MainActor
    func backspaceOutsideAnyPlaceholder_deletesOneCharacterAsUsual() {
        let textView = makeTextView("[Image #1] テスト", cursor: 14, numbers: [1])

        textView.deleteBackward(nil)

        #expect(textView.string == "[Image #1] テス")
    }

    @Test @MainActor
    func backspaceAtTheStartOfAPlaceholder_deletesOneCharacterAsUsual() {
        let textView = makeTextView("a [Image #1]", cursor: 2, numbers: [1])

        textView.deleteBackward(nil)

        #expect(textView.string == "a[Image #1]")
    }

    @Test @MainActor
    func forwardDeleteAtTheStartOfAPlaceholder_deletesTheWholeToken() {
        let textView = makeTextView("[Image #1] テスト", cursor: 0, numbers: [1])

        textView.deleteForward(nil)

        #expect(textView.string == "テスト")
    }

    @Test @MainActor
    func withoutAttachedNumbers_backspaceIsUnchanged() {
        // 添付が無ければ本文中の `[Image #1]` はただの文字列。特別扱いしない。
        let textView = makeTextView("[Image #1]", cursor: 10, numbers: [])

        textView.deleteBackward(nil)

        #expect(textView.string == "[Image #1")
    }

    @Test @MainActor
    func withASelection_backspaceIsUnchanged() {
        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "a [Image #1] b"
        textView.attachedImageNumbers = { [1] }
        textView.setSelectedRange(NSRange(location: 0, length: 2))

        textView.deleteBackward(nil)

        #expect(textView.string == "[Image #1] b")
    }

    @Test @MainActor
    func tokenDeletion_matchesTheChipRemovalPath() {
        // 打鍵経路とチップ × 経路（ComposerImagePlaceholder.removing）で本文が食い違わない。
        let source = "a [Image #1] b"
        let textView = makeTextView(source, cursor: 12, numbers: [1])

        textView.deleteBackward(nil)

        #expect(textView.string == ComposerImagePlaceholder.removing(number: 1, from: source))
    }

    // MARK: - 選択はトークンを分断しない（task-7）

    /// 実アプリと同じ配線（Coordinator を delegate に付けた NSTextView）を組む。
    /// 選択の吸着は個々のコマンドの override ではなく delegate の1箇所で守っているため、
    /// delegate 無しの素の text view ではこの契約は成立しない。
    @MainActor
    private func makeWiredTextView(
        _ text: String,
        cursor: Int,
        numbers: [Int]
    ) -> (IMESafeTextView.SubmitAwareTextView, IMESafeTextView.Coordinator, NSWindow) {
        let representable = IMESafeTextView(
            text: .constant(text),
            isComposing: .constant(false),
            measuredHeight: .constant(0),
            minHeight: 0,
            maxHeight: 1000,
            onSubmit: {}
        )
        let coordinator = IMESafeTextView.Coordinator(representable)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let textView = IMESafeTextView.SubmitAwareTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.attachedImageNumbers = { numbers }
        textView.delegate = coordinator
        window.contentView = textView
        textView.string = text
        textView.setSelectedRange(NSRange(location: cursor, length: 0))
        return (textView, coordinator, window)
    }

    @Test @MainActor
    func shiftLeftFromTheEndOfAPlaceholder_selectsTheWholeToken() {
        let (textView, _, _) = makeWiredTextView("x [Image #1] y", cursor: 12, numbers: [1])

        textView.moveLeftAndModifySelection(nil)

        #expect(textView.selectedRange() == NSRange(location: 2, length: 10))
    }

    @Test @MainActor
    func shiftRightAfterSelectingAToken_shrinksBackToTheCaret() {
        // 伸ばした選択を同じ回数で戻せること（トークンに吸い付いて戻せない状態にしない）。
        let (textView, _, _) = makeWiredTextView("x [Image #1] y", cursor: 12, numbers: [1])

        textView.moveLeftAndModifySelection(nil)
        textView.moveRightAndModifySelection(nil)

        #expect(textView.selectedRange() == NSRange(location: 12, length: 0))
    }

    @Test @MainActor
    func shiftLeftTwice_selectsTheTokenAndOneMoreCharacter() {
        let (textView, _, _) = makeWiredTextView("x [Image #1] y", cursor: 12, numbers: [1])

        textView.moveLeftAndModifySelection(nil)
        textView.moveLeftAndModifySelection(nil)

        #expect(textView.selectedRange() == NSRange(location: 1, length: 11))
    }

    @Test @MainActor
    func shiftRightFromTheStartOfAPlaceholder_selectsTheWholeToken() {
        let (textView, _, _) = makeWiredTextView("x [Image #1] y", cursor: 2, numbers: [1])

        textView.moveRightAndModifySelection(nil)

        #expect(textView.selectedRange() == NSRange(location: 2, length: 10))
    }

    @Test @MainActor
    func theCaretCanNeverSitInsideAToken() {
        // shift 無しの ← やマウスクリックで内側に入れてしまうと、そこを起点にした選択が
        // トークンを分断したままになる。選択変更の1箇所で守っているので入り込めない。
        let (textView, _, _) = makeWiredTextView("x [Image #1] y", cursor: 12, numbers: [1])

        textView.moveLeft(nil)

        #expect(textView.selectedRange() == NSRange(location: 2, length: 0))
    }

    @Test @MainActor
    func clickingIntoTheMiddleOfAToken_snapsOutOfIt() {
        let (textView, _, _) = makeWiredTextView("x [Image #1] y", cursor: 0, numbers: [1])

        textView.setSelectedRange(NSRange(location: 7, length: 0))

        #expect(!ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(
            textView.selectedRange().location, in: textView.string, numbers: [1]
        ))
    }

    @Test @MainActor
    func shiftUpAcrossAToken_doesNotLeaveItSplit() {
        // shift+Enter で複数行になる。上下の選択も同じ規則で守られること。
        let (textView, _, _) = makeWiredTextView("aaa\n[Image #1]\nbbb", cursor: 18, numbers: [1])

        textView.moveUpAndModifySelection(nil)

        let selection = textView.selectedRange()
        #expect(!ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(
            selection.lowerBound, in: textView.string, numbers: [1]
        ))
        #expect(!ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(
            selection.upperBound, in: textView.string, numbers: [1]
        ))
    }

    @Test @MainActor
    func optionShiftLeftAcrossAToken_doesNotLeaveItSplit() {
        let (textView, _, _) = makeWiredTextView("x [Image #1] y", cursor: 12, numbers: [1])

        textView.moveWordLeftAndModifySelection(nil)

        let selection = textView.selectedRange()
        #expect(!ComposerImagePlaceholder.selectionEdgeSplitsPlaceholder(
            selection.lowerBound, in: textView.string, numbers: [1]
        ))
    }

    @Test @MainActor
    func shiftLeftOutsideAnyPlaceholder_selectsOneCharacterAsUsual() {
        let (textView, _, _) = makeWiredTextView("x [Image #1] y", cursor: 14, numbers: [1])

        textView.moveLeftAndModifySelection(nil)

        #expect(textView.selectedRange() == NSRange(location: 13, length: 1))
    }

    @Test @MainActor
    func withoutAttachedNumbers_shiftLeftSelectsOneCharacter() {
        let (textView, _, _) = makeWiredTextView("x [Image #1] y", cursor: 12, numbers: [])

        textView.moveLeftAndModifySelection(nil)

        #expect(textView.selectedRange() == NSRange(location: 11, length: 1))
    }

    // MARK: - コピーで画像も載る（task-6）

    @Test @MainActor
    func copyingASelectionWithAPlaceholder_putsTheImageOnThePasteboard() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "見て [Image #1] です"
        textView.attachedImageNumbers = { [1] }
        textView.imagesForCopy = { numbers in
            numbers.map { _ in (data: Data([0x89, 0x50]), mediaType: "image/png") }
        }
        textView.setSelectedRange(NSRange(location: 3, length: 10))

        #expect(textView.writeSelectionWithImages(to: pasteboard) == true)
        #expect(pasteboard.string(forType: .string) == "[Image #1]")
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) == Data([0x89, 0x50]))
    }

    @Test @MainActor
    func copyingASelectionWithoutAPlaceholder_fallsBackToPlainCopy() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "見て [Image #1] です"
        textView.attachedImageNumbers = { [1] }
        textView.imagesForCopy = { _ in [(data: Data([0x89]), mediaType: "image/png")] }
        textView.setSelectedRange(NSRange(location: 0, length: 2))

        #expect(textView.writeSelectionWithImages(to: pasteboard) == false)
    }

    @Test @MainActor
    func copyingWithAnEmptySelection_fallsBackToPlainCopy() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "[Image #1]"
        textView.attachedImageNumbers = { [1] }
        textView.imagesForCopy = { _ in [(data: Data([0x89]), mediaType: "image/png")] }
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        #expect(textView.writeSelectionWithImages(to: pasteboard) == false)
    }

    @Test @MainActor
    func copyingMultiplePlaceholders_putsEveryImageOnThePasteboard() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "[Image #1] [Image #2]"
        textView.attachedImageNumbers = { [1, 2] }
        textView.imagesForCopy = { numbers in
            numbers.map { (data: Data([UInt8($0)]), mediaType: "image/png") }
        }
        textView.setSelectedRange(NSRange(location: 0, length: 21))

        #expect(textView.writeSelectionWithImages(to: pasteboard) == true)
        let pngs = pasteboard.pasteboardItems?.compactMap {
            $0.data(forType: NSPasteboard.PasteboardType("public.png"))
        }
        #expect(pngs == [Data([1]), Data([2])])
    }

    @Test @MainActor
    func copyingAPlaceholderWhoseImageIsGone_fallsBackToPlainCopy() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "[Image #1]"
        textView.attachedImageNumbers = { [1] }
        textView.imagesForCopy = { _ in [] }
        textView.setSelectedRange(NSRange(location: 0, length: 10))

        #expect(textView.writeSelectionWithImages(to: pasteboard) == false)
    }

    @Test @MainActor
    func copyingAnUnsupportedMediaType_fallsBackToPlainCopy() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "[Image #1]"
        textView.attachedImageNumbers = { [1] }
        textView.imagesForCopy = { _ in [(data: Data([1]), mediaType: "image/heic")] }
        textView.setSelectedRange(NSRange(location: 0, length: 10))

        // 載せられない形式なら通常コピーへ委ねる（テキストまで失わせない）。
        #expect(textView.writeSelectionWithImages(to: pasteboard) == false)
    }

    @Test @MainActor
    func cutSelectionWithAPlaceholder_writesTheImageAndRemovesTheText() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.string = "見て [Image #1] です"
        textView.attachedImageNumbers = { [1] }
        textView.imagesForCopy = { _ in [(data: Data([0x89]), mediaType: "image/png")] }
        textView.setSelectedRange(NSRange(location: 3, length: 10))

        #expect(textView.writeSelectionWithImages(to: pasteboard) == true)
        #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("public.png")) == Data([0x89]))
    }

    // MARK: - 自分でコピーしたものを貼り戻す（task-6）

    @Test @MainActor
    func pastingBackOwnCopy_doesNotSwallowTheSelectedText() {
        // テキストと画像を両方持つ pasteboard を画像として横取りすると、本文が丸ごと捨てられる。
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        let item = NSPasteboardItem()
        item.setString("見て [Image #1] です", forType: .string)
        item.setData(Data([0x89, 0x50]), forType: NSPasteboard.PasteboardType("public.png"))
        pasteboard.writeObjects([item])

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.attachedImageNumbers = { [1] }
        var attachInvoked = false
        textView.onPasteImageOutcome = { _, _ in
            attachInvoked = true
            return .attached(number: 2)
        }

        // false = 通常のテキストペーストに委ねる（本文が保たれる）。
        #expect(textView.handlePaste(from: pasteboard) == false)
        #expect(attachInvoked == false)
    }

    @Test @MainActor
    func pastingAPlainImage_stillAttaches() {
        let pasteboard = makePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setData(Data([0x89, 0x50]), forType: NSPasteboard.PasteboardType("public.png"))

        let textView = IMESafeTextView.SubmitAwareTextView()
        textView.attachedImageNumbers = { [1] }
        textView.onPasteImageOutcome = { _, _ in .attached(number: 2) }

        #expect(textView.handlePaste(from: pasteboard) == true)
        #expect(textView.string == "[Image #2] ")
    }

    // MARK: - ストアからの画像取り出し（task-6）

    @Test @MainActor
    func imagesForCopy_returnsOnlyTheRequestedNumbersInAttachmentOrder() {
        let store = ComposerAttachmentStore()
        store.addImage(data: Data([1]), mediaType: "image/png")
        store.addImage(data: Data([2]), mediaType: "image/jpeg")
        store.addImage(data: Data([3]), mediaType: "image/png")

        let images = store.imagesForCopy(numbers: [3, 1])

        #expect(images.map(\.data) == [Data([1]), Data([3])])
        #expect(images.map(\.mediaType) == ["image/png", "image/png"])
    }
}
