import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private let tinyPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

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
    @Test
    func sendTextWithControlImages_includesImageInTurnStartInput() async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)

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

    @Test
    func sendTextWithControlImages_clearsImagesWhenTurnStartThrows() async throws {
        let client = RecordingStructuredClient()
        client.turnStartError = NSError(domain: "test", code: 1)
        let vm = makeClaudeViewModel(client: client)

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

    @Test
    func sendTextWithControlImages_unsupportedAgentThrowsWithoutStaging() async throws {
        let client = RecordingStructuredClient()
        let vm = makeCodexViewModel(client: client)

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

private actor RacingCodexImageClient: StructuredAgentClient, CodexSettingsProviding, CodexImageInputConfiguring {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let threadEvents: AsyncStream<ThreadEvent>
    nonisolated let configurationStarted: AsyncStream<Void>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let threadEventContinuation: AsyncStream<ThreadEvent>.Continuation
    private let configurationStartedContinuation: AsyncStream<Void>.Continuation
    private let models: [AppServerModel]
    private var configurationContinuation: CheckedContinuation<Void, Never>?
    private var lastInput: [ChatInput]?

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
    }

    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}

    func close() async {
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

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
