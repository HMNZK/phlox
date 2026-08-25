import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private let tinyPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

private final class RevertAttachmentRecordingClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var turnInputs: [[ChatInput]] = []
    private var resetCount = 0

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        lock.withLock { turnInputs.append(input) }
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func resetConversation() async {
        lock.withLock { resetCount += 1 }
    }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
    func recordedTurnInputs() -> [[ChatInput]] { lock.withLock { turnInputs } }
    func resetConversationCalls() -> Int { lock.withLock { resetCount } }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@MainActor
private func makeViewModel(client: RevertAttachmentRecordingClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@MainActor
private func completeTurn(
    _ vm: ChatSessionViewModel,
    client: RevertAttachmentRecordingClient,
    userText: String,
    agentItemID: String,
    agentReply: String
) async throws {
    try await vm.sendText(userText, submit: true)
    client.yield(.agentMessageDelta(itemId: agentItemID, agentReply))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
}

@Suite @MainActor
struct ChatRevertAttachmentTests {
    @Test
    func revert_restoresRuntimeAttachmentsForResend() async throws {
        let client = RevertAttachmentRecordingClient()
        let vm = makeViewModel(client: client)

        let attachment = try #require(
            vm.attachmentStore.addImage(data: tinyPNG, mediaType: "image/png", filename: "shot.png")
        )
        let userText = "見て \(ComposerImagePlaceholder.text(for: attachment.number))"
        try await completeTurn(
            vm,
            client: client,
            userText: userText,
            agentItemID: "a1",
            agentReply: "応答"
        )

        #expect(vm.attachmentStore.attachments.isEmpty)

        let userID = try #require(vm.transcript.compactMap { item -> String? in
            if case .userMessage(let id, _, _, _) = item { id } else { nil }
        }.first)

        let restored = await vm.revert(toUserMessageID: userID)
        #expect(restored == userText)
        #expect(vm.attachmentStore.attachments == [attachment])

        try await vm.sendText("再送", submit: true)
        let resendInput = try #require(client.recordedTurnInputs().last)
        #expect(resendInput.contains(.image(data: tinyPNG, mediaType: "image/png")))
        #expect(resendInput.contains(.text("再送")))

        await vm.terminate()
    }

    @Test
    func revert_withoutRuntimeCache_clearsAttachmentStore() async throws {
        let client = RevertAttachmentRecordingClient()
        let vm = makeViewModel(client: client)

        try await completeTurn(
            vm,
            client: client,
            userText: "テキストのみ",
            agentItemID: "a1",
            agentReply: "応答"
        )

        let userID = try #require(vm.transcript.compactMap { item -> String? in
            if case .userMessage(let id, _, _, _) = item { id } else { nil }
        }.first)

        _ = vm.attachmentStore.addImage(data: tinyPNG, mediaType: "image/png")

        let restored = await vm.revert(toUserMessageID: userID)
        #expect(restored == "テキストのみ")
        #expect(vm.attachmentStore.attachments.isEmpty)

        await vm.terminate()
    }

    @Test
    func sendTextWithControlImages_cachesAttachmentsForRevert() async throws {
        let client = RevertAttachmentRecordingClient()
        let vm = makeViewModel(client: client)

        try await vm.sendTextWithControlImages(
            "control 画像",
            submit: true,
            images: [(mediaType: "image/png", data: tinyPNG)]
        )
        client.yield(.turnCompleted(nativeSessionId: nil))
        try await waitUntil { vm.status == .idle }

        let userID = try #require(vm.transcript.compactMap { item -> String? in
            if case .userMessage(let id, _, _, _) = item { id } else { nil }
        }.first)

        _ = await vm.revert(toUserMessageID: userID)
        #expect(vm.attachmentStore.attachments.count == 1)
        #expect(vm.attachmentStore.attachments[0].data == tinyPNG)
        #expect(vm.attachmentStore.attachments[0].number == 1)

        await vm.terminate()
    }
}
