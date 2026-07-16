import Foundation
import Testing
import PhloxCore
import Features

/// task-10 受け入れテスト（PM 著・実装役はアサーション編集禁止）。
/// API 拡張の閲覧・添付系 UI 統合の観測可能な振る舞いを凍結する:
///  1. 画像添付: 最大4枚・1枚4MiB・計8MiB。超過は弾いてメッセージ表示。送信で SendRequest.images に載せ、
///     成功でクリア・失敗で復元。
///  2. サブエージェント解決: api.subAgents の markerMessageID で行→subAgentID を解決。不一致・旧サーバーは nil。
///  3. サブエージェント詳細: SubAgentDetailViewModel.load() が api.subAgentMessages をチャットに反映。
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
        return SendAttachment(mediaType: mediaType, data: Data(count: bytes))
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

    @Test("1枚4MiB超の添付は弾く")
    func rejectsOversizedSingleAttachment() {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())

        vm.addAttachments([image(mib: 5)])

        #expect(vm.attachments.isEmpty)
        #expect(vm.attachmentError != nil)
    }

    @Test("合計8MiB超の添付は弾く")
    func rejectsBatchExceedingTotalLimit() {
        let vm = SessionDetailViewModel(session: makeSession(), api: MockAPI())

        // 各3MiB（1枚上限内）だが合計9MiB > 8MiB。
        vm.addAttachments([image(mib: 3), image(mib: 3), image(mib: 3)])

        #expect(vm.attachments.isEmpty)
        #expect(vm.attachmentError != nil)
    }

    // MARK: - 2. 添付つき送信

    @Test("添付つき送信は SendRequest.images に載る")
    func sendCarriesAttachmentsAsImages() async {
        let api = MockAPI(sendOutcome: .success(SendResult(accepted: true)))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.addAttachments([image(mib: 1)])
        vm.inputText = "見て"

        await vm.sendMessage()

        #expect(await api.lastSentRequest?.images.count == 1)
    }

    @Test("送信成功で添付をクリアする")
    func clearsAttachmentsOnSendSuccess() async {
        let api = MockAPI(sendOutcome: .success(SendResult(accepted: true)))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.addAttachments([image(mib: 1)])
        vm.inputText = "見て"

        await vm.sendMessage()

        #expect(vm.attachments.isEmpty, "送信成功後は添付をクリアする")
    }

    @Test("送信失敗で添付とテキストを復元する")
    func restoresAttachmentsAndTextOnSendFailure() async {
        let api = MockAPI(sendOutcome: .failure(.unreachable))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)
        vm.addAttachments([image(mib: 1)])
        vm.inputText = "見て"

        await vm.sendMessage()

        #expect(vm.attachments.count == 1, "失敗時は添付を復元する")
        #expect(vm.inputText == "見て", "失敗時はテキストを復元する")
    }

    // MARK: - 3. サブエージェント解決

    @Test("markerMessageID 一致で subAgentID を解決する")
    func resolvesSubAgentIDByMarker() async {
        let api = MockAPI()
        await api.setSubAgentsOutcome(.success([
            SubAgentSummary(id: "sa1", name: "explore", status: .running, messageCount: 3, markerMessageID: "m1")
        ]))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        let resolved = await vm.resolveSubAgentID(forMessageID: "m1")

        #expect(resolved == "sa1")
    }

    @Test("markerMessageID 不一致では解決しない")
    func doesNotResolveOnMarkerMismatch() async {
        let api = MockAPI()
        await api.setSubAgentsOutcome(.success([
            SubAgentSummary(id: "sa1", name: "explore", status: .running, messageCount: 3, markerMessageID: "m1")
        ]))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        let resolved = await vm.resolveSubAgentID(forMessageID: "mX")

        #expect(resolved == nil)
    }

    @Test("subAgents が旧サーバー（501）でも解決せずクラッシュしない")
    func doesNotResolveOnOldServer() async {
        let api = MockAPI()
        await api.setSubAgentsOutcome(.failure(.server(status: 501, message: "未対応")))
        let vm = SessionDetailViewModel(session: makeSession(), api: api)

        let resolved = await vm.resolveSubAgentID(forMessageID: "m1")

        #expect(resolved == nil)
    }

    // MARK: - 4. サブエージェント詳細

    @Test("SubAgentDetailViewModel.load() が subAgentMessages をチャットに反映する")
    func subAgentDetailLoadsMessages() async {
        let api = MockAPI()
        let messages: [ChatMessage] = [.agent(id: "sm1", text: "サブ回答")]
        await api.setSubAgentMessagesOutcome(.success(messages))
        let vm = SubAgentDetailViewModel(session: makeSession(), subAgentID: "sa1", api: api)

        await vm.load()

        #expect(vm.chatMessages == messages)
    }
}
