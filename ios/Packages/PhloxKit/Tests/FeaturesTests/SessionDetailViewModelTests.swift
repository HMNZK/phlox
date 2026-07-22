import XCTest
import PhloxCore
@testable import Features

// E4-6 / E4-8 検証。出力取得・入力バー有効制御・折りたたみ上限・送信（楽観更新/失敗復元）を検証する。
@MainActor
final class SessionDetailViewModelTests: XCTestCase {

    private func session(_ status: SessionStatus) -> Session {
        Session(id: "s1", name: "Rose", agent: .claudeCode, status: status, subtitle: "", updatedAt: Date(timeIntervalSince1970: 0))
    }

    // MARK: - E4-6

    func testLoadOutputReflectsText() async {
        let vm = SessionDetailViewModel(session: session(.running), api: MockAPI(outputOutcome: .success("hello\nworld")))
        await vm.loadOutput()
        XCTAssertEqual(vm.outputText, "hello\nworld")
        XCTAssertNil(vm.loadError)
    }

    func testLoadOutputErrorSetsLoadError() async {
        let vm = SessionDetailViewModel(session: session(.running), api: MockAPI(outputOutcome: .failure(.unreachable)))
        await vm.loadOutput()
        XCTAssertNotNil(vm.loadError)
    }

    func testInputEnabledForInteractiveStatuses() {
        XCTAssertTrue(SessionDetailViewModel(session: session(.awaitingApproval(prompt: "p")), api: MockAPI()).inputEnabled)
        XCTAssertTrue(SessionDetailViewModel(session: session(.running), api: MockAPI()).inputEnabled)
        XCTAssertTrue(SessionDetailViewModel(session: session(.idle), api: MockAPI()).inputEnabled)
    }

    func testInputDisabledForTerminalStatuses() {
        XCTAssertFalse(SessionDetailViewModel(session: session(.completed(exitCode: 0)), api: MockAPI()).inputEnabled)
        XCTAssertFalse(SessionDetailViewModel(session: session(.error(message: "e")), api: MockAPI()).inputEnabled)
        XCTAssertFalse(SessionDetailViewModel(session: session(.starting), api: MockAPI()).inputEnabled)
    }

    func testTruncateKeepsLastLinesWhenOverLimit() {
        let text = (1...600).map { "line\($0)" }.joined(separator: "\n")
        let truncated = SessionDetailViewModel.truncate(text, maxLines: 500)
        let lines = truncated.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertTrue(truncated.contains("省略"))
        XCTAssertLessThanOrEqual(lines.count, 501)
        XCTAssertTrue(truncated.contains("line600"))
        XCTAssertFalse(truncated.contains("line1\n"))
    }

    func testTruncateNoOpUnderLimit() {
        let text = "a\nb\nc"
        XCTAssertEqual(SessionDetailViewModel.truncate(text, maxLines: 500), text)
    }

    // MARK: - 構造化チャット / フォールバック（CH-4）

    func testLoadShowsChatWhenMessagesPresent() async {
        let vm = SessionDetailViewModel(
            session: session(.running),
            api: MockAPI(messagesOutcome: .success([.agent(id: "a1", text: "hi")]))
        )
        await vm.load()
        XCTAssertTrue(vm.showsChat)
        XCTAssertEqual(vm.chatMessages, [.agent(id: "a1", text: "hi")])
    }

    func testLoadFallsBackToTerminalWhenMessagesEmpty() async {
        let vm = SessionDetailViewModel(
            session: session(.running),
            api: MockAPI(outputOutcome: .success("terminal text"), messagesOutcome: .success([]))
        )
        await vm.load()
        XCTAssertFalse(vm.showsChat)
        XCTAssertEqual(vm.outputText, "terminal text")
    }

    func testLoadFallsBackToTerminalWhenMessagesNotFound() async {
        let vm = SessionDetailViewModel(
            session: session(.running),
            api: MockAPI(outputOutcome: .success("terminal text"), messagesOutcome: .failure(.notFound))
        )
        await vm.load()
        XCTAssertFalse(vm.showsChat)
        XCTAssertEqual(vm.outputText, "terminal text")
    }

    // MARK: - ポーリング更新（refresh）

    func testRefreshUpdatesChatMessagesWhenNewArrive() async {
        let mock = MockAPI(messagesOutcome: .success([.agent(id: "a1", text: "hi")]))
        let vm = SessionDetailViewModel(session: session(.running), api: mock)
        await vm.load()
        XCTAssertEqual(vm.chatMessages.map(\.id), ["a1"])
        // エージェントの遅延応答が増えたケース
        await mock.setMessagesOutcome(.success([.agent(id: "a1", text: "hi"), .agent(id: "a2", text: "yo")]))
        await vm.refresh()
        XCTAssertEqual(vm.chatMessages.map(\.id), ["a1", "a2"], "新着メッセージが反映される")
    }

    func testRefreshKeepsChatOnTransientFailure() async {
        let mock = MockAPI(messagesOutcome: .success([.agent(id: "a1", text: "hi")]))
        let vm = SessionDetailViewModel(session: session(.running), api: mock)
        await vm.load()
        XCTAssertTrue(vm.showsChat)
        // ポーリング中の一時的な取得失敗
        await mock.setMessagesOutcome(.failure(.unreachable))
        await vm.refresh()
        XCTAssertTrue(vm.showsChat, "一時的な失敗ではチャットを消さない")
        XCTAssertEqual(vm.chatMessages.map(\.id), ["a1"], "既存メッセージを維持")
    }

    func testRefreshClearsLoadErrorWhenOutputRecovers() async {
        let mock = MockAPI(
            outputOutcome: .failure(.unreachable),
            messagesOutcome: .success([])
        )
        let vm = SessionDetailViewModel(session: session(.running), api: mock)
        await vm.load()
        XCTAssertNotNil(vm.loadError)

        await mock.setOutputOutcome(.success("recovered output"))
        await vm.refresh()

        XCTAssertNil(vm.loadError, "output 取得が回復したらエラーバナーを消す")
        XCTAssertEqual(vm.outputText, "recovered output")
    }

    func testRefreshClearsLoadErrorWhenMessagesArrive() async {
        let mock = MockAPI(
            outputOutcome: .failure(.unreachable),
            messagesOutcome: .success([])
        )
        let vm = SessionDetailViewModel(session: session(.running), api: mock)
        await vm.load()
        XCTAssertNotNil(vm.loadError)

        await mock.setMessagesOutcome(.success([.agent(id: "m1", text: "こんにちは")]))
        await vm.refresh()

        XCTAssertNil(vm.loadError, "messages が取れたらエラーバナーを消す")
        XCTAssertEqual(vm.chatMessages, [.agent(id: "m1", text: "こんにちは")])
    }

    // MARK: - E4-8 送信

    func testSendMessageSuccessClearsInputAndReturnsToIdle() async {
        let vm = SessionDetailViewModel(session: session(.running), api: MockAPI(sendOutcome: .success(SendResult(accepted: true))))
        vm.inputText = "やってください"
        await vm.sendMessage()
        XCTAssertEqual(vm.inputText, "", "成功時は入力をクリア（楽観更新）")
        XCTAssertEqual(vm.sendState, .idle, "送信完了ステータスは表示しない（バナー廃止）")
    }

    func testSendMessageFailureRestoresInput() async {
        let vm = SessionDetailViewModel(session: session(.running), api: MockAPI(sendOutcome: .failure(.unreachable)))
        vm.inputText = "送信したい内容"
        await vm.sendMessage()
        XCTAssertEqual(vm.inputText, "送信したい内容", "失敗時は入力を復元（再送可能）")
        if case .failed = vm.sendState {} else { XCTFail("expected .failed") }
    }

    func testSendMessageIgnoresEmptyInput() async {
        let mock = MockAPI()
        let vm = SessionDetailViewModel(session: session(.running), api: mock)
        vm.inputText = "   "
        await vm.sendMessage()
        let count = await mock.sendCount
        XCTAssertEqual(count, 0, "空入力では send を呼ばない")
    }

    func testInputBarEnabledReflectsStatusAndNotSending() {
        let running = SessionDetailViewModel(session: session(.running), api: MockAPI())
        XCTAssertTrue(running.isInputBarEnabled)
        let completed = SessionDetailViewModel(session: session(.completed(exitCode: 0)), api: MockAPI())
        XCTAssertFalse(completed.isInputBarEnabled)
    }

    func testIsVisibleExcludesWhitespaceOnlyMessages() {
        XCTAssertFalse(SessionDetailViewModel.isVisible(.agent(id: "a1", text: "  \n")))
        XCTAssertFalse(SessionDetailViewModel.isVisible(.subAgent(id: "s1", text: "")))
        XCTAssertTrue(SessionDetailViewModel.isVisible(.subAgent(id: "s2", text: "running")))
    }

    // MARK: - task-9 セッション操作

    func testStopCallsInterruptWhenRunning() async {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: session(.running), api: api)
        await vm.stop()
        let interruptCount = await api.interruptCount
        XCTAssertEqual(interruptCount, 1)
    }

    func testStopIgnoredWhenNotRunning() async {
        let api = MockAPI()
        let vm = SessionDetailViewModel(session: session(.idle), api: api)
        await vm.stop()
        await vm.stop()
        let interruptCount = await api.interruptCount
        XCTAssertEqual(interruptCount, 0)
    }

    func testInterrupt409DisablesWithoutLoadError() async {
        let api = MockAPI()
        await api.setInterruptOutcome(.failure(.server(status: 409, message: "interrupt unsupported")))
        let vm = SessionDetailViewModel(session: session(.running), api: api)
        await vm.stop()
        XCTAssertFalse(vm.canInterrupt)
        XCTAssertNil(vm.loadError)
    }

    func testUsageFetchedOnRunningToIdleTransition() async {
        let api = MockAPI(messagesOutcome: .success([]))
        await api.setSessions([session(.idle)])
        await api.setUsageOutcome(.success(TurnUsage(costUSD: 0.5, contextUsedTokens: 50, contextWindowTokens: 100)))
        let vm = SessionDetailViewModel(session: session(.running), api: api)
        await vm.refresh()
        XCTAssertEqual(vm.turnUsage?.costUSD, 0.5)
        let usageCount = await api.usageCount
        XCTAssertEqual(usageCount, 1)
    }

    func testUsageNotFetchedWhileStillRunning() async {
        let api = MockAPI(messagesOutcome: .success([]))
        await api.setSessions([session(.running)])
        await api.setUsageOutcome(.success(TurnUsage(costUSD: 0.99, contextUsedTokens: 1, contextWindowTokens: 2)))
        let vm = SessionDetailViewModel(session: session(.running), api: api)
        await vm.refresh()
        let usageCount = await api.usageCount
        XCTAssertEqual(usageCount, 0)
        XCTAssertNil(vm.turnUsage)
    }

    func testSnapshotReplacesMessagesOnRefresh() async {
        let api = MockAPI(messagesOutcome: .success([.agent(id: "stale", text: "古い")]))
        let snapshot = MessagesDelta(
            messages: [.user(id: "m1", text: "q"), .agent(id: "m2", text: "a")],
            cursor: "c1",
            isSnapshot: true
        )
        await api.setMessagesDeltaScript([.success(snapshot)])
        let vm = SessionDetailViewModel(session: session(.idle), api: api)
        await vm.refresh()
        XCTAssertEqual(vm.chatMessages.map(\.id), ["m1", "m2"])
    }

    func testDeltaAppendsAndCarriesCursor() async {
        let api = MockAPI(messagesOutcome: .success([]))
        let snapshot = MessagesDelta(messages: [.agent(id: "m1", text: "1")], cursor: "c1", isSnapshot: true)
        let delta = MessagesDelta(messages: [.agent(id: "m2", text: "2")], cursor: "c2", isSnapshot: false)
        await api.setMessagesDeltaScript([.success(snapshot), .success(delta)])
        let vm = SessionDetailViewModel(session: session(.idle), api: api)
        await vm.refresh()
        await vm.refresh()
        XCTAssertEqual(vm.chatMessages.map(\.id), ["m1", "m2"])
        let deltaSinceLog = await api.deltaSinceLog
        XCTAssertEqual(deltaSinceLog, [nil, "c1"])
    }

    func testFallsBackToFullMessagesOn501() async {
        let fallback: [ChatMessage] = [.agent(id: "f1", text: "fallback")]
        let api = MockAPI(messagesOutcome: .success(fallback))
        let vm = SessionDetailViewModel(session: session(.idle), api: api)
        await vm.refresh()
        XCTAssertEqual(vm.chatMessages, fallback)
        let deltaSinceLog = await api.deltaSinceLog
        XCTAssertFalse(deltaSinceLog.isEmpty)
    }

    func testFallsBackToFullMessagesOn404() async {
        let fallback: [ChatMessage] = [.agent(id: "f2", text: "404")]
        let api = MockAPI(messagesOutcome: .success(fallback))
        await api.setMessagesDeltaScript([.failure(.notFound)])
        let vm = SessionDetailViewModel(session: session(.idle), api: api)
        await vm.refresh()
        XCTAssertEqual(vm.chatMessages, fallback)
    }

    func testDeltaDeduplicatesRepeatedMessageIDs() async {
        let api = MockAPI(messagesOutcome: .success([]))
        let snapshot = MessagesDelta(messages: [.agent(id: "m1", text: "1")], cursor: "c1", isSnapshot: true)
        let duplicate = MessagesDelta(messages: [.agent(id: "m1", text: "1 again")], cursor: "c2", isSnapshot: false)
        await api.setMessagesDeltaScript([.success(snapshot), .success(duplicate)])
        let vm = SessionDetailViewModel(session: session(.idle), api: api)
        await vm.refresh()
        await vm.refresh()
        XCTAssertEqual(vm.chatMessages.count, 1)
        XCTAssertEqual(vm.chatMessages.first?.id, "m1")
    }

    func testDeltaOverlapReplacesAsSnapshotFallback() async {
        let api = MockAPI(messagesOutcome: .success([]))
        let snapshot = MessagesDelta(messages: [.agent(id: "m1", text: "1")], cursor: "c1", isSnapshot: true)
        let overlap = MessagesDelta(
            messages: [.agent(id: "m1", text: "1"), .agent(id: "m2", text: "2")],
            cursor: "c0",
            isSnapshot: false
        )
        await api.setMessagesDeltaScript([.success(snapshot), .success(overlap)])
        let vm = SessionDetailViewModel(session: session(.idle), api: api)
        await vm.refresh()
        await vm.refresh()
        XCTAssertEqual(vm.chatMessages.map(\.id), ["m1", "m2"])
    }

    func testRefreshKeepsChatOnTransientDeltaFailure() async {
        let api = MockAPI(messagesOutcome: .success([.agent(id: "m1", text: "hi")]))
        await api.setMessagesDeltaScript([.failure(.unreachable)])
        let vm = SessionDetailViewModel(session: session(.running), api: api)
        await vm.load()
        await vm.refresh()
        XCTAssertEqual(vm.chatMessages.map(\.id), ["m1"])
    }

    // MARK: - task-10 画像添付

    private func attachment(mib: Double) -> SendAttachment {
        SendAttachment(mediaType: "image/png", data: Data(count: Int(mib * 1024 * 1024)))
    }

    func testAddAttachmentsAcceptsExactlyFourMiBPerImage() {
        let vm = SessionDetailViewModel(session: session(.idle), api: MockAPI())
        vm.addAttachments([attachment(mib: 4)])
        XCTAssertEqual(vm.attachments.count, 1)
        XCTAssertNil(vm.attachmentError)
    }

    func testAddAttachmentsRejectsJustOverFourMiBPerImage() {
        let vm = SessionDetailViewModel(session: session(.idle), api: MockAPI())
        let bytes = SessionDetailViewModel.maxAttachmentBytesPerImage + 1
        vm.addAttachments([SendAttachment(mediaType: "image/png", data: Data(count: bytes))])
        XCTAssertTrue(vm.attachments.isEmpty)
        XCTAssertNotNil(vm.attachmentError)
    }

    func testAddAttachmentsAcceptsExactlyEightMiBTotal() {
        let vm = SessionDetailViewModel(session: session(.idle), api: MockAPI())
        vm.addAttachments([attachment(mib: 2), attachment(mib: 2), attachment(mib: 2), attachment(mib: 2)])
        XCTAssertEqual(vm.attachments.count, 4)
        XCTAssertNil(vm.attachmentError)
    }

    func testAddAttachmentsRejectsBatchExceedingEightMiBTotal() {
        let vm = SessionDetailViewModel(session: session(.idle), api: MockAPI())
        vm.addAttachments([attachment(mib: 3), attachment(mib: 3), attachment(mib: 3)])
        XCTAssertTrue(vm.attachments.isEmpty)
        XCTAssertNotNil(vm.attachmentError)
    }

    func testAddAttachmentsRejectsFifthImageBatchWithoutPartialAdoption() {
        let vm = SessionDetailViewModel(session: session(.idle), api: MockAPI())
        vm.addAttachments([attachment(mib: 1), attachment(mib: 1), attachment(mib: 1), attachment(mib: 1), attachment(mib: 1)])
        XCTAssertTrue(vm.attachments.isEmpty)
        XCTAssertNotNil(vm.attachmentError)
    }

    func testAddAttachmentsRetainsDataWithoutEagerCopy() {
        var data = Data(repeating: 0xAB, count: 1024 * 1024)
        let attachment = SendAttachment(mediaType: "image/png", data: data)
        let vm = SessionDetailViewModel(session: session(.idle), api: MockAPI())
        vm.addAttachments([attachment])
        data.append(0xCD)
        XCTAssertEqual(vm.attachments[0].data.count, 1024 * 1024, "append 後の COW 分離で無駄コピーを起こさない")
    }

    func testSendMessageRestoresAttachmentsOnFailure() async {
        let api = MockAPI(sendOutcome: .failure(.unreachable))
        let vm = SessionDetailViewModel(session: session(.running), api: api)
        vm.inputText = "見て"
        vm.inputCursorUTF16 = vm.inputText.utf16.count
        vm.addAttachments([attachment(mib: 1)])
        await vm.sendMessage()
        XCTAssertEqual(vm.attachments.count, 1)
        XCTAssertEqual(vm.inputText, "見て [Image #1] ")
    }

    func testSendMessageIncludesAttachmentsInRequest() async {
        let api = MockAPI(sendOutcome: .success(SendResult(accepted: true)))
        let vm = SessionDetailViewModel(session: session(.running), api: api)
        vm.inputText = "見て"
        vm.inputCursorUTF16 = vm.inputText.utf16.count
        vm.addAttachments([attachment(mib: 1)])
        await vm.sendMessage()
        let images = await api.lastSentRequest?.images
        XCTAssertEqual(images?.count, 1)
    }

    // MARK: - task-10 サブエージェント解決

    func testResolveSubAgentIDByMarkerMessageID() async {
        let api = MockAPI()
        await api.setSubAgentsOutcome(.success([
            SubAgentSummary(id: "sa1", name: "explore", status: .running, messageCount: 1, markerMessageID: "m1")
        ]))
        let vm = SessionDetailViewModel(session: session(.idle), api: api)
        let resolved = await vm.resolveSubAgentID(forMessageID: "m1")
        XCTAssertEqual(resolved, "sa1")
        XCTAssertEqual(vm.subAgentID(forMessageID: "m1"), "sa1")
    }

    func testResolveSubAgentIDReturnsNilOnOldServer() async {
        let api = MockAPI()
        await api.setSubAgentsOutcome(.failure(.server(status: 501, message: "未対応")))
        let vm = SessionDetailViewModel(session: session(.idle), api: api)
        let resolved = await vm.resolveSubAgentID(forMessageID: "m1")
        XCTAssertNil(resolved)
        XCTAssertNil(vm.loadError)
    }

    func testDetectImageWireFormatPNGAndJPEG() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])
        XCTAssertEqual(SessionDetailViewModel.detectImageWireFormat(png), .png)
        XCTAssertEqual(SessionDetailViewModel.detectImageWireFormat(jpeg), .jpeg)
    }

    func testDetectImageWireFormatHEICLikeIsOther() {
        let heicLike = Data([0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70])
        XCTAssertEqual(SessionDetailViewModel.detectImageWireFormat(heicLike), .other)
    }

    func testNormalizeAttachmentPreservesPNGBytesAndMediaType() {
        let png = Data([0x89, 0x50, 0x4E, 0x47] + [0x00, 0x01, 0x02])
        let normalized = SessionDetailViewModel.normalizeAttachment(
            SendAttachment(mediaType: "application/octet-stream", data: png)
        )
        XCTAssertEqual(normalized?.mediaType, "image/png")
        XCTAssertEqual(normalized?.data, png)
    }

    func testNormalizeAttachmentPreservesJPEGBytesAndMediaType() {
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let normalized = SessionDetailViewModel.normalizeAttachment(
            SendAttachment(mediaType: "application/octet-stream", data: jpeg)
        )
        XCTAssertEqual(normalized?.mediaType, "image/jpeg")
        XCTAssertEqual(normalized?.data, jpeg)
    }

    #if canImport(UIKit)
    func testNormalizeNonJPEGWireFormatReencodesToJPEG() {
        let gif = Data(base64Encoded: "R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7")!
        let normalized = SessionDetailViewModel.normalizeAttachment(
            SendAttachment(mediaType: "application/octet-stream", data: gif)
        )
        XCTAssertEqual(normalized?.mediaType, "image/jpeg")
        XCTAssertTrue(normalized?.data.starts(with: [0xFF, 0xD8]) == true)
        XCTAssertNotEqual(normalized?.data, gif)
    }
    #endif

    func testAddAttachmentsCachesSmallPreviewSeparateFromSendPayload() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0, count: 64))
        let vm = SessionDetailViewModel(session: session(.idle), api: MockAPI())
        vm.addAttachments([SendAttachment(mediaType: "image/png", data: png)])
        XCTAssertEqual(vm.attachmentItems.count, 1)
        XCTAssertEqual(vm.attachmentItems[0].send.data, png)
        #if canImport(UIKit)
        XCTAssertFalse(vm.attachmentItems[0].previewData.isEmpty)
        XCTAssertLessThan(vm.attachmentItems[0].previewData.count, png.count)
        #endif
    }

        func testRefreshSubAgentIndexDoesNotSetLoadErrorOnOldServer() async {
        let api = MockAPI(messagesOutcome: .success([.agent(id: "a1", text: "hi")]))
        await api.setSubAgentsOutcome(.failure(.server(status: 501, message: "未対応")))
        let vm = SessionDetailViewModel(session: session(.running), api: api)
        await vm.refresh()
        XCTAssertNil(vm.loadError)
        XCTAssertNil(vm.subAgentID(forMessageID: "m1"))
    }
}
