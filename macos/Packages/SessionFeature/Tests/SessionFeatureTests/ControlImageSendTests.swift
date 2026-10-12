import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC")!

private final class RecordingStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var lastTurnStartInput: [ChatInput]?
    var turnStartError: (any Error)?

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        lastTurnStartInput = input
        if let turnStartError {
            throw turnStartError
        }
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func emit(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

@MainActor
private func makeClaudeViewModel(client: RecordingStructuredClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@MainActor
private func makeCodexViewModel(client: RecordingStructuredClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@Suite @MainActor
struct ControlImageSendTests {
    @Test func ChatComposerDraftMergeDoesNotCascadeRenumberingOrDuplicateIDs() {
        let first = ComposerAttachment(number: 1, data: tinyPNG, mediaType: "image/png")
        let second = ComposerAttachment(number: 2, data: tinyPNG, mediaType: "image/png")
        let third = ComposerAttachment(number: 1, data: tinyPNG, mediaType: "image/png")
        let fourth = ComposerAttachment(number: 2, data: tinyPNG, mediaType: "image/png")
        let merged = ComposerAttachmentStore.mergingDrafts(
            text: "first [Image #1] [Image #2]", attachments: [first, first, second],
            nextText: "next [Image #1] [Image #2] [Image #9]", nextAttachments: [third, fourth])
        #expect(merged.text == "first [Image #1] [Image #2]\n\nnext [Image #3] [Image #4] [Image #9]")
        #expect(merged.attachments.map(\.id) == [first.id, second.id, third.id, fourth.id])
        #expect(merged.attachments.map(\.number) == [1, 2, 3, 4])
        let sameImage = ComposerAttachment(id: first.id, number: 8, data: first.data, mediaType: first.mediaType)
        let deduplicated = ComposerAttachmentStore.mergingDrafts(text: "", attachments: [first],
            nextText: "same [Image #8]", nextAttachments: [sameImage])
        #expect(deduplicated.text == "same [Image #1]")
        #expect(deduplicated.attachments == [first])
    }
    @Test func firstMessageFailureRenumbersImagesAndRemovingChipKeepsOtherReference() async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)
        try await withTerminatedViewModel(vm) {
            try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
            let first = ComposerAttachment(data: tinyPNG, mediaType: "image/png", filename: "first.png")
            let next = ComposerAttachment(data: tinyPNG, mediaType: "image/png", filename: "next.png")
            await vm.sendFirstMessage("first [Image #1]", attachments: [first])
            vm.draft = "next [Image #1]"
            vm.attachmentStore.restore([next])
            client.emit(.error(message: "fake first turn failure"))
            for _ in 0..<100 {
                if case .error = vm.status { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(vm.draft == "first [Image #1]\n\nnext [Image #2]")
            #expect(vm.composerAttachments.map(\.number) == [1, 2])
            let restoredNext = try #require(vm.composerAttachments.first { $0.id == next.id })
            vm.attachmentStore.remove(id: restoredNext.id)
            vm.draft = ComposerImagePlaceholder.removing(number: restoredNext.number, from: vm.draft)
            #expect(vm.draft == "first [Image #1]\n\nnext")
            #expect(vm.composerAttachments == [first])
        }
    }
    @Test(arguments: ["next input", ""])
    func firstMessageAsyncFailurePreservesNextInputAndDeduplicatesAttachments(nextText: String) async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)
        try await withTerminatedViewModel(vm) {
            try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
            let original = ComposerAttachment(data: tinyPNG, mediaType: "image/png", filename: "original.png")
            let next = ComposerAttachment(data: tinyPNG, mediaType: "image/png", filename: "next.png")
            await vm.sendFirstMessage("first input", attachments: [original])
            vm.draft = nextText
            vm.attachmentStore.restore([original, next])
            client.emit(.error(message: "fake first turn failure"))
            for _ in 0..<100 {
                if case .error = vm.status { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            if case .error = vm.status {} else { Issue.record("error not processed") }
            #expect(vm.draft == (nextText.isEmpty ? "first input" : "first input\n\nnext input"))
            #expect(vm.attachmentStore.attachments == [original, ComposerAttachment(id: next.id, number: 2,
                data: next.data, mediaType: next.mediaType, filename: next.filename)])
            #expect(client.lastTurnStartInput?.count == 2)
        }
    }

    @Test func firstMessageAsyncFailureRestoresTextAndOriginalAttachments() async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)
        try await withTerminatedViewModel(vm) {
            try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
            let attachments = [ComposerAttachment(data: tinyPNG, mediaType: "image/png", filename: "test.png")]
            await vm.sendFirstMessage("inspect", attachments: attachments)
            #expect(vm.attachmentStore.attachments.isEmpty)
            client.emit(.error(message: "fake first turn failure"))
            for _ in 0..<100 {
                if case .error = vm.status { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(vm.draft == "inspect")
            #expect(vm.attachmentStore.attachments == attachments)
            #expect(client.lastTurnStartInput?.count == 2)
        }
    }

    @Test func laterTurnErrorDoesNotRestorePreviousInput() async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)
        try await withTerminatedViewModel(vm) {
            try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
            await vm.sendFirstMessage("first", attachments: [])
            client.emit(.turnCompleted(nativeSessionId: nil))
            for _ in 0..<100 {
                if vm.completedTurnSeq == 1 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(vm.completedTurnSeq == 1)
            try await vm.sendText("second", submit: true)
            client.emit(.error(message: "fake second turn failure"))
            for _ in 0..<100 {
                if case .error = vm.status { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            if case .error = vm.status {} else { Issue.record("error not processed") }
            #expect(vm.draft.isEmpty)
        }
    }

    @Test func pendingFirstMessageIsRemovedOnLaunchFailureAndBlocksSubmit() async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)
        let attachments = [ComposerAttachment(data: tinyPNG, mediaType: "image/png")]
        vm.prepareFirstMessage("inspect", attachments: attachments)
        #expect(vm.pendingFirstMessage != nil)
        #expect(vm.draft.isEmpty)
        #expect(vm.consumeDraftForSend() == nil)
        vm.markLaunchFailed(.processFailed("fake launch failure"), restoringDraft: "inspect")
        #expect(vm.pendingFirstMessage == nil)
        #expect(vm.draft == "inspect")
        #expect(vm.attachmentStore.attachments == attachments)
        #expect(vm.transcript.allSatisfy { if case .userMessage = $0 { false } else { true } })
        #expect(vm.transcriptItemIDs == Set(vm.transcript.map(\.id)))
        #expect(!vm.isReadyForInput)
        await vm.terminate()
    }

    @Test(arguments: [false, true])
    func launchFailurePreservesInputEditedWhileStarting(isRestart: Bool) async {
        let vm = makeClaudeViewModel(client: RecordingStructuredClient())
        if !isRestart { vm.prepareFirstMessage("first input", attachments: []) }
        vm.draft = "next input"
        vm.markLaunchFailed(.processFailed("fake launch failure"), restoringDraft: isRestart ? "next input" : "first input")
        #expect(vm.draft == (isRestart ? "next input" : "first input\n\nnext input"))
        await vm.terminate()
    }

    private func withTerminatedViewModel<T>(
        _ viewModel: ChatSessionViewModel,
        operation: () async throws -> T
    ) async throws -> T {
        do {
            let result = try await operation()
            await viewModel.terminate()
            return result
        } catch {
            await viewModel.terminate()
            throw error
        }
    }

    @Test
    func sendTextWithControlImages_includesImageInTurnStartInput() async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)

        try await withTerminatedViewModel(vm) {
            try await vm.sendTextWithControlImages(
                "この画面を見て",
                submit: true,
                images: [(mediaType: "image/png", data: tinyPNG)]
            )

            let input = try #require(client.lastTurnStartInput)
            #expect(input == [
                .text("この画面を見て"),
                .image(data: tinyPNG, mediaType: "image/png"),
            ])
            #expect(vm.attachmentStore.attachments.isEmpty)
        }
    }

    @Test
    func oversizedOriginalIsPreparedBeforeTurnStart() async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)
        var original = tinyPNG
        original.append(Data(count: 6_000_000 - original.count))
        vm.attachmentStore.addImage(data: original, mediaType: "image/png", filename: "large.png")
        try await withTerminatedViewModel(vm) {
            try await vm.sendText("large image", submit: true)
            let inputs = try #require(client.lastTurnStartInput)
            guard case .image(let sent, let mediaType) = inputs.last else {
                Issue.record("画像が送信されていない")
                return
            }
            #expect(sent.count <= ImageAttachmentLimits.maxSendBytes)
            #expect(mediaType == "image/png")
            #expect(vm.attachmentStore.attachments.isEmpty)
        }
    }

    @Test
    func brokenOriginalAbortsWithoutSendingAndPreservesDraftAndAttachment() async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)
        let broken = Data([0x89, 0x50, 0x4e, 0x47])
        vm.attachmentStore.addImage(data: broken, mediaType: "image/png")
        vm.draft = "retry this"
        let text = try #require(vm.consumeDraftForSend())
        try await withTerminatedViewModel(vm) {
            await #expect(throws: (any Error).self) { try await vm.sendText(text, submit: true) }
            #expect(client.lastTurnStartInput == nil)
            #expect(vm.attachmentStore.attachments.first?.data == broken)
            #expect(vm.draft == "retry this")
            #expect(vm.attachmentStore.lastError == "画像を読み込めませんでした")
            #expect(vm.status != .running)
        }
    }

    @Test
    func sendTextWithControlImages_clearsImagesWhenTurnStartThrows() async throws {
        let client = RecordingStructuredClient()
        client.turnStartError = NSError(domain: "test", code: 1)
        let vm = makeClaudeViewModel(client: client)

        try await withTerminatedViewModel(vm) {
            await #expect(throws: (any Error).self) {
                try await vm.sendTextWithControlImages(
                    "retry me",
                    submit: true,
                    images: [(mediaType: "image/png", data: tinyPNG)]
                )
            }

            #expect(vm.attachmentStore.attachments.isEmpty)

            client.turnStartError = nil
            try await vm.sendTextWithControlImages(
                "second try",
                submit: true,
                images: [(mediaType: "image/png", data: tinyPNG)]
            )

            let input = try #require(client.lastTurnStartInput)
            #expect(input.contains(.image(data: tinyPNG, mediaType: "image/png")))
            #expect(input.contains(.text("second try")))
        }
    }

    @Test
    func sendTextWithControlImages_unsupportedAgentThrowsWithoutStaging() async throws {
        let client = RecordingStructuredClient()
        let vm = makeCodexViewModel(client: client)

        try await withTerminatedViewModel(vm) {
            await #expect(throws: ChatSessionViewModel.ControlImageSendError.imagesUnsupported) {
                try await vm.sendTextWithControlImages(
                    "image please",
                    submit: true,
                    images: [(mediaType: "image/png", data: tinyPNG)]
                )
            }

            #expect(client.lastTurnStartInput == nil)
            #expect(vm.attachmentStore.attachments.isEmpty)
        }
    }

    @Test(arguments: [false, true], [false, true])
    func concurrentControlSendPreservesOriginalImageSend(submit: Bool, includesImages: Bool) async throws {
        let imageModel = try JSONDecoder().decode(
            AppServerModel.self,
            from: Data(#"{"id":"image-model","model":"image-model","displayName":"Image","description":"","hidden":false,"supportedReasoningEfforts":["medium"],"defaultReasoningEffort":"medium","isDefault":true,"inputModalities":["text","image"]}"#.utf8)
        )
        let client = RacingCodexImageClient(models: [imageModel])
        let vm = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/work"
        )
        try await withTerminatedViewModel(vm) {
            try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
            let attachment = try #require(vm.attachmentStore.addImage(
                data: tinyPNG, mediaType: "image/png", filename: "desktop.png"
            ))
            var started = client.configurationStarted.makeAsyncIterator()
            let originalSend = Task { @MainActor in
                try await vm.sendText("desktop input", submit: true)
            }
            _ = await started.next()
            await #expect(throws: ChatSessionViewModel.ControlImageSendError.imageSendInProgress) {
                try await vm.sendText("mobile input", submit: submit)
            }
            await #expect(throws: ChatSessionViewModel.ControlImageSendError.imageSendInProgress) {
                try await vm.sendTextWithControlImages(
                    "mobile input", submit: submit,
                    images: includesImages ? [(mediaType: "image/png", data: tinyPNG)] : []
                )
            }
            #expect(vm.attachmentStore.attachments == [attachment])
            #expect(await client.lastTurnStartInput() == nil)
            await client.releaseConfiguration()
            try await originalSend.value
            #expect(await client.turnStartInputs() == [[
                .text("desktop input"), .image(data: tinyPNG, mediaType: "image/png"),
            ]])
            #expect(vm.attachmentStore.attachments.isEmpty)
        }
    }

    @Test
    func sendTextWithControlImages_modelChangesDuringCapabilityAwait_abortsWithoutTextOnlySend() async throws {
        let imageModel = try JSONDecoder().decode(
            AppServerModel.self,
            from: Data(#"{"id":"image-model","model":"image-model","displayName":"Image","description":"","hidden":false,"supportedReasoningEfforts":["medium"],"defaultReasoningEffort":"medium","isDefault":true,"inputModalities":["text","image"]}"#.utf8)
        )
        let textModel = try JSONDecoder().decode(
            AppServerModel.self,
            from: Data(#"{"id":"text-model","model":"text-model","displayName":"Text","description":"","hidden":false,"supportedReasoningEfforts":["medium"],"defaultReasoningEffort":"medium","isDefault":false,"inputModalities":["text"]}"#.utf8)
        )
        let client = RacingCodexImageClient(models: [imageModel, textModel])
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await withTerminatedViewModel(vm) {
            try await vm.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )

            var started = client.configurationStarted.makeAsyncIterator()
            let sendTask = Task { @MainActor in
                try await vm.sendTextWithControlImages(
                    "画像を説明して",
                    submit: true,
                    images: [(mediaType: "image/png", data: tinyPNG)]
                )
            }
            _ = await started.next()
            try await vm.setModel(model: "text-model", effort: "medium")
            await client.releaseConfiguration()

            await #expect(throws: ChatSessionViewModel.ControlImageSendError.imageSendSnapshotChanged) {
                try await sendTask.value
            }
            #expect(await client.lastTurnStartInput() == nil)
        }
    }

    @Test
    func sendText_imageTurnInProgressBecomesExplicitImageRejectionAndRestoresDraftAndAttachment() async throws {
        let imageModel = try JSONDecoder().decode(
            AppServerModel.self,
            from: Data(#"{"id":"image-model","model":"image-model","displayName":"Image","description":"","hidden":false,"supportedReasoningEfforts":["medium"],"defaultReasoningEffort":"medium","isDefault":true,"inputModalities":["text","image"]}"#.utf8)
        )
        let client = RacingCodexImageClient(models: [imageModel])
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await withTerminatedViewModel(vm) {
            try await vm.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
            await client.setConfigurationBlocked(false)

            vm.draft = "画像を説明して"
            let attachment = try #require(
                vm.attachmentStore.addImage(data: tinyPNG, mediaType: "image/png")
            )
            let input = try #require(vm.consumeDraftForSend())
            await client.setTurnStartError(.imageTurnInProgress)

            await #expect(throws: ChatSessionViewModel.ControlImageSendError.imageSendSnapshotChanged) {
                try await vm.sendText(input, submit: true)
            }
            #expect(vm.draft == input)
            #expect(vm.attachmentStore.attachments == [attachment])
            #expect(vm.attachmentStore.lastError == "画像対応モデルまたは添付が送信前に変更されたため、送信を中止しました")
            #expect(await client.turnStartInputs() == [[
                .text(input),
                .image(data: tinyPNG, mediaType: "image/png"),
            ]])
        }
    }

    // 05 R8: 送れないモデルで送ろうとしたエラーは、送れるモデルに替えたら消える。
    @Test
    func sendText_imageErrorClearsAfterSwitchingToAnImageModel() async throws {
        let textModel = try JSONDecoder().decode(
            AppServerModel.self,
            from: Data(#"{"id":"text-model","model":"text-model","displayName":"Text","description":"","hidden":false,"supportedReasoningEfforts":["medium"],"defaultReasoningEffort":"medium","isDefault":true,"inputModalities":["text"]}"#.utf8)
        )
        let imageModel = try JSONDecoder().decode(
            AppServerModel.self,
            from: Data(#"{"id":"image-model","model":"image-model","displayName":"Image","description":"","hidden":false,"supportedReasoningEfforts":["medium"],"defaultReasoningEffort":"medium","isDefault":false,"inputModalities":["text","image"]}"#.utf8)
        )
        let client = RacingCodexImageClient(models: [textModel, imageModel])
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/work"
        )
        try await withTerminatedViewModel(vm) {
            try await vm.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
            await client.setConfigurationBlocked(false)
            try await vm.setModel(model: "text-model", effort: "medium")
            vm.attachmentStore.addImage(data: tinyPNG, mediaType: "image/png")
            await #expect(throws: SendRejected.imagesUnsupported) { try await vm.sendText("", submit: true) }
            #expect(vm.attachmentStore.lastError == ChatSessionViewModel.ControlImageSendError.imagesUnsupported.localizedDescription)

            try await vm.setModel(model: "image-model", effort: "medium")
            #expect(vm.imageAttachmentSupport == .supported)
            #expect(vm.attachmentStore.lastError == nil)
        }
    }
}

private actor RacingCodexImageClient: StructuredAgentClient, CodexSettingsProviding, CodexImageInputConfiguring {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let threadEvents: AsyncStream<ThreadEvent>
    nonisolated let configurationStarted: AsyncStream<Void>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let threadEventContinuation: AsyncStream<ThreadEvent>.Continuation
    private let configurationStartedContinuation: AsyncStream<Void>.Continuation
    private let models: [AppServerModel]
    private var configurationContinuation: CheckedContinuation<Void, Never>?
    private var configurationBlocked = true
    private var lastInput: [ChatInput]?
    private var turnStartInputsStorage: [[ChatInput]] = []
    private var turnStartError: CodexStructuredClientError?

    init(models: [AppServerModel]) {
        self.models = models
        var eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { eventContinuation = $0 }
        self.eventContinuation = eventContinuation!
        var threadEventContinuation: AsyncStream<ThreadEvent>.Continuation?
        threadEvents = AsyncStream { threadEventContinuation = $0 }
        self.threadEventContinuation = threadEventContinuation!
        var startedContinuation: AsyncStream<Void>.Continuation?
        configurationStarted = AsyncStream(bufferingPolicy: .unbounded) { startedContinuation = $0 }
        self.configurationStartedContinuation = startedContinuation!
    }

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        lastInput = input
        turnStartInputsStorage.append(input)
        if let turnStartError {
            throw turnStartError
        }
    }

    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}

    func close() async {
        configurationContinuation?.resume()
        configurationContinuation = nil
        eventContinuation.finish()
        threadEventContinuation.finish()
        configurationStartedContinuation.finish()
    }

    func activeThreadId() async -> String? { "thread-image-race" }

    func initialize(_ params: InitializeParams) async throws -> InitializeResponse {
        try decode(#"{"codexHome":"/tmp","platformFamily":"macOS","platformOs":"macOS","userAgent":"test"}"#)
    }

    func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        try decode(#"{"thread":{"id":"thread-image-race","status":{"type":"idle"}}}"#)
    }

    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        try decode(#"{"thread":{"id":"thread-image-race","status":{"type":"idle"}}}"#)
    }

    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        try decode(#"{"thread":{"id":"thread-image-race","status":{"type":"idle"}}}"#)
    }

    func listModels(_ params: ModelListParams) async throws -> ModelListResponse {
        let value = try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(models)
        )
        return try decode(JSONEncoder().encode(JSONValue.object(["data": value, "nextCursor": .null])))
    }

    func listPermissionProfiles(_ params: PermissionProfileListParams) async throws -> PermissionProfileListResponse {
        try decode(#"{"data":[]}"#)
    }

    func listCollaborationModes(_ params: CollaborationModeListParams) async throws -> CollaborationModeListResponse {
        try decode(#"{"data":[]}"#)
    }

    func updateThreadSettings(_ params: ThreadSettingsUpdateParams) async throws -> ThreadSettingsUpdateResponse {
        ThreadSettingsUpdateResponse()
    }

    func setNativeImageInputEnabled(_ enabled: Bool) async {
        guard configurationBlocked else { return }
        configurationStartedContinuation.yield(())
        await withCheckedContinuation { continuation in
            configurationContinuation = continuation
        }
    }

    func releaseConfiguration() {
        configurationContinuation?.resume()
        configurationContinuation = nil
    }

    func lastTurnStartInput() -> [ChatInput]? { lastInput }

    func setConfigurationBlocked(_ blocked: Bool) {
        configurationBlocked = blocked
    }

    func setTurnStartError(_ error: CodexStructuredClientError?) {
        turnStartError = error
    }

    func turnStartInputs() -> [[ChatInput]] { turnStartInputsStorage }

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
