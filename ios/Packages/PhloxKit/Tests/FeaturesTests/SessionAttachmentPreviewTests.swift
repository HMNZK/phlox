import Foundation
import Testing
import PhloxCore
@testable import Features

@MainActor
@Suite("添付サムネイル ViewModel 白箱")
struct SessionAttachmentPreviewTests {
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

    @Test("添付つき送信後にメッセージ突き合わせで各サムネイルを保持する")
    func sendWithAttachmentsReconcilesAfterRefresh() async {
        let api = MockAPI(
            sendOutcome: .success(SendResult(accepted: true)),
            messagesOutcome: .success([])
        )
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.inputText = "写真です"
        vm.inputCursorUTF16 = vm.inputText.utf16.count
        vm.addAttachments([image(), image()])
        #expect(vm.inputText == "写真です [Image #1] [Image #2] ")

        await vm.sendMessage()

        await api.setMessagesOutcome(.success([
            .user(id: "m1", text: "写真です [Image #1] [Image #2]"),
        ]))
        await vm.refresh()

        let previews = vm.attachmentPreviews(forMessageID: "m1")
        #expect(previews.count == 2)
        #expect(previews.allSatisfy { !$0.isEmpty })
    }

    @Test("添付なし送信ではサムネイルを割り当てない")
    func sendWithoutAttachmentsDoesNotMap() async {
        let api = MockAPI(
            sendOutcome: .success(SendResult(accepted: true)),
            messagesOutcome: .success([.user(id: "m1", text: "テキストのみ")])
        )
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.inputText = "テキストのみ"

        await vm.sendMessage()

        #expect(vm.attachmentPreviews(forMessageID: "m1").isEmpty)
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
