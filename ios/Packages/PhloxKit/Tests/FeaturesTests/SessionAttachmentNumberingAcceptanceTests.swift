// task-3 受け入れテスト（PM 著・実装役は編集禁止）
// 契約: tasks/task-3.md — iOS の添付に番号を振り、本文のカーソル位置へ
// `[Image #N]` を挿入する。表記・規則は task-1 の ComposerImagePlaceholder に従う。
//
// アサーションは変更禁止。ただしテストハーネス自体の欠陥を見つけた場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite("task-3: iOS 添付の番号付けと本文プレースホルダ")
struct SessionAttachmentNumberingAcceptanceTests {

    private func makeSession() -> Session {
        Session(
            id: "s1",
            name: "Rose",
            agent: .claudeCode,
            status: .idle,
            subtitle: "proj",
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func makeViewModel() -> SessionDetailViewModel {
        SessionDetailViewModel(session: makeSession(), api: MockAPI())
    }

    private func image(bytes: Int = 1024) -> SendAttachment {
        SendAttachment(mediaType: "image/png", data: Data(count: bytes))
    }

    // MARK: - 採番

    @Test
    func addAttachments_assignsSequentialNumbersWithinABatch() {
        let vm = makeViewModel()

        vm.addAttachments([image(), image()])

        #expect(vm.attachmentItems.map(\.number) == [1, 2])
    }

    @Test
    func addAttachments_continuesNumberingAcrossBatches() {
        let vm = makeViewModel()

        vm.addAttachments([image()])
        vm.addAttachments([image(), image()])

        #expect(vm.attachmentItems.map(\.number) == [1, 2, 3])
    }

    @Test
    func removeAttachment_doesNotRenumberTheRemainingOnes() {
        let vm = makeViewModel()
        vm.addAttachments([image(), image(), image()])

        vm.removeAttachment(at: 1)

        #expect(vm.attachmentItems.map(\.number) == [1, 3])
        vm.addAttachments([image()])
        #expect(vm.attachmentItems.map(\.number) == [1, 3, 4])
    }

    // MARK: - 本文への挿入

    @Test
    func addAttachments_insertsPlaceholderAtCursor() {
        let vm = makeViewModel()
        vm.inputText = "見て"
        vm.inputCursorUTF16 = 2

        vm.addAttachments([image()])

        #expect(vm.inputText == "見て [Image #1] ")
        #expect(vm.inputCursorUTF16 == 14)
    }

    @Test
    func addAttachments_insertsInTheMiddleOfExistingText() {
        let vm = makeViewModel()
        vm.inputText = "ab"
        vm.inputCursorUTF16 = 1

        vm.addAttachments([image()])

        #expect(vm.inputText == "a [Image #1] b")
        #expect(vm.inputCursorUTF16 == 13)
    }

    @Test
    func addAttachments_insertsOnePlaceholderPerImageInABatch() {
        let vm = makeViewModel()

        vm.addAttachments([image(), image()])

        #expect(vm.inputText == "[Image #1] [Image #2] ")
        #expect(vm.inputCursorUTF16 == 22)
    }

    @Test
    func addAttachments_whenBatchIsRejected_leavesTheTextUntouched() {
        let vm = makeViewModel()
        vm.inputText = "見て"
        vm.inputCursorUTF16 = 2

        // 1枚あたりの上限超過でバッチ全体を弾く（既存セマンティクス）。
        vm.addAttachments([image(bytes: SessionDetailViewModel.maxAttachmentBytesPerImage + 1)])

        #expect(vm.attachmentItems.isEmpty)
        #expect(vm.inputText == "見て")
        #expect(vm.inputCursorUTF16 == 2)
        #expect(vm.attachmentError != nil)
    }

    @Test
    func addAttachments_rejectedBatchDoesNotConsumeNumbers() {
        let vm = makeViewModel()
        vm.addAttachments([image()])

        vm.addAttachments([image(bytes: SessionDetailViewModel.maxAttachmentBytesPerImage + 1)])
        vm.addAttachments([image()])

        #expect(vm.attachmentItems.map(\.number) == [1, 2])
    }

    // MARK: - 削除で本文からも消える

    @Test
    func removeAttachment_removesOnlyItsOwnPlaceholder() {
        let vm = makeViewModel()
        vm.addAttachments([image(), image()])
        #expect(vm.inputText == "[Image #1] [Image #2] ")

        vm.removeAttachment(at: 0)

        #expect(vm.inputText == "[Image #2] ")
        #expect(vm.attachmentItems.map(\.number) == [2])
    }

    @Test
    func removeAttachment_keepsCursorWithinTheText() {
        let vm = makeViewModel()
        vm.addAttachments([image()])
        vm.inputCursorUTF16 = vm.inputText.utf16.count

        vm.removeAttachment(at: 0)

        #expect(vm.inputText == "")
        #expect(vm.inputCursorUTF16 <= vm.inputText.utf16.count)
    }

    @Test
    func removeAttachment_outOfRangeIndexChangesNothing() {
        let vm = makeViewModel()
        vm.addAttachments([image()])
        let textBefore = vm.inputText

        vm.removeAttachment(at: 5)

        #expect(vm.attachmentItems.map(\.number) == [1])
        #expect(vm.inputText == textBefore)
    }
}
