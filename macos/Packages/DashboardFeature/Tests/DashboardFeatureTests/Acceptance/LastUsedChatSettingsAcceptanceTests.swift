// task-7 受け入れテスト（PM 著・実装役は編集禁止）

import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

private final class RecordingSpawnClient: StructuredAgentClient, SpawnAgentSettingsControlling, @unchecked Sendable {
    struct Applied: Equatable {
        var model: String?
        var permissionOrMode: String?
        var effort: String?
    }

    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var applied: [Applied] = []

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        lock.withLock { applied.append(Applied(model: model, permissionOrMode: permissionOrMode, effort: effort)) }
    }

    func lastApplied() -> Applied? {
        lock.withLock { applied.last }
    }
}

@Test @MainActor
func startNew_appliesLastUsedModelAndEffortForClaudeSpawnSession() async throws {
    let client = RecordingSpawnClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write"),
        persistedSettings: CodexAppServerSessionSettings(selectedModel: "fable", selectedEffort: "max")
    )
    #expect(vm.selectedModel == "fable")
    #expect(vm.selectedEffort == "max")
    let applied = try #require(client.lastApplied())
    #expect(applied.model == "fable")
    #expect(applied.effort == "max")
}

@Test @MainActor
func startNew_withoutPersistedSettingsKeepsExistingDefaults() async throws {
    let client = RecordingSpawnClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    // 既定挙動の回帰ガード: 保存値なしなら従来どおり先頭 alias（opus）+ 既定 effort（high）。
    #expect(vm.selectedModel == "opus")
    #expect(vm.selectedEffort == "high")
}

@Test
func lastUsedStore_roundTripsPerAgentAndIsolatesAgents() throws {
    let suiteName = "phlox-acceptance-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = LastUsedChatSettingsStore(defaults: defaults)

    store.record(agentID: "claude-code", model: "fable", effort: "max")
    store.record(agentID: "codex", model: "gpt-5.2-codex", effort: nil)

    #expect(store.lastUsed(agentID: "claude-code") == LastUsedChatSettings(model: "fable", effort: "max"))
    #expect(store.lastUsed(agentID: "codex") == LastUsedChatSettings(model: "gpt-5.2-codex", effort: nil))
    #expect(store.lastUsed(agentID: "cursor") == nil)

    // 上書き: 最後に記録した値が勝つ。
    store.record(agentID: "claude-code", model: "sonnet", effort: "high")
    #expect(store.lastUsed(agentID: "claude-code") == LastUsedChatSettings(model: "sonnet", effort: "high"))
}
