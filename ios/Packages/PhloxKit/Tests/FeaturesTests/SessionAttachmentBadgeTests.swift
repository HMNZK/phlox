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
        SendAttachment(mediaType: "image/png", data: Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")!)
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

    @Test("破損画像の送信を中止し本文と添付を保持する")
    func invalidImagePreservesDraftForRetry() async {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())
        vm.inputText = "この画像を見て"
        vm.addAttachments([SendAttachment(mediaType: "image/png", data: Data([1, 2, 3]))])
        let text = vm.inputText
        let items = vm.attachmentItems
        await vm.sendMessage()
        #expect(vm.inputText == text)
        #expect(vm.attachmentItems == items)
        #expect(vm.attachmentError == "画像を読み込めませんでした")
        #expect(vm.sendState == .failed("画像を読み込めませんでした"))
    }
}
