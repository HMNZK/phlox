// task-3 白箱テスト（実装役が追加）。採番・プレースホルダ挿入/削除の境界を ViewModel 層で検証する。

import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite("task-3: SessionDetailViewModel 添付番号 whitebox")
struct SessionAttachmentNumberingWhiteboxTests {

    private func makeViewModel() -> SessionDetailViewModel {
        SessionDetailViewModel(
            session: Session(
                id: "s1",
                name: "Rose",
                agent: .claudeCode,
                status: .idle,
                subtitle: "proj",
                updatedAt: Date(timeIntervalSince1970: 0)
            ),
            api: MockAPI()
        )
    }

    private func image(bytes: Int = 1024) -> SendAttachment {
        SendAttachment(mediaType: "image/png", data: Data(count: bytes))
    }

    @Test
    func addAttachments_emptyBatchIsNoOp() {
        let vm = makeViewModel()
        vm.addAttachments([])
        #expect(vm.attachmentItems.isEmpty)
        #expect(vm.inputText.isEmpty)
    }

    @Test
    func addAttachments_rejectedByCountLimitDoesNotMutateTextOrCursor() {
        let vm = makeViewModel()
        vm.inputText = "draft"
        vm.inputCursorUTF16 = 3
        vm.addAttachments(Array(repeating: image(), count: SessionDetailViewModel.maxAttachmentCount + 1))

        #expect(vm.attachmentItems.isEmpty)
        #expect(vm.inputText == "draft")
        #expect(vm.inputCursorUTF16 == 3)
        #expect(vm.attachmentError != nil)
    }

    @Test
    func removeAttachment_clampsCursorWhenTextShrinks() {
        let vm = makeViewModel()
        vm.addAttachments([image()])
        vm.inputCursorUTF16 = vm.inputText.utf16.count

        vm.removeAttachment(at: 0)

        #expect(vm.inputText.isEmpty)
        #expect(vm.inputCursorUTF16 == 0)
    }

    @Test
    func addAttachments_batchInsertsPlaceholdersAtSameCursorAdvancingEachTime() {
        let vm = makeViewModel()
        vm.inputText = "x"
        vm.inputCursorUTF16 = 0

        vm.addAttachments([image(), image()])

        #expect(vm.inputText == "[Image #1] [Image #2] x")
        #expect(vm.inputCursorUTF16 == 22)
    }
}
