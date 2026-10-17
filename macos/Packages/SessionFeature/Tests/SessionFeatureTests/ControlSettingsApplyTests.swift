import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

private enum SettingsJSON {
    static func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    static func model(id: String, displayName: String, isDefault: Bool, efforts: [String] = ["medium"]) -> String {
        let list = efforts.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"id":"\(id)","model":"\(id)","displayName":"\(displayName)","description":"",
        "hidden":false,"supportedReasoningEfforts":[\(list)],"defaultReasoningEffort":"medium",
        "isDefault":\(isDefault)}
        """
    }
}

private final class SettingsCodexClient: StructuredAgentClient, CodexSettingsProviding, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let threadEvents: AsyncStream<ThreadEvent>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let threadContinuation: AsyncStream<ThreadEvent>.Continuation
    private let lock = NSLock()
    private var recorded: [ThreadSettingsUpdateParams] = []
    /// 既定のモデルで選べる推論の深さ。
    var defaultModelEfforts = ["medium"]
    /// 設定の更新ごとに待つ時間（先頭から順に使う）。
    var updateDelays: [UInt64] = []
    /// 失敗させる設定の更新（届いた順の番号。0 始まり）。
    var failingUpdates: Set<Int> = []
    var failingError: any Error = CancellationError()
    var updateBarrier: AsyncStream<Void>?
    private var started = 0
    /// 届き始めた設定の更新の数（待ちに入ったものも含む）。
    var startedUpdates: Int { lock.withLock { started } }

    var updatedSettings: [ThreadSettingsUpdateParams] { lock.withLock { recorded } }

    /// app-server からの設定の通知（どの変更の結果かは載らない）。
    func emitSettings(model: String, effort: String, mode: String = "default", profile: String? = nil, sandbox: String = "workspaceWrite", approvalPolicy: ApprovalPolicy = .named("never")) throws {
        let policyJSON = String(decoding: try JSONEncoder().encode(approvalPolicy), as: UTF8.self)
        let settings: ThreadSettings = try SettingsJSON.decode("""
        {"cwd":"/tmp","model":"\(model)","modelProvider":"openai","effort":"\(effort)","approvalPolicy":\(policyJSON),"approvalsReviewer":"user","sandboxPolicy":{"type":"\(sandbox)"},"activePermissionProfile":\(profile.map { #"{"id":"\#($0)","extends":null}"# } ?? "null"),"serviceTier":null,"collaborationMode":{"mode":"\(mode)","settings":{"model":"\(model)","reasoning_effort":"\(effort)","developer_instructions":null}}}
        """)
        threadContinuation.yield(.threadSettingsUpdated(threadId: "thread-1", threadSettings: settings))
    }

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
        try SettingsJSON.decode(
            #"{"codexHome":"/tmp","platformFamily":"macOS","platformOs":"macOS","userAgent":"test"}"#
        )
    }

    func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        let policy = try JSONEncoder().encode(params.approvalPolicy)
        let sandbox = try JSONEncoder().encode(params.sandbox)
        return try SettingsJSON.decode("""
        {"thread":{"id":"thread-1","status":{"type":"idle"}},"approvalPolicy":\(String(decoding: policy, as: UTF8.self)),"sandbox":\(String(decoding: sandbox, as: UTF8.self))}
        """)
    }

    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        try await threadStart(ThreadStartParams(approvalPolicy: params.approvalPolicy, sandbox: params.sandbox))
    }

    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        try SettingsJSON.decode(#"{"thread":{"id":"thread-1","turns":[]}}"#)
    }

    func listModels(_ params: ModelListParams) async throws -> ModelListResponse {
        try SettingsJSON.decode("""
        {"data":[\(SettingsJSON.model(id: "gpt-5.5-codex", displayName: "GPT-5.5 Codex", isDefault: true, efforts: defaultModelEfforts)),
        \(SettingsJSON.model(id: "gpt-5.5-codex-mini", displayName: "GPT-5.5 Codex mini", isDefault: false))]}
        """)
    }

    func listPermissionProfiles(_ params: PermissionProfileListParams) async throws -> PermissionProfileListResponse {
        try SettingsJSON.decode(#"{"data":[{"id":":workspace"},{"id":":read-only"}]}"#)
    }

    /// プラン モードを選べるようにするか。
    var offersPlanMode = false

    func listCollaborationModes(_ params: CollaborationModeListParams) async throws -> CollaborationModeListResponse {
        try SettingsJSON.decode(offersPlanMode
            ? #"{"data":[{"name":"Plan","mode":"plan","model":null,"reasoning_effort":null},{"name":"Default","mode":"default","model":null,"reasoning_effort":null}]}"#
            : #"{"data":[]}"#)
    }

    /// 受け取った順に記録する（app-server は届いた順に適用する）。応答だけを遅らせる。
    func updateThreadSettings(_ params: ThreadSettingsUpdateParams) async throws -> ThreadSettingsUpdateResponse {
        let (delay, fails): (UInt64?, Bool) = lock.withLock {
            started += 1
            recorded.append(params)
            return (updateDelays.isEmpty ? nil : updateDelays.removeFirst(), failingUpdates.contains(started - 1))
        }
        if let delay { try? await Task.sleep(nanoseconds: delay) }
        if fails { throw failingError }
        if let updateBarrier {
            var iterator = updateBarrier.makeAsyncIterator()
            _ = await iterator.next()
        }
        return ThreadSettingsUpdateResponse()
    }
}


@MainActor @Suite struct ControlSettingsApplyTests {
    private func vm(_ client: SettingsCodexClient) -> ChatSessionViewModel {
        ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: nil)
    }

    @Test func codexNotReadyPrecedesValidation() async {
        let model = vm(SettingsCodexClient())
        #expect(await model.applyControlSettings(.init(effort: "unknown", permission: .some("unknown"))) == .notReady)
        await model.terminate()
    }

    @Test func codexPermissionExitsPlanThenEntersPlanThenAppliesEffort() async throws {
        let client = SettingsCodexClient()
        client.offersPlanMode = true
        let model = vm(client)
        try await model.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        try await model.setPlanMode(true)
        let before = client.updatedSettings.count
        #expect(await model.applyControlSettings(.init(effort: "medium", permission: .some(":workspace"), planMode: true)) == .applied)
        let updates = Array(client.updatedSettings.dropFirst(before))
        #expect(updates.count == 4)
        #expect(updates[0].permissions == ":workspace")
        #expect(updates[1].collaborationMode?.mode == .default)
        #expect(updates[2].collaborationMode?.mode == .plan)
        #expect(updates[3].effort == "medium")
        #expect(updates[3].model == model.selectedModel)
        #expect(model.isPlanMode)
        await model.terminate()
    }

    @Test func codexInvalidAndUnsupportedValidateBeforeApplying() async throws {
        let client = SettingsCodexClient()
        let model = vm(client)
        try await model.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        let before = client.updatedSettings.count
        #expect(await model.applyControlSettings(.init(effort: "medium", permission: .some(":workspace"), planMode: true)) == .unsupported("planMode"))
        #expect(await model.applyControlSettings(.init(effort: "unknown", permission: .some(":workspace"))) == .invalidValue("effort"))
        #expect(await model.applyControlSettings(.init(permission: .some("plan"))) == .invalidValue("permission"))
        #expect(client.updatedSettings.count == before)
        await model.terminate()
    }

    @Test func failedPermissionDoesNotApplyPlanOrEffort() async throws {
        let client = SettingsCodexClient()
        let model = vm(client)
        try await model.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        client.failingUpdates = [client.startedUpdates]
        let before = client.updatedSettings.count
        #expect(await model.applyControlSettings(.init(effort: "medium", permission: .some(":workspace"))) == .failed)
        #expect(client.updatedSettings.count == before + 1)
        await model.terminate()
    }
}
