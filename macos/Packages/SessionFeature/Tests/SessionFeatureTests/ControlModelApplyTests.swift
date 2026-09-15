// Control API からのモデル変更（GET /sessions/{id}/settings・POST /sessions/{id}/model）の
// VM 側窓口を検査する。codex は app-server の updateThreadSettings、
// spawn 型（Claude/Cursor）は CLI フラグ差し替えという2系統を1つの outcome へ写像する。

import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private enum ControlModelJSON {
    static func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func model(id: String, displayName: String, isDefault: Bool) -> String {
        """
        {"id":"\(id)","model":"\(id)","displayName":"\(displayName)","description":"",
        "hidden":false,"supportedReasoningEfforts":["medium"],"defaultReasoningEffort":"medium",
        "isDefault":\(isDefault)}
        """
    }
}

private final class ControlModelCodexClient: StructuredAgentClient, CodexSettingsProviding, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let threadEvents: AsyncStream<ThreadEvent>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let threadContinuation: AsyncStream<ThreadEvent>.Continuation
    private let lock = NSLock()
    private var recorded: [ThreadSettingsUpdateParams] = []

    var updatedSettings: [ThreadSettingsUpdateParams] { lock.withLock { recorded } }

    init() {
        var capturedEvent: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { capturedEvent = $0 }
        eventContinuation = capturedEvent!
        var capturedThread: AsyncStream<ThreadEvent>.Continuation?
        threadEvents = AsyncStream { capturedThread = $0 }
        threadContinuation = capturedThread!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        eventContinuation.finish()
        threadContinuation.finish()
    }

    func activeThreadId() async -> String? { "thread-1" }

    func initialize(_ params: InitializeParams) async throws -> InitializeResponse {
        try ControlModelJSON.decode(
            #"{"codexHome":"/tmp","platformFamily":"macOS","platformOs":"macOS","userAgent":"test"}"#
        )
    }

    func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        try ControlModelJSON.decode(#"{"thread":{"id":"thread-1","status":{"type":"idle"}}}"#)
    }

    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        try ControlModelJSON.decode(#"{"thread":{"id":"thread-1","status":{"type":"idle"}}}"#)
    }

    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        try ControlModelJSON.decode(#"{"thread":{"id":"thread-1","turns":[]}}"#)
    }

    func listModels(_ params: ModelListParams) async throws -> ModelListResponse {
        try ControlModelJSON.decode("""
        {"data":[\(ControlModelJSON.model(id: "gpt-5.5-codex", displayName: "GPT-5.5 Codex", isDefault: true)),
        \(ControlModelJSON.model(id: "gpt-5.5-codex-mini", displayName: "GPT-5.5 Codex mini", isDefault: false))]}
        """)
    }

    func listPermissionProfiles(_ params: PermissionProfileListParams) async throws -> PermissionProfileListResponse {
        try ControlModelJSON.decode(#"{"data":[]}"#)
    }

    func listCollaborationModes(_ params: CollaborationModeListParams) async throws -> CollaborationModeListResponse {
        try ControlModelJSON.decode(#"{"data":[]}"#)
    }

    func updateThreadSettings(_ params: ThreadSettingsUpdateParams) async throws -> ThreadSettingsUpdateResponse {
        lock.withLock { recorded.append(params) }
        return ThreadSettingsUpdateResponse()
    }
}

private final class ControlModelSpawnClient: StructuredAgentClient, SpawnAgentSettingsControlling, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent> = AsyncStream { _ in }
    private let lock = NSLock()
    private var recorded: [String?] = []

    var appliedModels: [String?] { lock.withLock { recorded } }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {}

    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        lock.withLock { recorded.append(model) }
    }
}

@MainActor
@Suite struct ControlModelApplyTests {

    private func makeCodexViewModel(client: ControlModelCodexClient) -> ChatSessionViewModel {
        ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/control-model"
        )
    }

    @Test func codexAdvertisesLiveModelsAndAppliesSelection() async throws {
        let client = ControlModelCodexClient()
        let vm = makeCodexViewModel(client: client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        defer { Task { await vm.terminate() } }

        #expect(vm.controlModelChoices.map(\.id) == ["gpt-5.5-codex", "gpt-5.5-codex-mini"])
        #expect(vm.controlModelChoices.map(\.displayName) == ["GPT-5.5 Codex", "GPT-5.5 Codex mini"])

        let outcome = await vm.applyControlModel("gpt-5.5-codex-mini")

        #expect(outcome == .applied)
        #expect(vm.selectedModel == "gpt-5.5-codex-mini")
        #expect(client.updatedSettings.last?.model == "gpt-5.5-codex-mini")
    }

    @Test func codexRejectsUnknownModel() async throws {
        let client = ControlModelCodexClient()
        let vm = makeCodexViewModel(client: client)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        defer { Task { await vm.terminate() } }

        let outcome = await vm.applyControlModel("no-such-model")

        #expect(outcome == .unknownModel)
        #expect(client.updatedSettings.isEmpty)
    }

    @Test func codexBeforeStartAdvertisesNothingAndIsUnsupported() async {
        let client = ControlModelCodexClient()
        let vm = makeCodexViewModel(client: client)

        // startNew を呼んでいない＝thread 未開始。候補も未取得なので unsupported で広告もしない。
        #expect(vm.controlModelChoices.isEmpty)
        #expect(await vm.applyControlModel("gpt-5.5-codex") == .unsupported)
    }

    @Test func spawnAgentAppliesKnownModelAndRejectsUnknown() async throws {
        let client = ControlModelSpawnClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/control-model"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        defer { Task { await vm.terminate() } }

        let known = try #require(vm.availableSpawnAgentModels.first)
        #expect(vm.controlModelChoices.map(\.id) == vm.availableSpawnAgentModels)
        #expect(await vm.applyControlModel(known) == .applied)
        #expect(vm.selectedModel == known)
        #expect(await vm.applyControlModel("no-such-model") == .unknownModel)
    }
}
