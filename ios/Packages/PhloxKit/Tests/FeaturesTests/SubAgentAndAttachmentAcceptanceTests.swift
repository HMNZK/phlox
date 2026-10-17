import Foundation
import Testing
import PhloxCore
import Features

/// task-10 受け入れテスト（PM 著・実装役はアサーション編集禁止）。
/// 画像添付 UI 統合の観測可能な振る舞いを凍結する:
///  1. 画像添付: 最大4枚・1枚4MiB・計8MiB。超過は弾いてメッセージ表示。送信で SendRequest.images に載せ、
///     成功でクリア・失敗で復元。
/// 添付の上限違反は「バッチ全体を弾く」契約（部分採用しない）。
/// acceptance_tests のアサーションは変更禁止。ハーネス欠陥は PM 承認のうえ MockAPI 部分のみ修理可。
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

    @Test("5枚目を含むバッチは弾いてエラーを表示する")
    func rejectsBatchExceedingCountLimit() {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())

        vm.addAttachments([image(mib: 1), image(mib: 1), image(mib: 1), image(mib: 1), image(mib: 1)])

        #expect(vm.attachments.count <= 4, "上限を超えて保持しない")
        #expect(vm.attachmentError != nil, "超過理由を表示する")
    }

    @Test("1枚20MB超の添付は弾く")
    func rejectsOversizedSingleAttachment() {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())

        vm.addAttachments([image(mib: 20_000_001.0 / (1024 * 1024))])

        #expect(vm.attachments.isEmpty)
        #expect(vm.attachmentError != nil)
    }

    @Test("超過画像を含むバッチは部分採用しない")
    func rejectsBatchContainingOversizedImage() {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())

        // 受理可能な画像と20MBを1バイト超える画像のバッチ。
        vm.addAttachments([image(mib: 1), image(mib: 20_000_001.0 / (1024 * 1024))])

        #expect(vm.attachments.isEmpty)
        #expect(vm.attachmentError != nil)
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
