import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite("添付バッジ ViewModel 白箱")
struct SessionAttachmentBadgeTests {
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

    private func image() -> SendAttachment {
        SendAttachment(mediaType: "image/png", data: Data(count: 1024))
    }

    @Test("添付つき送信後にメッセージ突き合わせで枚数を保持する")
    func sendWithAttachmentsReconcilesAfterRefresh() async {
        let api = MockAPI(
            sendOutcome: .success(SendResult(accepted: true)),
            messagesOutcome: .success([])
        )
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        // 添付は本文へ `[Image #N]` を挿入するため、送信テキストはプレースホルダを含む。
        vm.inputText = "写真です"
        vm.inputCursorUTF16 = vm.inputText.utf16.count
        vm.addAttachments([image(), image()])
        #expect(vm.inputText == "写真です [Image #1] [Image #2] ")

        await vm.sendMessage()

        // sendMessage は本文を trim して送るので、サーバーが返す user メッセージも trim 済み。
        await api.setMessagesOutcome(.success([
            .user(id: "m1", text: "写真です [Image #1] [Image #2]"),
        ]))
        await vm.refresh()

        #expect(vm.attachmentImageCount(forMessageID: "m1") == 2)
    }

    @Test("添付なし送信では side-map に載せない")
    func sendWithoutAttachmentsDoesNotMap() async {
        let api = MockAPI(
            sendOutcome: .success(SendResult(accepted: true)),
            messagesOutcome: .success([.user(id: "m1", text: "テキストのみ")])
        )
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.inputText = "テキストのみ"

        await vm.sendMessage()

        #expect(vm.attachmentImageCount(forMessageID: "m1") == nil)
    }
}
