// ChatSessionViewModel 分割前安全網（Run 2 / task-6）
// 監査 A: C3 永続化 FIFO・C13 背景タスク・C6 reapplyPersistedSettings の差分特性化。

import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - Test doubles

private actor SuspendedFirstSnapshotStore: TranscriptStore {
    private(set) var startedSnapshots: [[ChatItem]] = []
    private(set) var completedSnapshots: [[ChatItem]] = []
    private(set) var upsertedBatches: [[ChatItem]] = []
    private var firstSnapshotContinuation: CheckedContinuation<Void, Never>?

    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] {
        completedSnapshots.last ?? []
    }

    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        upsertedBatches.append(items)
    }

    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {
        startedSnapshots.append(items)
        if startedSnapshots.count == 1 {
            await withCheckedContinuation { firstSnapshotContinuation = $0 }
        }
        completedSnapshots.append(items)
    }

    func releaseFirstSnapshot() {
        firstSnapshotContinuation?.resume()
        firstSnapshotContinuation = nil
    }
}

private final class FailingPlanReapplyTransport: AppServerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var settingsUpdateCount = 0
    private var paramsByMethod: [String: [[String: Any]]] = [:]

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    func send(_ data: Data) async throws {
        let line: Data
        if let newline = data.firstIndex(of: 0x0A) {
            line = Data(data[..<newline])
        } else {
            line = data
        }
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              let method = object["method"] as? String,
              let id = object["id"] else {
            return
        }

        if method == "thread/settings/update" {
            let params = object["params"] as? [String: Any] ?? [:]
            lock.withLock {
                paramsByMethod[method, default: []].append(params)
            }
            let attempt = lock.withLock {
                settingsUpdateCount += 1
                return settingsUpdateCount
            }
            if attempt == 1, params["collaborationMode"] != nil {
                receiveObject([
                    "jsonrpc": "2.0",
                    "id": id,
                    "error": ["code": -32000, "message": "plan mode rejected"],
                ])
                return
            }
        }

        let result: [String: Any]
        switch method {
        case "initialize":
            result = [
                "codexHome": "/tmp/codex",
                "platformFamily": "mac",
                "platformOs": "macos",
                "userAgent": "codex-test/1",
            ]
        case "thread/resume":
            result = [
                "thread": ["id": "thread-1", "status": ["type": "idle"]],
                "approvalPolicy": "never",
                "approvalsReviewer": "user",
                "sandbox": ["type": "workspaceWrite"],
                "model": "gpt-5-codex",
                "reasoningEffort": "medium",
                "activePermissionProfile": ["id": ":workspace", "extends": NSNull()],
            ]
        case "thread/read":
            result = ["thread": ["id": "thread-1", "status": ["type": "idle"], "turns": []]]
        case "model/list":
            result = ["data": [[
                "id": "gpt-5-codex",
                "model": "gpt-5-codex",
                "displayName": "GPT-5 Codex",
                "hidden": false,
                "supportedReasoningEfforts": [],
                "defaultReasoningEffort": "medium",
                "isDefault": true,
            ]], "nextCursor": NSNull()]
        case "permissionProfile/list":
            result = ["data": [
                ["id": ":workspace", "description": "Auto"],
            ], "nextCursor": NSNull()]
        case "collaborationMode/list":
            result = ["data": [
                ["name": "Plan", "mode": "plan", "model": NSNull(), "reasoning_effort": NSNull()],
            ]]
        default:
            result = [:]
        }
        receiveObject(["jsonrpc": "2.0", "id": id, "result": result])
    }

    func close() async {
        continuation?.finish()
    }

    private func receiveObject(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        continuation?.yield(data)
    }

    func capturedParams(for method: String) -> [[String: Any]] {
        lock.withLock { paramsByMethod[method] ?? [] }
    }

    /// 空の RPC 応答とは別に届く、適用された設定の通知。
    func emitAppliedPermissionSettings(_ params: [String: Any]) {
        receiveObject(appliedPermissionSettingsNotification(params))
    }
}

private func appliedPermissionSettingsNotification(_ params: [String: Any]) -> [String: Any] {
    [
        "jsonrpc": "2.0", "method": "thread/settings/updated",
        "params": ["threadId": "thread-1", "threadSettings": [
            "cwd": "/tmp/work", "model": params["model"] ?? "gpt-5-codex", "modelProvider": "openai",
            "effort": params["effort"] ?? "medium", "approvalPolicy": params["approvalPolicy"] ?? "on-request",
            "approvalsReviewer": "user", "sandboxPolicy": ["type": "readOnly"],
            "activePermissionProfile": ["id": params["permissions"] ?? ":read-only", "extends": NSNull()],
            "serviceTier": NSNull(), "collaborationMode": ["mode": "default", "settings": [
                "model": params["model"] ?? "gpt-5-codex", "reasoning_effort": params["effort"] ?? "medium",
                "developer_instructions": NSNull(),
            ]],
        ]],
    ]
}

// MARK: - C3 FIFO

@Test @MainActor
func characterization_transcriptRevert_waitsForInFlightSnapshot() async throws {
    let store = SuspendedFirstSnapshotStore()
    let client = EventYieldingStructuredClient()
    let sessionID = SessionID()
    let vm = ChatSessionViewModel(
        id: sessionID,
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        transcriptStore: store
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("first turn", submit: true)
    client.yield(.agentMessageDelta(itemId: "agent-1", "answer one"))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    try await waitUntil { await store.startedSnapshots.count == 1 }

    let userID = try #require(vm.transcript.compactMap { item -> String? in
        if case .userMessage(let id, _, _, _) = item { id } else { nil }
    }.first)
    let restoredText = await vm.revert(toUserMessageID: userID)
    #expect(restoredText == "first turn")
    #expect(vm.transcript.isEmpty)
    #expect(await store.startedSnapshots.count == 1)
    #expect(await store.completedSnapshots.isEmpty)

    await store.releaseFirstSnapshot()
    await vm.terminate()

    let snapshots = await store.completedSnapshots
    #expect(snapshots.count >= 2)
    #expect(snapshots.first?.contains { $0.id == userID } == true)
    #expect(snapshots.last == [])
    #expect(try await store.loadTranscript(for: sessionID).isEmpty)
    #expect(await store.upsertedBatches.isEmpty)
}

// MARK: - C13 background tasks

@Test @MainActor
func characterization_backgroundTaskUpsert_updatesExistingTaskInPlace() async throws {
    let client = EventYieldingStructuredClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.backgroundTaskStarted(
        taskId: "shared-task",
        taskType: "local_bash",
        description: "initial description",
        toolUseId: "tool-1"
    ))
    try await waitUntil { vm.runningBackgroundTasks.count == 1 }

    client.yield(.backgroundTaskStarted(
        taskId: "shared-task",
        taskType: "local_bash",
        description: "updated description",
        toolUseId: "tool-1"
    ))
    try await waitUntil {
        vm.runningBackgroundTasks.first?.description == "updated description"
    }

    #expect(vm.runningBackgroundTasks.count == 1)
    #expect(vm.runningBackgroundTasks.first?.taskId == "shared-task")
    #expect(vm.runningBackgroundTasks.first?.description == "updated description")
}

@Test @MainActor
func characterization_claudeAndCodexBackgroundTaskEvent_preservesExactTrackedTasks() async throws {
    let claudeClient = EventYieldingStructuredClient()
    let claude = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: claudeClient,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await claude.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    claudeClient.yield(.backgroundTaskStarted(
        taskId: "tracked-task",
        taskType: "local_bash",
        description: "tracked",
        toolUseId: "tool-tracked"
    ))
    try await waitUntil { claude.runningBackgroundTasks.count == 1 }

    let codexClient = EventYieldingStructuredClient()
    let codex = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: codexClient,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await codex.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    codexClient.yield(.backgroundTaskStarted(
        taskId: "ignored-task",
        taskType: "local_bash",
        description: "ignored",
        toolUseId: "tool-ignored"
    ))
    try await waitUntil { codex.rawEventLog.count >= 1 }

    let claudeTask = try #require(claude.runningBackgroundTasks.first)
    #expect(claude.runningBackgroundTasks.count == 1)
    #expect(claudeTask.taskId == "tracked-task")
    #expect(claudeTask.taskType == "local_bash")
    #expect(claudeTask.description == "tracked")
    #expect(claudeTask.toolUseId == "tool-tracked")

    let codexTask = try #require(codex.runningBackgroundTasks.first)
    #expect(codex.runningBackgroundTasks.count == 1)
    #expect(codexTask.taskId == "ignored-task")
    #expect(codexTask.taskType == "local_bash")
    #expect(codexTask.description == "ignored")
    #expect(codexTask.toolUseId == "tool-ignored")
}

// MARK: - C6 reapplyPersistedSettings

@Test @MainActor
func characterization_reapplyPersistedSettings_fallsBackWhenPlanModeUpdateFails() async throws {
    let transport = FailingPlanReapplyTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    await vm.restore(
        threadId: "thread-1",
        approvalPolicy: .named("never"),
        sandbox: .named("workspace-write"),
        persistedSettings: CodexAppServerSessionSettings(
            selectedModel: "o4-mini",
            selectedEffort: "high",
            selectedPermissionProfile: ":read-only",
            isPlanMode: true
        )
    )

    #expect(vm.restoreState == .restored)
    #expect(vm.selectedModel == "o4-mini")
    #expect(vm.selectedEffort == "high")
    #expect(vm.selectedPermissionProfile == ":workspace") // 通知を受けるまでは確認済みの状態。

    let updates = transport.capturedParams(for: "thread/settings/update")
    #expect(updates.count == 2)
    #expect(updates.first?["collaborationMode"] != nil)
    #expect(updates.last?["collaborationMode"] == nil)
    // 失敗後も collaborationMode ローカル変数で isPlanMode が再設定される現挙動を固定する。
    #expect(vm.isPlanMode == true)
    #expect(vm.isPlanModeAvailable == true)
    let applied = try #require(updates.last)
    #expect(applied["approvalPolicy"] as? String == "on-request")
    transport.emitAppliedPermissionSettings(applied)
    let synced = await waitUntil(timeoutNanoseconds: 1_000_000_000) { vm.selectedPermissionProfile == ":read-only" }
    #expect(synced)
    #expect(vm.selectedApprovalPolicy == .named("on-request"))
}

@Test @MainActor
func characterization_reapplyPersistedSettings_skipsPlanModeWhenCollaborationListUnavailable() async throws {
    let transport = ScriptedAppServerTransport()
    transport.collaborationModeData = [
        ["name": "Default", "mode": "default", "model": NSNull(), "reasoning_effort": NSNull()],
    ]
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    await vm.restore(
        threadId: "thread-1",
        approvalPolicy: .named("never"),
        sandbox: .named("workspace-write"),
        persistedSettings: CodexAppServerSessionSettings(
            selectedModel: "o4-mini",
            selectedEffort: "high",
            selectedPermissionProfile: ":read-only",
            isPlanMode: true
        )
    )

    let update = try #require(transport.capturedParams(for: "thread/settings/update").first)
    #expect(update["collaborationMode"] == nil)
    #expect(vm.isPlanMode == false)
    #expect(vm.selectedModel == "o4-mini")
    #expect(vm.selectedEffort == "high")
    #expect(vm.selectedPermissionProfile == ":workspace")
    #expect(update["approvalPolicy"] as? String == "on-request")
    transport.receiveObject(appliedPermissionSettingsNotification(update))
    let synced = await waitUntil(timeoutNanoseconds: 1_000_000_000) { vm.selectedPermissionProfile == ":read-only" }
    #expect(synced)
    #expect(vm.selectedApprovalPolicy == .named("on-request"))
}
