import Foundation
import Testing
import PhloxCore
import Features

/// task-10 受け入れテスト。段階8bのユーザー指示でAC-6-18へ更新。
/// 画像添付 UI 統合の観測可能な振る舞いを凍結する:
///  1. 画像添付: 最大4枚・1枚20MB・計80MB。超過画像だけを弾いてメッセージ表示。送信で SendRequest.images に載せ、
///     成功でクリア・失敗で復元。
/// 旧バッチ全拒否契約からの変更根拠は0029-ios-redesign-8b-attachments.mdに記録。
@MainActor
struct SubAgentAndAttachmentAcceptanceTests {
    private func makeSession(status: SessionStatus = .idle) -> Session {
        Session(
            id: "s1", name: "Rose", agent: .claudeCode, status: status,
            subtitle: "proj", updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func image(mib: Double, mediaType: String = "image/png") -> SendAttachment {
        let bytes = Int(mib * 1024 * 1024)
        return SendAttachment(mediaType: mediaType, data: paddedImage(bytes: bytes))
    }

    // MARK: - 1. 画像添付の検証

    @Test("4枚までの妥当な添付を受け入れる")
    func acceptsUpToFourValidAttachments() {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())

        vm.addAttachments([image(mib: 1), image(mib: 1), image(mib: 1), image(mib: 1)])

        #expect(vm.attachments.count == 4)
        #expect(vm.attachmentError == nil)
    }

    @Test("5枚目だけを弾いてエラーを表示する")
    func rejectsBatchExceedingCountLimit() {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())

        vm.addAttachments([image(mib: 1), image(mib: 1), image(mib: 1), image(mib: 1), image(mib: 1)])

        #expect(vm.attachments.count == 4, "先頭4枚は保持する")
        #expect(vm.attachmentError == "画像は最大4枚までです。1枚20MB・合計80MBまで添付できます。")
    }

    @Test("1枚20MB超の添付は弾く")
    func rejectsOversizedSingleAttachment() {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())

        vm.addAttachments([image(mib: 20_000_001.0 / (1024 * 1024))])

        #expect(vm.attachments.isEmpty)
        #expect(vm.attachmentError != nil)
    }

    @Test("超過画像だけを除外し既存画像・有効画像・本文を保持する")
    func rejectsOnlyOversizedImage() {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())
        vm.inputText = "本文"
        vm.inputCursorUTF16 = vm.inputText.utf16.count
        let existing = image(mib: 1)
        vm.addAttachments([existing])
        let existingItem = vm.attachmentItems[0]
        let valid = image(mib: 0.5)
        // 受理可能な画像と20MBを1バイト超える画像のバッチ。
        vm.addAttachments([valid, image(mib: 20_000_001.0 / (1024 * 1024))])

        #expect(vm.attachments == [existing, valid])
        #expect(vm.attachmentItems[0] == existingItem)
        #expect(vm.inputText == "本文 [Image #1] [Image #2] ")
        #expect(vm.attachmentError == "画像は1枚あたり20MBまでです")
    }

    // MARK: - 2. 添付つき送信

    @Test("添付つき送信は SendRequest.images に載る")
    func sendCarriesAttachmentsAsImages() async {
        let api = MockAPI(sendOutcome: .success(SendResult(accepted: true)))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.inputText = "見て"
        vm.inputCursorUTF16 = vm.inputText.utf16.count
        vm.addAttachments([image(mib: 1)])

        await vm.sendMessage()

        #expect(await api.lastSentRequest?.images.count == 1)
    }

    @Test("送信成功で添付をクリアする")
    func clearsAttachmentsOnSendSuccess() async {
        let api = MockAPI(sendOutcome: .success(SendResult(accepted: true)))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.inputText = "見て"
        vm.inputCursorUTF16 = vm.inputText.utf16.count
        vm.addAttachments([image(mib: 1)])

        await vm.sendMessage()

        #expect(vm.attachments.isEmpty, "送信成功後は添付をクリアする")
    }

    @Test("送信失敗で添付とテキストを復元する")
    func restoresAttachmentsAndTextOnSendFailure() async {
        let api = MockAPI(sendOutcome: .failure(.unreachable))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.inputText = "見て"
        vm.inputCursorUTF16 = vm.inputText.utf16.count
        vm.addAttachments([image(mib: 1)])

        await vm.sendMessage()

        #expect(vm.attachments.count == 1, "失敗時は添付を復元する")
        #expect(vm.inputText == "見て [Image #1] ", "失敗時はテキストを復元する")
    }
}

private func paddedImage(bytes: Int) -> Data {
    var data = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")!
    data.append(Data(count: max(0, bytes - data.count)))
    return data
}
