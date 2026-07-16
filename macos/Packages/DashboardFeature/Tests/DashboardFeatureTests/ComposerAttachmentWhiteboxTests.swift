import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class ComposerAttachmentCaptureClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var receivedInputs: [[ChatInput]] = []

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        receivedInputs.append(input)
    }

    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

private final class ComposerAttachmentThrowingClient: StructuredAgentClient, @unchecked Sendable {
    enum Failure: Error {
        case turnStart
    }

    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var receivedInputs: [[ChatInput]] = []

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        receivedInputs.append(input)
        throw Failure.turnStart
    }

    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

@Test @MainActor
func composerAttachment_acceptsImageAtExactSizeLimit() {
    let store = ComposerAttachmentStore()
    let limitSizedImage = Data(count: ComposerAttachmentStore.maxBytesPerImage)

    store.addImage(data: limitSizedImage, mediaType: "image/png", filename: "limit.png")

    #expect(store.attachments.count == 1)
    #expect(store.attachments.first?.data.count == ComposerAttachmentStore.maxBytesPerImage)
    #expect(store.lastError == nil)
}

@Test @MainActor
func composerAttachment_sendTextSendsImagesAndClearsOnlyAfterSuccess() async throws {
    let client = ComposerAttachmentCaptureClient()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    let image = Data([1, 2, 3, 4])
    viewModel.attachmentStore.addImage(data: image, mediaType: "image/png")

    try await viewModel.sendText("inspect", submit: true)

    #expect(client.receivedInputs == [[
        .text("inspect"),
        .image(data: image, mediaType: "image/png"),
    ]])
    #expect(viewModel.attachmentStore.attachments.isEmpty)
}

@Test @MainActor
func composerAttachment_rejectsImageThatWouldExceedTotalRawLimit() {
    let store = ComposerAttachmentStore()
    let threeMiB = Data(count: 3 * 1024 * 1024)

    store.addImage(data: threeMiB, mediaType: "image/png")
    store.addImage(data: threeMiB, mediaType: "image/png")
    store.addImage(data: threeMiB, mediaType: "image/png")

    #expect(store.attachments.count == 2)
    #expect(store.totalRawBytes == 6 * 1024 * 1024)
    #expect(store.lastError == "画像は合計8MiBまでです")
}

@Test @MainActor
func composerAttachment_sendPathBlocksOverTotalRawLimitAndKeepsAttachments() async throws {
    let client = ComposerAttachmentCaptureClient()
    let overLimitStore = ComposerAttachmentStore(attachments: [
        ComposerAttachment(data: Data(count: 3 * 1024 * 1024), mediaType: "image/png"),
        ComposerAttachment(data: Data(count: 3 * 1024 * 1024), mediaType: "image/png"),
        ComposerAttachment(data: Data(count: 3 * 1024 * 1024), mediaType: "image/png"),
    ])
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        attachmentStore: overLimitStore
    )

    try await viewModel.sendText("inspect", submit: true)

    #expect(client.receivedInputs.isEmpty)
    #expect(viewModel.attachmentStore.attachments.count == 3)
    #expect(viewModel.attachmentStore.lastError == "画像は合計8MiBまでです")
}

@Test @MainActor
func composerAttachment_nonClaudeImageOnlySendIsBlockedAndKeepsAttachments() async throws {
    let client = ComposerAttachmentCaptureClient()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    viewModel.attachmentStore.addImage(data: Data([1, 2, 3]), mediaType: "image/png")

    try await viewModel.sendText("", submit: true)

    #expect(client.receivedInputs.isEmpty)
    #expect(viewModel.attachmentStore.attachments.count == 1)
    #expect(viewModel.attachmentStore.lastError == "画像添付は Claude のみ対応です")
}

@Test @MainActor
func composerAttachment_sendFailureKeepsAttachments() async {
    let client = ComposerAttachmentThrowingClient()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    let image = Data([1, 2, 3, 4])
    viewModel.attachmentStore.addImage(data: image, mediaType: "image/png")

    do {
        try await viewModel.sendText("inspect", submit: true)
        Issue.record("Expected sendText to throw")
    } catch {
        #expect(viewModel.attachmentStore.attachments.count == 1)
        #expect(client.receivedInputs == [[
            .text("inspect"),
            .image(data: image, mediaType: "image/png"),
        ]])
    }
}

@Test @MainActor
func composerAttachment_imageOnlySendDisplaysImageCountInTranscript() async throws {
    let client = ComposerAttachmentCaptureClient()
    let viewModel = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    viewModel.attachmentStore.addImage(data: Data([1]), mediaType: "image/png")
    viewModel.attachmentStore.addImage(data: Data([2]), mediaType: "image/jpeg")

    try await viewModel.sendText("", submit: true)

    #expect(client.receivedInputs == [[
        .image(data: Data([1]), mediaType: "image/png"),
        .image(data: Data([2]), mediaType: "image/jpeg"),
    ]])
    guard case let .userMessage(_, text, _, attachments) = try #require(viewModel.transcript.first) else {
        Issue.record("先頭アイテムが userMessage ではない")
        return
    }
    #expect(text.isEmpty)
    #expect(attachments == [
        ChatUserAttachment(filename: nil, mediaType: "image/png"),
        ChatUserAttachment(filename: nil, mediaType: "image/jpeg"),
    ])
}

@Test
func composerAttachment_pastePolicyInterceptsWhenTextAndImageArePresent() {
    #expect(ComposerPastePolicy.shouldInterceptImagePaste(availableTypeIdentifiers: [
        "public.utf8-plain-text",
        "public.png",
    ]) == true)
}

@Test
func composerAttachment_pastePolicyInterceptsImageOnlyPaste() {
    #expect(ComposerPastePolicy.shouldInterceptImagePaste(availableTypeIdentifiers: [
        "public.png",
    ]) == true)
}
