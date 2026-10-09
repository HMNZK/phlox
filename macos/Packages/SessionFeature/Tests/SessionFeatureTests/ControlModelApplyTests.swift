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

    static func model(id: String, displayName: String, isDefault: Bool, efforts: [String] = ["medium"]) -> String {
        let list = efforts.map { "\"\($0)\"" }.joined(separator: ",")
        return """
        {"id":"\(id)","model":"\(id)","displayName":"\(displayName)","description":"",
        "hidden":false,"supportedReasoningEfforts":[\(list)],"defaultReasoningEffort":"medium",
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
        let settings: ThreadSettings = try ControlModelJSON.decode("""
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
        try ControlModelJSON.decode(
            #"{"codexHome":"/tmp","platformFamily":"macOS","platformOs":"macOS","userAgent":"test"}"#
        )
    }

    func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        let policy = try JSONEncoder().encode(params.approvalPolicy)
        let sandbox = try JSONEncoder().encode(params.sandbox)
        return try ControlModelJSON.decode("""
        {"thread":{"id":"thread-1","status":{"type":"idle"}},"approvalPolicy":\(String(decoding: policy, as: UTF8.self)),"sandbox":\(String(decoding: sandbox, as: UTF8.self))}
        """)
    }

    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        try await threadStart(ThreadStartParams(approvalPolicy: params.approvalPolicy, sandbox: params.sandbox))
    }

    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        try ControlModelJSON.decode(#"{"thread":{"id":"thread-1","turns":[]}}"#)
    }

    func listModels(_ params: ModelListParams) async throws -> ModelListResponse {
        try ControlModelJSON.decode("""
        {"data":[\(ControlModelJSON.model(id: "gpt-5.5-codex", displayName: "GPT-5.5 Codex", isDefault: true, efforts: defaultModelEfforts)),
        \(ControlModelJSON.model(id: "gpt-5.5-codex-mini", displayName: "GPT-5.5 Codex mini", isDefault: false))]}
        """)
    }

    func listPermissionProfiles(_ params: PermissionProfileListParams) async throws -> PermissionProfileListResponse {
        try ControlModelJSON.decode(#"{"data":[]}"#)
    }

    /// プラン モードを選べるようにするか。
    var offersPlanMode = false

    func listCollaborationModes(_ params: CollaborationModeListParams) async throws -> CollaborationModeListResponse {
        try ControlModelJSON.decode(offersPlanMode
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

    private var recordedEfforts: [String?] = []
    var appliedEfforts: [String?] { lock.withLock { recordedEfforts } }

    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        lock.withLock {
            recorded.append(model)
            recordedEfforts.append(effort)
        }
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

// 入力欄の ⇧Tab: いまのモデルで選べる推論の深さを 1 段ずつ回し、最後の次は最初へ戻る。
@MainActor
@Suite struct EffortCycleTests {
    @Test func nextEffortWrapsAroundAndStartsFromTheFirst() {
        let levels = ["low", "medium", "high"]
        #expect(ChatSessionViewModel.nextEffort(after: "low", in: levels) == "medium")
        #expect(ChatSessionViewModel.nextEffort(after: "high", in: levels) == "low")
        #expect(ChatSessionViewModel.nextEffort(after: nil, in: levels) == "low")
        #expect(ChatSessionViewModel.nextEffort(after: "max", in: levels) == "low")
        #expect(ChatSessionViewModel.nextEffort(after: "medium", in: ["medium"]) == nil)
        #expect(ChatSessionViewModel.nextEffort(after: nil, in: []) == nil)
    }

    @Test(arguments: ["opus", "haiku"])
    func claudeCyclesThroughItsEffortsAndAppliesThem(model: String) async throws {
        let client = ControlModelSpawnClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/effort-cycle"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        defer { Task { await vm.terminate() } }
        await vm.setSpawnAgentModel(model)
        let levels = vm.cyclableEfforts
        #expect(levels.count > 1)
        await vm.setSpawnAgentEffort(levels.last)

        let next = await vm.cycleEffort()

        #expect(next == levels.first)
        #expect(vm.selectedEffort == levels.first)
        #expect(client.appliedEfforts.last == levels.first)
    }

    @Test func claudeModelWithoutEffortDoesNothing() async throws {
        let client = ControlModelSpawnClient()
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.claudeCode),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/effort-cycle"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        defer { Task { await vm.terminate() } }
        await vm.setSpawnAgentModel("claude-haiku-4-5")
        let applied = client.appliedEfforts.count

        #expect(vm.cyclableEfforts.isEmpty)
        #expect(await vm.cycleEffort() == nil)
        #expect(client.appliedEfforts.count == applied)
    }

    @Test func codexCyclesThroughTheSelectedModelsEfforts() async throws {
        let client = ControlModelCodexClient()
        client.defaultModelEfforts = ["low", "medium", "high"]
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/effort-cycle"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        defer { Task { await vm.terminate() } }
        try await vm.setModel(model: "gpt-5.5-codex", effort: "medium")
        #expect(vm.cyclableEfforts == ["low", "medium", "high"])

        #expect(await vm.cycleEffort() == "high")
        #expect(await vm.cycleEffort() == "low")
        #expect(client.updatedSettings.last?.model == "gpt-5.5-codex")
        #expect(client.updatedSettings.last?.effort == "low")
    }

    /// 続けて押したとき、先の反映が遅れても最後に選んだ段が残る。
    @Test func rapidPressesApplyInOrder() async throws {
        let client = ControlModelCodexClient()
        client.defaultModelEfforts = ["low", "medium", "high"]
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/effort-cycle"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        defer { Task { await vm.terminate() } }
        try await vm.setModel(model: "gpt-5.5-codex", effort: "medium")
        client.updateDelays = [100_000_000, 0]

        async let first = vm.cycleEffort()
        async let second = vm.cycleEffort()
        let results = await [first, second]

        // どちらが先に走っても、medium → high → low と 1 段ずつ進む（並行すると 2 回とも high になる）。
        #expect(Set(results.compactMap { $0 }) == ["high", "low"])
        #expect(vm.selectedEffort == "low")
        #expect(client.updatedSettings.last?.effort == "low")
    }

    private func makeCodexViewModel(_ client: ControlModelCodexClient) async throws -> ChatSessionViewModel {
        client.defaultModelEfforts = ["low", "medium", "high"]
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/effort-cycle"
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        try await vm.setModel(model: "gpt-5.5-codex", effort: "medium")
        return vm
    }

    /// ⇧Tab の応答が遅れている間にメニューで別のモデルを選んでも、あとから選んだモデルが画面に残る。
    @Test func menuChoiceMadeWhileAShiftTabIsPendingWins() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }
        client.updateDelays = [100_000_000]
        let before = client.startedUpdates

        let cycle = Task { await vm.cycleEffort() }
        await waitUntil { !(client.startedUpdates == before) }
        try await vm.setModel(model: "gpt-5.5-codex-mini", effort: nil)
        _ = await cycle.value

        #expect(vm.selectedModel == "gpt-5.5-codex-mini")
        #expect(client.updatedSettings.last?.model == "gpt-5.5-codex-mini")
    }

    /// 変更の応答を待っている間に前の設定の通知が届いても、画面のモデル・深さを前に戻さない。
    @Test func settingsNotificationWhileAChangeIsPendingDoesNotRevert() async throws {
        let client = ControlModelCodexClient()
        client.offersPlanMode = true
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }
        client.updateDelays = [200_000_000]
        let before = client.startedUpdates

        let change = Task { try await vm.setModel(model: "gpt-5.5-codex-mini", effort: nil) }
        await waitUntil { !(client.startedUpdates == before) }
        // 通知が処理されたことは、守らない権限の表示が変わったことで確かめる。
        try client.emitSettings(model: "gpt-5.5-codex", effort: "low", mode: "plan", profile: ":workspace")
        await waitUntil { !(vm.selectedPermissionProfile != ":workspace") }
        #expect(vm.selectedModel == "gpt-5.5-codex")
        #expect(vm.selectedEffort == "medium")
        #expect(vm.isPlanMode == false)
        try await change.value

        #expect(vm.selectedModel == "gpt-5.5-codex-mini")
        // 待っている変更が無ければ、通知はそのまま画面に反映する。
        try client.emitSettings(model: "gpt-5.5-codex", effort: "high")
        for _ in 0..<200 where vm.selectedEffort != "high" { try await Task.sleep(nanoseconds: 5_000_000) }
        #expect(vm.selectedModel == "gpt-5.5-codex")
        #expect(vm.selectedEffort == "high")
    }

    /// 旧形式で始めた thread の設定通知は権限プロファイルが null。実際の sandbox から権限を表示する。
    @Test func settingsNotificationWithoutProfileShowsPermissionFromSandbox() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }

        try client.emitSettings(model: "gpt-5.5-codex", effort: "low", profile: nil, sandbox: "dangerFullAccess")
        await waitUntil { vm.selectedEffort == "low" }

        #expect(vm.selectedPermissionProfile == ":danger-full-access")
    }

    /// プラン モードの切り替えの応答より先に、後から選んだモデルの応答が返っても、選んだモデルが残る。
    @Test func laterModelChoiceWinsOverASlowPlanModeToggle() async throws {
        let client = ControlModelCodexClient()
        client.offersPlanMode = true
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }
        client.updateDelays = [100_000_000]
        let before = client.startedUpdates

        let toggle = Task { try await vm.setPlanMode(true) }
        await waitUntil { !(client.startedUpdates == before) }
        try await vm.setModel(model: "gpt-5.5-codex-mini", effort: nil)
        try await toggle.value

        #expect(vm.selectedModel == "gpt-5.5-codex-mini")
    }

    /// 遅れて失敗した前のプラン モードの切り替えで、後から通った切り替えを取り消さない。
    @Test func slowFailedPlanModeToggleDoesNotUndoALaterOne() async throws {
        let client = ControlModelCodexClient()
        client.offersPlanMode = true
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }
        client.updateDelays = [100_000_000]
        client.failingUpdates = [client.startedUpdates]
        let before = client.startedUpdates

        let slow = Task { try await vm.setPlanMode(true) }
        await waitUntil { !(client.startedUpdates == before) }
        try await vm.setPlanMode(true)
        _ = try? await slow.value

        #expect(vm.isPlanMode)
        #expect(vm.isPlanModeAvailable)
    }

    /// ⇧Tab の応答待ちの間にメニューで選び直しても、⇧Tab は失敗扱いにしない。
    @Test func shiftTabSupersededByAMenuChoiceIsNotAFailure() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }
        client.updateDelays = [100_000_000]
        let before = client.startedUpdates

        let cycle = Task { await vm.cycleEffort() }
        await waitUntil { !(client.startedUpdates == before) }
        try await vm.setModel(model: "gpt-5.5-codex", effort: "low")

        #expect(await cycle.value == "high")
        #expect(vm.selectedEffort == "low")
    }

    /// 保存済みの設定の再適用が通らなかったら、画面をその値にしない。
    @Test func failedPersistedSettingsReapplyDoesNotShowTheStoredModel() async throws {
        let client = ControlModelCodexClient()
        client.failingUpdates = [0]
        let vm = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/effort-cycle"
        )
        defer { Task { await vm.terminate() } }
        try await vm.startNew(
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write"),
            persistedSettings: CodexAppServerSessionSettings(
                selectedModel: "gpt-5.5-codex-mini",
                selectedEffort: "low",
                selectedPermissionProfile: nil,
                isPlanMode: false
            )
        )

        #expect(client.updatedSettings.first?.model == "gpt-5.5-codex-mini")
        #expect(vm.selectedModel != "gpt-5.5-codex-mini")
        #expect(vm.selectedEffort != "low")
    }

    @Test func fullAccessChangesApprovalAndExecutionBoundariesTogether() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }

        try await vm.setPermissionProfile(id: ":danger-full-access")

        #expect(client.updatedSettings.last?.permissions == ":danger-full-access")
        #expect(client.updatedSettings.last?.approvalPolicy == .named("never"))
    }

    @Test func restrictedPresetsRestoreInteractiveApprovals() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }

        for profile in [":read-only", ":workspace"] {
            try await vm.setPermissionProfile(id: profile)
            #expect(client.updatedSettings.last?.approvalPolicy == .named("on-request"))
        }
        try await vm.setPermissionProfile(id: "project-profile")
        #expect(client.updatedSettings.last?.approvalPolicy == nil)
    }

    @Test func legacyFullAccessReapplyIncludesNeverAndFailureKeepsConfirmedProfile() async throws {
        let client = ControlModelCodexClient()
        client.failingUpdates = [0]
        let vm = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/permission-reapply"
        )
        defer { Task { await vm.terminate() } }
        try await vm.startNew(
            approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"),
            persistedSettings: CodexAppServerSessionSettings(selectedPermissionProfile: ":danger-full-access")
        )

        #expect(client.updatedSettings.first?.approvalPolicy == .named("never"))
        #expect(vm.selectedPermissionProfile == ":workspace")
    }

    @Test func permissionDisplayUsesConfirmedPolicyInsteadOfSelectedProfileAlone() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }
        #expect(vm.codexPermissionTitle(languageCode: "ja") == "Default")

        try await vm.setPermissionProfile(id: ":danger-full-access")
        // RPC 応答だけでは実際の設定が分からないので、確認された前の状態を維持する。
        #expect(vm.codexPermissionTitle(languageCode: "ja") == "Default")
        try client.emitSettings(model: "gpt-5.5-codex", effort: "low", profile: ":danger-full-access", sandbox: "dangerFullAccess", approvalPolicy: .named("on-request"))
        await waitUntil { vm.selectedPermissionProfile == ":danger-full-access" }
        #expect(vm.codexPermissionTitle(languageCode: "ja") == "Custom")
        #expect(vm.selectedCodexPermissionPreset == nil)

        try client.emitSettings(model: "gpt-5.5-codex", effort: "low", profile: ":danger-full-access", sandbox: "dangerFullAccess")
        await waitUntil { vm.selectedApprovalPolicy == .named("never") }
        #expect(vm.codexPermissionTitle(languageCode: "ja") == "Full Access")
        #expect(vm.codexSettingsSnapshot?.approvalPolicyJSON == #""never""#)
    }

    @Test func slowPermissionAcknowledgmentDoesNotUndoNewerConfirmedSettings() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }
        client.updateDelays = [100_000_000]
        let before = client.startedUpdates
        let slow = Task { try await vm.setPermissionProfile(id: ":danger-full-access") }
        await waitUntil { client.startedUpdates > before }
        try await vm.setPermissionProfile(id: ":workspace")
        try client.emitSettings(model: "gpt-5.5-codex", effort: "medium", profile: ":workspace", approvalPolicy: .named("on-request"))
        await waitUntil { vm.selectedApprovalPolicy == .named("on-request") }
        try await slow.value
        #expect(vm.codexPermissionTitle(languageCode: "ja") == "Default")
    }

    @Test func failedPermissionChangePreservesStateAndReportsError() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        defer { Task { await vm.terminate() } }
        client.failingUpdates = [client.startedUpdates]
        client.failingError = JSONRPCClientError.serverError(code: -32000, message: "sandbox not permitted")
        await #expect(throws: JSONRPCClientError.serverError(code: -32000, message: "sandbox not permitted")) {
            try await vm.setPermissionProfile(id: ":danger-full-access")
        }
        #expect(vm.codexPermissionTitle(languageCode: "ja") == "Default")
        #expect(vm.transcript.contains { item in
            if case .error(_, let message, _) = item {
                return message == "権限を変更できませんでした: sandbox not permitted"
            }
            return false
        })
    }

    @Test func restoredGranularPolicyAndSnapshotRetainTheirOriginalForm() async throws {
        let json = #"{"granular":{"sandbox_approval":false,"rules":true}}"#
        let policy = try JSONDecoder().decode(ApprovalPolicy.self, from: Data(json.utf8))
        let client = ControlModelCodexClient()
        let vm = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/permission-restore"
        )
        defer { Task { await vm.terminate() } }
        await vm.restore(
            threadId: "thread-1", approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"),
            persistedSettings: CodexAppServerSessionSettings(selectedPermissionProfile: ":workspace", approvalPolicyJSON: json)
        )
        #expect(client.updatedSettings.first?.approvalPolicy == policy)
        try client.emitSettings(model: "gpt-5.5-codex", effort: "low", profile: ":workspace", approvalPolicy: policy)
        await waitUntil { vm.selectedApprovalPolicy == policy }
        let savedJSON = try #require(vm.codexSettingsSnapshot?.approvalPolicyJSON)
        #expect(try JSONDecoder().decode(ApprovalPolicy.self, from: Data(savedJSON.utf8)) == policy)
        #expect(vm.codexPermissionTitle(languageCode: "ja") == "Custom")
    }

    @Test func restoreAcceptsPermissionNotificationBeforeTranscriptIsCommitted() async throws {
        let client = ControlModelCodexClient()
        let barrier = AsyncStream<Void>.makeStream()
        client.updateBarrier = barrier.stream
        let vm = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/permission-restore"
        )
        defer { barrier.continuation.finish(); Task { await vm.terminate() } }
        let restore = Task {
            await vm.restore(
                threadId: "thread-1", approvalPolicy: .named("never"), sandbox: .named("danger-full-access"),
                persistedSettings: CodexAppServerSessionSettings(
                    selectedPermissionProfile: ":read-only", approvalPolicyJSON: #""on-request""#
                )
            )
        }
        await waitUntil { client.startedUpdates == 1 }
        try client.emitSettings(model: "gpt-5.5-codex", effort: "medium", profile: ":read-only",
                                sandbox: "readOnly", approvalPolicy: .named("on-request"))
        await waitUntil { vm.selectedPermissionProfile == ":read-only" }
        #expect(vm.threadId == nil)
        #expect(vm.codexPermissionTitle(languageCode: "ja") == "Read Only")
        barrier.continuation.yield(())
        await restore.value
        #expect(vm.codexSettingsSnapshot?.selectedPermissionProfile == ":read-only")
        #expect(vm.codexSettingsSnapshot?.approvalPolicyJSON == #""on-request""#)
    }

    @Test func successfulRestoreWaitsForPermissionNotificationBeforeSaving() async throws {
        let client = ControlModelCodexClient()
        let vm = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/permission-restore"
        )
        var stored = CodexAppServerSessionSettings(
            selectedPermissionProfile: ":read-only", approvalPolicyJSON: #""on-request""#
        )
        let saved = stored
        var saves = 0
        vm.codexSettingsDidChange = { if let value = $0 { stored = value }; saves += 1 }
        await vm.restore(
            threadId: "thread-1", approvalPolicy: .named("never"), sandbox: .named("danger-full-access"),
            persistedSettings: saved
        )
        #expect(stored == saved)
        #expect(saves == 0)
        try client.emitSettings(model: "gpt-5.5-codex", effort: "low", profile: ":read-only", sandbox: "readOnly", approvalPolicy: .named("on-request"))
        await waitUntil { saves > 0 }
        #expect(stored.selectedPermissionProfile == ":read-only")
        #expect(stored.approvalPolicyJSON == #""on-request""#)
        await vm.terminate()
    }

    @Test func permissionSelectionIsSavedOnlyAfterServerNotification() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        var saved: CodexAppServerSessionSettings?
        vm.codexSettingsDidChange = { saved = $0 }
        try await vm.setPermissionProfile(id: ":read-only")
        #expect(saved == nil)
        try client.emitSettings(model: "gpt-5.5-codex", effort: "low", profile: ":read-only", sandbox: "readOnly", approvalPolicy: .named("on-request"))
        await waitUntil { saved != nil }
        #expect(saved?.selectedPermissionProfile == ":read-only")
        #expect(saved?.approvalPolicyJSON == #""on-request""#)
        await vm.terminate()
    }

    @Test func failedSavedPermissionRestoreDoesNotOverwriteSavedSettings() async {
        let client = ControlModelCodexClient()
        client.failingUpdates = [0]
        let reason = """
        sandbox not permitted
        The configured permissions profile does not allow access outside the project. Choose an allowed profile or update the workspace policy before retrying.
        """
        client.failingError = JSONRPCClientError.serverError(code: -32000, message: reason)
        let vm = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.codex), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/permission-restore"
        )
        let saved = CodexAppServerSessionSettings(
            selectedPermissionProfile: ":read-only", approvalPolicyJSON: #""on-request""#
        )
        var stored: CodexAppServerSessionSettings? = saved
        var saves = 0
        vm.codexSettingsDidChange = { stored = $0; saves += 1 }
        await vm.restore(
            threadId: "thread-1", approvalPolicy: .named("never"), sandbox: .named("danger-full-access"),
            persistedSettings: saved
        )
        #expect(vm.selectedPermissionProfile != ":read-only")
        #expect(stored == saved)
        #expect(saves == 0)
        #expect(vm.transcript.contains {
            if case .error(_, let message, _) = $0 {
                return message == "保存された設定を適用できませんでした: \(reason)"
            }
            return false
        })
        await vm.terminate()
    }

    /// 終了し始めたら ⇧Tab は何も送らない。
    @Test func nothingIsSentAfterTermination() async throws {
        let client = ControlModelCodexClient()
        let vm = try await makeCodexViewModel(client)
        await vm.terminate()
        let sent = client.updatedSettings.count

        #expect(await vm.cycleEffort() == nil)
        #expect(client.updatedSettings.count == sent)
    }
}

/// 条件が成り立つまで待つ。2 秒たっても成り立たなければ失敗として止める（退行でテストが止まり続けないように）。
@MainActor
private func waitUntil(_ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition() {
        guard ContinuousClock.now < deadline else {
            Issue.record("待っている状態にならなかった")
            return
        }
        await Task.yield()
    }
}
