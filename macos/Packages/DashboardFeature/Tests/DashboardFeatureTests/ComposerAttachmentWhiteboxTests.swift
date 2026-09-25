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
    #expect(viewModel.attachmentStore.lastError == "画像添付は Claude と画像対応モデルの Codex に対応しています")
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

// 05 R8: 画像の扱いは 1 つの判定に従う。Claude は送れる、Codex の非対応モデルは添付して知らせる、Cursor は貼り付けを断る。
@MainActor
private func attachmentViewModel(_ agent: AgentKind) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(agent),
        client: ComposerAttachmentCaptureClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@Test @MainActor
func composerAttachment_supportIsDecidedOncePerAgentAndModel() {
    #expect(attachmentViewModel(.claudeCode).imageAttachmentSupport == .supported)
    // 画像対応が分からない（モデル一覧が無い）Codex は、いまのモデルには送れない扱い。
    #expect(attachmentViewModel(.codex).imageAttachmentSupport == .modelUnsupported)
    #expect(attachmentViewModel(.cursor).imageAttachmentSupport == .agentUnsupported)
}

@Test @MainActor
func composerAttachment_pastedImageFollowsTheSupport() {
    let ja = Locale(identifier: "ja")
    let claude = attachmentViewModel(.claudeCode)
    #expect(ComposerAttachmentCapability.addPastedImage(to: claude, data: Data([1]), mediaType: "image/png", locale: ja) == .attached(number: 1))
    #expect(claude.attachmentStore.lastError == nil)

    #expect(ComposerAttachmentCapability.imageNotice(claude, locale: ja) == nil)

    let codex = attachmentViewModel(.codex)
    #expect(ComposerAttachmentCapability.imageNotice(codex, locale: ja) == nil)
    #expect(ComposerAttachmentCapability.addPastedImage(to: codex, data: Data([1]), mediaType: "image/png", locale: ja) == .attached(number: 1))
    #expect(codex.attachmentStore.lastError == nil)
    #expect(ComposerAttachmentCapability.imageNotice(codex, locale: ja)?.contains("この画像は送られません") == true)

    let cursor = attachmentViewModel(.cursor)
    #expect(ComposerAttachmentCapability.addPastedImage(to: cursor, data: Data([1]), mediaType: "image/png", locale: ja) == .unsupported)
    #expect(cursor.attachmentStore.attachments.isEmpty)
    #expect(cursor.attachmentStore.lastErrorTone == .neutral)
    #expect(cursor.attachmentStore.lastError?.hasPrefix("Cursor では画像を貼り付けられません") == true)
}

@Test @MainActor
func composerAttachment_limitErrorsStayRed() {
    let store = ComposerAttachmentStore()
    store.setError("参照にした", tone: .neutral)
    store.addImage(data: Data(count: ComposerAttachmentStore.maxBytesPerImage + 1), mediaType: "image/png")
    #expect(store.lastErrorTone == .error)
}

// 画像を添付している間は ↑ で履歴を呼ばない（本文の [Image #N] が消えると添付も外れるため）。
@Test @MainActor
func composerAttachment_historyIsNotRecalledWhileAnImageIsAttached() async throws {
    let viewModel = attachmentViewModel(.claudeCode)
    try await viewModel.sendText("前の入力", submit: true)
    #expect(InputHistoryPolicy.entries(from: viewModel.transcript).map(\.text) == ["前の入力"])
    viewModel.attachmentStore.addImage(data: Data([1]), mediaType: "image/png")
    viewModel.draft = "[Image #1] これを見て"

    #expect(!viewModel.recallInputHistory(.older))
    #expect(viewModel.draft == "[Image #1] これを見て")

    viewModel.attachmentStore.clear()
    viewModel.draft = ""
    #expect(viewModel.recallInputHistory(.older))
    #expect(viewModel.draft == "前の入力")
}

// 画像つきで送った入力は ↑ で呼び戻さない（本文だけ戻すと画像なしで送ってしまう）。
@Test @MainActor
func composerAttachment_historySkipsInputsSentWithImages() async throws {
    let viewModel = attachmentViewModel(.claudeCode)
    try await viewModel.sendText("文字だけ", submit: true)
    viewModel.attachmentStore.addImage(data: Data([1]), mediaType: "image/png")
    try await viewModel.sendText("[Image #1] 画像つき", submit: true)
    viewModel.attachmentStore.clear()
    viewModel.draft = ""

    #expect(viewModel.recallInputHistory(.older))
    #expect(viewModel.draft == "文字だけ")
    #expect(!viewModel.recallInputHistory(.older))
}

// 添付の記録が無くても、本文に [Image #N] がある入力は呼び戻さない（Codex の会話を読み直した入力）。
@Test @MainActor
func composerAttachment_historySkipsInputsWithAnImagePlaceholder() async throws {
    let viewModel = attachmentViewModel(.claudeCode)
    try await viewModel.sendText("文字だけ", submit: true)
    try await viewModel.sendText("[Image #2] 読み直した画像つき", submit: true)
    viewModel.draft = ""

    #expect(viewModel.recallInputHistory(.older))
    #expect(viewModel.draft == "文字だけ")
}
