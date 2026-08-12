import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

/// SessionFeature の Codex 画像入力受け入れテスト。
///
/// 存在しない Feature state 型を先取りせず、実 DTO と既存 ViewModel API を検査する。
@Suite("Acceptance: Codex 画像入力")
struct AcceptanceCodexImageInputTests {
    private let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

    private func imageURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-codex-image-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = directory.appendingPathComponent("image.png")
        try png.write(to: image)
        return image
    }

    @Test("Codex native localImage は path と detail を保持する")
    func nativeImageInputRoundTripsWithoutLegacyText() throws {
        let path = try imageURL().path
        let input = UserInput.localImage(path: path, detail: "high")
        let encoded = try JSONEncoder().encode(input)
        let decoded = try JSONDecoder().decode(UserInput.self, from: encoded)

        #expect(decoded == input)
        let raw = try JSONDecoder().decode(JSONValue.self, from: encoded)
        #expect(raw["type"] == JSONValue.string("localImage"))
        #expect(raw["path"] == JSONValue.string(path))
    }

    @Test("画像を含む Codex wire input は text-only へ丸めない")
    func imageInputWireContainsNativeImageAndText() throws {
        let path = try imageURL().path
        let input: [UserInput] = [.text("この画像を説明して"), .localImage(path: path, detail: nil)]
        let data = try JSONEncoder().encode(input)
        let raw = try JSONDecoder().decode(JSONValue.self, from: data)

        guard case .array(let values) = raw else {
            Issue.record("画像付き input が配列でない")
            return
        }
        #expect(values.count == 2)
        #expect(values.contains { $0["type"] == JSONValue.string("localImage") })
        #expect(values.contains { $0["type"] == JSONValue.string("text") })
    }

    @Test("model/list の inputModalities は画像能力判定に使える実 DTO を返す")
    func modelListExposesNativeImageModality() throws {
        let response = try JSONDecoder().decode(
            ModelListResponse.self,
            from: Data(#"{"data":[{"id":"gpt-5-codex","model":"gpt-5-codex","displayName":"GPT-5 Codex","description":"","hidden":false,"supportedReasoningEfforts":["medium"],"defaultReasoningEffort":"medium","isDefault":true,"inputModalities":["text","image"]}],"nextCursor":null}"#.utf8)
        )

        #expect(response.data.first?.inputModalities == ["text", "image"])
        #expect(response.data.first?.inputModalities?.contains("image") == true)
    }

    @Test("未知 modality の実 AppServerModel は既存 ViewModel API で画像入力を選べない")
    @MainActor
    func unknownImageModalityIsRejectedByExistingViewModelAPI() async throws {
        let model = try JSONDecoder().decode(
            AppServerModel.self,
            from: Data(#"{"id":"gpt-5-codex","model":"gpt-5-codex","displayName":"GPT-5 Codex","description":"","hidden":false,"supportedReasoningEfforts":["medium"],"defaultReasoningEffort":"medium","isDefault":true,"inputModalities":["text","future-image"]}"#.utf8)
        )
        let client = UnknownModalityCodexClient(model: model)
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-codex-image"
        )

        try await withTerminatedViewModel(viewModel) {
            try await viewModel.startNew(
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )

            #expect(viewModel.availableModels == [model])
            #expect(viewModel.availableModels.first?.inputModalities == ["text", "future-image"])
            #expect(viewModel.acceptsImageAttachments == false)
            await #expect(throws: ChatSessionViewModel.ControlImageSendError.imagesUnsupported) {
                try await viewModel.sendTextWithControlImages(
                    "画像を送る",
                    submit: true,
                    images: [(mediaType: "image/png", data: png)]
                )
            }
            #expect(viewModel.attachmentStore.attachments.isEmpty)
        }
    }

    @MainActor
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
}

private enum UnknownModalityClientError: Error {
    case unsupported
}

private final class UnknownModalityCodexClient: StructuredAgentClient, CodexSettingsProviding, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let threadEvents: AsyncStream<ThreadEvent>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let threadEventContinuation: AsyncStream<ThreadEvent>.Continuation
    private let model: AppServerModel

    init(model: AppServerModel) {
        self.model = model
        var eventCaptured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { eventCaptured = $0 }
        eventContinuation = eventCaptured!
        var threadEventCaptured: AsyncStream<ThreadEvent>.Continuation?
        threadEvents = AsyncStream { threadEventCaptured = $0 }
        threadEventContinuation = threadEventCaptured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        eventContinuation.finish()
        threadEventContinuation.finish()
    }
    func activeThreadId() async -> String? { "thread-image" }
    func initialize(_ params: InitializeParams) async throws -> InitializeResponse {
        try decode(#"{"codexHome":"/tmp","platformFamily":"macOS","platformOs":"macOS","userAgent":"test"}"#)
    }
    func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        try decode(#"{"thread":{"id":"thread-image","status":{"type":"idle"}}}"#)
    }
    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        throw UnknownModalityClientError.unsupported
    }
    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        throw UnknownModalityClientError.unsupported
    }
    func listModels(_ params: ModelListParams) async throws -> ModelListResponse {
        let modelValue = try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(model)
        )
        let response = JSONValue.object(["data": .array([modelValue])])
        return try decode(JSONEncoder().encode(response))
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

    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func decode<T: Decodable>(_ data: Data) throws -> T {
        try JSONDecoder().decode(T.self, from: data)
    }
}
