import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import PTYKit
import StructuredChatKit
@testable import DashboardFeature
@testable import SessionFeature

final class ScriptedAppServerTransport: AppServerTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var methods: [String] = []
    private var threadStartParams: [String: Any]?
    private var paramsByMethod: [String: [[String: Any]]] = [:]
    /// thread/start へ順に返す thread id。末尾を超えたら最後の id を繰り返す。
    /// 既定は従来どおり常に "thread-1"（既存テスト互換）。reset の新 thread を検証するテストが
    /// `["thread-1", "thread-2"]` のように上書きして別 id を得る。
    var threadStartIDs: [String] = ["thread-1"]
    private var threadStartIndex = 0
    var readThreadJSON: [String: Any] = [
        "id": "thread-1",
        "status": ["type": "idle"],
        "turns": [],
    ]
    var threadResponseModel: String? = "gpt-5-codex"
    var threadResponseReasoningEffort: String? = "medium"
    var threadResponsePermissionProfile: String? = ":workspace"
    var modelListData: [[String: Any]] = [[
        "id": "gpt-5-codex",
        "model": "gpt-5-codex",
        "displayName": "GPT-5 Codex",
        "description": "Coding model",
        "hidden": false,
        "supportedReasoningEfforts": [
            ["reasoningEffort": "medium", "description": "Balanced"],
            ["reasoningEffort": "high", "description": "Deep"],
        ],
        "defaultReasoningEffort": "medium",
        "isDefault": true,
    ], [
        "id": "o4-mini",
        "model": "o4-mini",
        "displayName": "o4 mini",
        "description": "Small model",
        "hidden": false,
        "supportedReasoningEfforts": [
            ["reasoningEffort": "low", "description": "Fast"],
            ["reasoningEffort": "high", "description": "Deep"],
        ],
        "defaultReasoningEffort": "low",
        "isDefault": false,
    ]]
    var permissionProfileData: [[String: Any]] = [
        ["id": ":read-only", "description": "Read Only"],
        ["id": ":workspace", "description": "Auto"],
        ["id": ":danger-full-access", "description": "Full Access"],
    ]
    var collaborationModeData: [[String: Any]] = [
        ["name": "Plan", "mode": "plan", "model": NSNull(), "reasoning_effort": NSNull()],
        ["name": "Default", "mode": "default", "model": NSNull(), "reasoning_effort": NSNull()],
    ]

    let receivedLines: AsyncStream<Data>

    init() {
        var captured: AsyncStream<Data>.Continuation?
        self.receivedLines = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured
    }

    func send(_ data: Data) async throws {
        let line: Data
        if let newline = data.firstIndex(of: 0x0A) {
            line = Data(data[..<newline])
        } else {
            line = data
        }
        guard let object = try JSONSerialization.jsonObject(with: line) as? [String: Any],
              let method = object["method"] as? String
        else { return }
        lock.withLock {
            methods.append(method)
            if method == "thread/start", let params = object["params"] as? [String: Any] {
                threadStartParams = params
            }
            if let params = object["params"] as? [String: Any] {
                paramsByMethod[method, default: []].append(params)
            }
        }

        guard let id = object["id"] else { return }
        let result: Any
        switch method {
        case "initialize":
            result = [
                "codexHome": "/tmp/codex",
                "platformFamily": "mac",
                "platformOs": "macos",
                "userAgent": "codex-test/1",
            ]
        case "thread/start":
            let tid = lock.withLock { () -> String in
                let id = threadStartIndex < threadStartIDs.count
                    ? threadStartIDs[threadStartIndex]
                    : (threadStartIDs.last ?? "thread-1")
                threadStartIndex += 1
                return id
            }
            result = threadResponse(threadId: tid)
        case "thread/resume":
            result = threadResponse(threadId: "thread-1")
        case "thread/read":
            result = ["thread": readThreadJSON]
        case "model/list":
            result = ["data": modelListData, "nextCursor": NSNull()]
        case "permissionProfile/list":
            result = ["data": permissionProfileData, "nextCursor": NSNull()]
        case "collaborationMode/list":
            result = ["data": collaborationModeData]
        case "thread/settings/update", "turn/start", "turn/interrupt":
            result = [:]
        default:
            result = [:]
        }
        receiveObject(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func threadResponse(threadId: String) -> [String: Any] {
        var response: [String: Any] = [
            "thread": [
                "id": threadId,
                "status": ["type": "idle"],
            ],
            "approvalPolicy": "never",
            "approvalsReviewer": "user",
            "sandbox": ["type": "workspaceWrite"],
        ]
        if let threadResponseModel {
            response["model"] = threadResponseModel
        }
        if let threadResponseReasoningEffort {
            response["reasoningEffort"] = threadResponseReasoningEffort
        }
        if let threadResponsePermissionProfile {
            response["activePermissionProfile"] = ["id": threadResponsePermissionProfile, "extends": NSNull()]
        }
        return response
    }

    func close() async {
        continuation?.finish()
    }

    func receive(_ json: String) {
        continuation?.yield(Data(json.utf8))
    }

    func receiveObject(_ object: [String: Any]) {
        let data = try! JSONSerialization.data(withJSONObject: object)
        continuation?.yield(data)
    }

    func sentMethods() -> [String] {
        lock.withLock { methods }
    }

    func capturedThreadStartParams() -> [String: Any]? {
        lock.withLock { threadStartParams }
    }

    func capturedParams(for method: String) -> [[String: Any]] {
        lock.withLock { paramsByMethod[method] ?? [] }
    }
}

actor RecordingTranscriptStore: TranscriptStore {
    private(set) var itemsBySession: [SessionID: [ChatItem]] = [:]
    private(set) var upsertedBatches: [[ChatItem]] = []
    private(set) var replacedBatches: [[ChatItem]] = []

    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] {
        itemsBySession[sessionID] ?? []
    }

    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        upsertedBatches.append(items)
        var stored = itemsBySession[sessionID] ?? []
        for item in items {
            if let index = stored.firstIndex(where: { $0.id == item.id }) {
                stored[index] = item
            } else {
                stored.append(item)
            }
        }
        itemsBySession[sessionID] = stored
    }

    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {
        replacedBatches.append(items)
        itemsBySession[sessionID] = items
    }
}

func fixedChatItemTimestamp(_ offset: TimeInterval = 0) -> Date {
    Date(timeIntervalSinceReferenceDate: 1_000 + offset)
}

final class FailingResumeStructuredClient: StructuredAgentClient, @unchecked Sendable {
    enum Failure: Error, Equatable {
        case resume
    }

    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws { throw Failure.resume }
    func interrupt() async throws {}
    func close() async {
        continuation.finish()
    }
}

final class EventYieldingStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        continuation.finish()
    }
}

private struct RecordedSpawnSettingsCall: Equatable {
    var model: String?
    var permissionOrMode: String?
    var effort: String?
}

private class RecordingSpawnSettingsClient: StructuredAgentClient, SpawnAgentSettingsControlling, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [RecordedSpawnSettingsCall] = []

    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    var calls: [RecordedSpawnSettingsCall] {
        lock.withLock { recordedCalls }
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        continuation.finish()
    }

    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        lock.withLock {
            recordedCalls.append(RecordedSpawnSettingsCall(
                model: model,
                permissionOrMode: permissionOrMode,
                effort: effort
            ))
        }
    }
}

private final class ProductionLikeSpawnSettingsClient: RecordingSpawnSettingsClient, @unchecked Sendable {}

final class CountingResumeStructuredClient: StructuredAgentClient, @unchecked Sendable {
    private let lock = NSLock()
    private var startCount = 0
    private var resumeRefs: [String] = []

    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    var starts: Int {
        lock.withLock { startCount }
    }

    var resumes: [String] {
        lock.withLock { resumeRefs }
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    func start() async {
        lock.withLock {
            startCount += 1
        }
    }

    func turnStart(_ input: [ChatInput]) async throws {}

    func resume(sessionRef: String) async throws {
        lock.withLock {
            resumeRefs.append(sessionRef)
        }
    }

    func interrupt() async throws {}

    func close() async {
        continuation.finish()
    }
}

private struct InterruptFailure: Error {}

private final class ThrowingInterruptStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var turnTexts: [String] = []

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { continuation in
            captured = continuation
        }
        self.continuation = captured!
    }

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        let text = input.compactMap { item in
            if case .text(let value) = item { value } else { nil }
        }.joined()
        lock.withLock { turnTexts.append(text) }
    }

    func resume(sessionRef: String) async throws {}

    func interrupt() async throws {
        throw InterruptFailure()
    }

    func close() async {
        continuation.finish()
    }

    func recordedTurnTexts() -> [String] {
        lock.withLock { turnTexts }
    }
}

/// turnStart 入力（プリアンブル観測用）と resetConversation 回数を記録し、イベントも yield できる
/// クライアント。任意で「次の turnStart を 1 回だけ throw」させ、送信失敗後の再送を再現できる。
final class RevertWhiteboxClient: StructuredAgentClient, @unchecked Sendable {
    struct SendFailure: Error {}

    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var turnTexts: [String] = []
    private var resetCount = 0
    private var throwNextTurnStart = false

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        let shouldThrow = lock.withLock { () -> Bool in
            if throwNextTurnStart {
                throwNextTurnStart = false
                return true
            }
            return false
        }
        if shouldThrow { throw SendFailure() }
        let text = input.compactMap { item in
            if case .text(let value) = item { value } else { nil }
        }.joined()
        lock.withLock { turnTexts.append(text) }
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func resetConversation() async { lock.withLock { resetCount += 1 } }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
    func armThrowNextTurnStart() { lock.withLock { throwNextTurnStart = true } }
    func recordedTurnTexts() -> [String] { lock.withLock { turnTexts } }
    func resetConversationCalls() -> Int { lock.withLock { resetCount } }
}

@MainActor
private func revertWhiteboxVM(
    client: RevertWhiteboxClient,
    store: RecordingTranscriptStore
) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        transcriptStore: store
    )
}

@MainActor
private func revertWhiteboxCompleteTurn(
    _ vm: ChatSessionViewModel,
    client: RevertWhiteboxClient,
    userText: String,
    agentItemID: String,
    agentReply: String
) async throws {
    try await vm.sendText(userText, submit: true)
    client.yield(.agentMessageDelta(itemId: agentItemID, agentReply))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
}

// task-8 ハザード(3): 送信失敗後の再送で文脈リプレイが二重付与も消失もしない（単一適用）。
@Test @MainActor
func revert_replayPreambleSurvivesFailedSendAndAppliesExactlyOnce() async throws {
    let client = RevertWhiteboxClient()
    let store = RecordingTranscriptStore()
    let vm = revertWhiteboxVM(client: client, store: store)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    try await revertWhiteboxCompleteTurn(vm, client: client, userText: "最初の依頼", agentItemID: "a1", agentReply: "応答1")
    try await revertWhiteboxCompleteTurn(vm, client: client, userText: "二番目の依頼", agentItemID: "a2", agentReply: "応答2")

    let userIDs = vm.transcript.compactMap { item -> String? in
        if case .userMessage(let id, _, _, _) = item { id } else { nil }
    }
    _ = await vm.revert(toUserMessageID: userIDs[1])

    // 送信は失敗する（reservation は残るはず）。
    client.armThrowNextTurnStart()
    await #expect(throws: RevertWhiteboxClient.SendFailure.self) {
        try await vm.sendText("編集後の依頼", submit: true)
    }
    // 失敗した送信はプリアンブル付き入力を記録していない（throw が記録より前）。
    #expect(!client.recordedTurnTexts().contains { $0.contains("---") })

    // 再送は成功し、プリアンブルがちょうど 1 回だけ適用される。
    try await vm.sendText("編集後の依頼-再送", submit: true)
    let successTurn = try #require(client.recordedTurnTexts().last)
    #expect(successTurn.contains("最初の依頼"))
    #expect(successTurn.contains("編集後の依頼-再送"))

    // さらに次の送信では素の入力のみ（reservation は使い切って解除済み）。
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    try await vm.sendText("その次", submit: true)

    // セパレータ "---" を含む送信は全体でちょうど 1 回だけ（二重付与も再付与もない）。
    #expect(client.recordedTurnTexts().filter { $0.contains("\n\n---\n\n") }.count == 1)
    #expect(client.recordedTurnTexts().last == "その次")
}

// task-8: 文脈リプレイは上限 12,000 文字で「古い側から」切り捨てる（直近を残す）。
@Test @MainActor
func revert_replayContextTruncatesFromOldSideAt12kChars() async throws {
    let client = RevertWhiteboxClient()
    let store = RecordingTranscriptStore()
    let vm = revertWhiteboxVM(client: client, store: store)
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    let bigOld = "ZOLDESTZ" + String(repeating: "o", count: 8_000)
    let bigRecent = "ZRECENTZ" + String(repeating: "r", count: 8_000)
    try await revertWhiteboxCompleteTurn(vm, client: client, userText: "first", agentItemID: "a1", agentReply: bigOld)
    try await revertWhiteboxCompleteTurn(vm, client: client, userText: "second", agentItemID: "a2", agentReply: bigRecent)
    try await revertWhiteboxCompleteTurn(vm, client: client, userText: "third", agentItemID: "a3", agentReply: "応答3")

    let userIDs = vm.transcript.compactMap { item -> String? in
        if case .userMessage(let id, _, _, _) = item { id } else { nil }
    }
    // "third"（3番目のユーザーメッセージ）の直前まで巻き戻す → 保持分は old/recent の 2 ターン。
    _ = await vm.revert(toUserMessageID: userIDs[2])

    try await vm.sendText("edited", submit: true)
    let turnText = try #require(client.recordedTurnTexts().last)

    // 直近（recent）は残り、最古（oldest）は古い側から切り捨てられる。
    #expect(turnText.contains("ZRECENTZ"))
    #expect(!turnText.contains("ZOLDESTZ"))
    #expect(turnText.contains("edited"))
    // プリアンブルは上限 12,000 文字ちょうど（+ セパレータ + 新規入力）。
    let separator = "\n\n---\n\n"
    #expect(turnText.count == 12_000 + separator.count + "edited".count)
}

// task-8 差し戻し MUST2 回帰: reset 後、旧 threadId の delta / turn-completed を inject しても
// transcript が復活せず、chatNativeSessionId が旧 thread へ逆行しない（新 thread のイベントは生きる）。
@Test @MainActor
func revert_codexIgnoresStaleOldThreadEventsAfterReset() async throws {
    let store = RecordingTranscriptStore()
    let transport = ScriptedAppServerTransport()
    // startNew → thread-1、reset（revert 内）→ thread-2 と別 id を返させる。
    transport.threadStartIDs = ["thread-1", "thread-2"]
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let sessionID = SessionID()
    let vm = ChatSessionViewModel(
        id: sessionID,
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work",
        transcriptStore: store
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    #expect(vm.chatNativeSessionId == "thread-1")

    // 1ターン目（thread-1）。
    try await vm.sendText("最初", submit: true)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"old-reply"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)
    try await waitUntil {
        vm.status == .idle && vm.transcript.contains { item in
            if case .agentMessage("agent-1", "old-reply", _) = item { true } else { false }
        }
    }

    // 2ターン目（thread-1）。
    try await vm.sendText("二番目", submit: true)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-2","itemId":"agent-2","delta":"reply2"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-2","status":"completed"}}}
    """)
    try await waitUntil { vm.status == .idle && vm.transcript.contains { item in
        if case .agentMessage("agent-2", "reply2", _) = item { true } else { false }
    } }

    let userIDs = vm.transcript.compactMap { item -> String? in
        if case .userMessage(let id, _, _, _) = item { id } else { nil }
    }
    // "二番目" の直前まで巻き戻す → retained = [user"最初", agent-1"old-reply"]。
    let restored = await vm.revert(toUserMessageID: try #require(userIDs.last))
    #expect(restored == "二番目")
    // reset で新 thread-2 を採用（旧 thread-1 から更新）。
    #expect(vm.chatNativeSessionId == "thread-2")
    let countAfterRevert = vm.transcript.count

    // 旧 thread-1 の遅延イベントを inject（本来なら transcript 復活・native id 逆行を招く）。
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-3","itemId":"agent-zombie","delta":"ZOMBIE"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-3","item":{"id":"agent-zombie2","type":"agent_message","text":"ZOMBIE-ITEM"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-3","status":"completed"}}}
    """)

    // 新 thread-2 の LIVE イベントをセンチネルとして inject。これが transcript に現れた時点で、
    // 先行の旧 thread-1 イベントは（FIFO で）処理済み＝遮断済みと確定できる。
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-2","turnId":"turn-4","itemId":"agent-live","delta":"LIVE"}}
    """)
    try await waitUntil {
        vm.transcript.contains { item in
            if case .agentMessage("agent-live", "LIVE", _) = item { true } else { false }
        }
    }

    // 旧 thread の delta / item は transcript へ復活していない。
    let joined = vm.transcript.map(\.plainText).joined()
    #expect(!joined.contains("ZOMBIE"))
    // 新 thread の LIVE のみが増分（旧 thread の 2 event は遮断）。
    #expect(vm.transcript.count == countAfterRevert + 1)
    // 旧 thread の turn/completed で chatNativeSessionId が thread-1 へ逆行していない。
    #expect(vm.chatNativeSessionId == "thread-2")

    // store も旧 thread item を復活させていない。
    let stored = try await store.loadTranscript(for: sessionID)
    #expect(!stored.map(\.plainText).joined().contains("ZOMBIE"))
}

@Test @MainActor
func transcriptStore_roundTripsAllChatItemCases() async throws {
    let root = FileManager.default.temporaryDirectory
        .appending(path: "phlox-transcript-store-\(UUID().uuidString)", directoryHint: .isDirectory)
    let store = FileTranscriptStore(directoryURL: root)
    let sessionID = SessionID()
    let items: [ChatItem] = [
        .userMessage(id: "user-1", text: "hello", timestamp: fixedChatItemTimestamp(1)),
        .agentMessage(id: "agent-1", text: "hi", timestamp: fixedChatItemTimestamp(2)),
        .reasoning(id: "reason-1", text: "thinking", timestamp: fixedChatItemTimestamp(3)),
        .commandExecution(id: "cmd-1", command: "pwd", output: "/tmp", timestamp: fixedChatItemTimestamp(4)),
        .commandExecution(id: "cmd-2", command: nil, output: "streamed output", timestamp: fixedChatItemTimestamp(5)),
        .fileChange(id: "file-1", changes: [
            FilePatchChange(path: "Sources/App.swift", diff: "@@\n+hello", kind: "edit"),
        ], timestamp: fixedChatItemTimestamp(6)),
        .error(id: "error-1", message: "boom", timestamp: fixedChatItemTimestamp(7)),
    ]

    try await store.upsertTranscriptItems(items, for: sessionID)

    let loaded = try await store.loadTranscript(for: sessionID)
    #expect(loaded == items)
    // 永続化(A)の受け入れ基準: timestamp が FileTranscriptStore 経由の往復で全ケース保持される
    // （Equatable は timestamp を除外するため loaded == items だけでは劣化を捕捉できない）
    #expect(loaded.map(\.timestamp) == items.map(\.timestamp))
}

@Test
func chatItem_decodesLegacyNestedJSONWithDistantPastTimestamp() throws {
    let json = #"[{"userMessage":{"id":"u1","text":"a"}},{"agentMessage":{"id":"a1","text":"b"}}]"#
    let decoded = try JSONDecoder().decode([ChatItem].self, from: Data(json.utf8))

    #expect(decoded == [
        .userMessage(id: "u1", text: "a", timestamp: fixedChatItemTimestamp()),
        .agentMessage(id: "a1", text: "b", timestamp: fixedChatItemTimestamp()),
    ])
    #expect(decoded.map(\.timestamp) == [.distantPast, .distantPast])
}

@Test
func chatItem_encodesNestedJSONAndRoundTripsTimestamp() throws {
    let items: [ChatItem] = [
        .userMessage(id: "u1", text: "a", timestamp: fixedChatItemTimestamp(10)),
        .commandExecution(id: "c1", command: nil, output: "out", timestamp: fixedChatItemTimestamp(11)),
    ]

    let data = try JSONEncoder().encode(items)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    #expect(object.count == 2)
    let userMessage = try #require(object[0]["userMessage"] as? [String: Any])
    let commandExecution = try #require(object[1]["commandExecution"] as? [String: Any])
    #expect(userMessage["id"] as? String == "u1")
    #expect(userMessage["text"] as? String == "a")
    #expect(userMessage["timestamp"] != nil)
    #expect(commandExecution["id"] as? String == "c1")
    #expect(commandExecution["output"] as? String == "out")
    #expect(commandExecution["timestamp"] != nil)

    let decoded = try JSONDecoder().decode([ChatItem].self, from: data)
    #expect(decoded == items)
    #expect(decoded.map(\.timestamp) == items.map(\.timestamp))
}

@Test @MainActor
func chatSessionViewModel_setsTimestampForNewItemsAndPreservesItAcrossDelta() async throws {
    let client = EventYieldingStructuredClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("hi", submit: true)

    let userItem = try #require(vm.transcript.first { $0.id.hasPrefix("user-") })
    #expect(userItem.timestamp != .distantPast)

    client.yield(.agentMessageDelta(itemId: "agent-1", "hel"))
    try await waitUntil {
        vm.transcript.contains { item in
            if case .agentMessage("agent-1", "hel", _) = item {
                return true
            }
            return false
        }
    }
    let initialAgentTimestamp = try #require(vm.transcript.first { $0.id == "agent-1" }).timestamp
    #expect(initialAgentTimestamp != .distantPast)

    client.yield(.agentMessageDelta(itemId: "agent-1", "lo"))
    try await waitUntil {
        vm.transcript.contains { item in
            if case .agentMessage("agent-1", "hello", _) = item {
                return true
            }
            return false
        }
    }
    let updatedAgentTimestamp = try #require(vm.transcript.first { $0.id == "agent-1" }).timestamp
    #expect(updatedAgentTimestamp == initialAgentTimestamp)
}

@Test @MainActor
func chatSessionViewModel_upsertsTranscriptAtTurnBoundaryByItemId() async throws {
    let store = RecordingTranscriptStore()
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let sessionID = SessionID()
    let vm = ChatSessionViewModel(
        id: sessionID,
        agentRef: .builtin(.claudeCode),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work",
        transcriptStore: store
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"hello"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":" world"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    try await waitUntil {
        await (try? store.loadTranscript(for: sessionID)) == [
            .agentMessage(id: "agent-1", text: "hello world", timestamp: fixedChatItemTimestamp())
        ]
    }
    let batches = await store.upsertedBatches
    #expect(batches.last == [.agentMessage(id: "agent-1", text: "hello world", timestamp: fixedChatItemTimestamp())])
}

@Test @MainActor
func chatSessionViewModel_claudeClientTurnCompletionUpsertsFullTranscript() async throws {
    let store = RecordingTranscriptStore()
    let client = EventYieldingStructuredClient()
    #expect(!(client is any CodexSettingsProviding))
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
    client.yield(.agentMessageDelta(itemId: "agent-1", "hello"))
    client.yield(.reasoningDelta(itemId: "reason-1", "thinking"))
    client.yield(.turnCompleted(nativeSessionId: "claude-native-1"))

    let expected: [ChatItem] = [
        .agentMessage(id: "agent-1", text: "hello", timestamp: fixedChatItemTimestamp()),
        .reasoning(id: "reason-1", text: "thinking", timestamp: fixedChatItemTimestamp()),
    ]
    try await waitUntil {
        await (try? store.loadTranscript(for: sessionID)) == expected
    }
    let batches = await store.upsertedBatches
    #expect(batches.last == expected)
    #expect(vm.chatNativeSessionId == "claude-native-1")
}

@Test @MainActor
func chatSessionViewModel_claudeClientErrorFlushesPartialTranscript() async throws {
    let store = RecordingTranscriptStore()
    let client = EventYieldingStructuredClient()
    #expect(!(client is any CodexSettingsProviding))
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
    client.yield(.agentMessageDelta(itemId: "agent-before-error", "partial answer"))
    client.yield(.error(message: "tool crashed"))

    try await waitUntil {
        guard let stored = await (try? store.loadTranscript(for: sessionID)) else { return false }
        return stored.contains(.agentMessage(id: "agent-before-error", text: "partial answer", timestamp: fixedChatItemTimestamp()))
            && stored.contains { item in
                if case .error(_, "tool crashed", _) = item {
                    return true
                }
                return false
            }
    }
    let stored = try await store.loadTranscript(for: sessionID)
    #expect(stored.contains(.agentMessage(id: "agent-before-error", text: "partial answer", timestamp: fixedChatItemTimestamp())))
    #expect(stored.contains { item in
        if case .error(_, "tool crashed", _) = item {
            return true
        }
        return false
    })
    #expect(stored == vm.transcript)
}

@Test @MainActor
func chatSessionViewModel_claudeClientTurnInterruptedFlushesPartialTranscript() async throws {
    let store = RecordingTranscriptStore()
    let client = EventYieldingStructuredClient()
    #expect(!(client is any CodexSettingsProviding))
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
    client.yield(.agentMessageDelta(itemId: "agent-before-interrupt", "interrupted answer"))
    client.yield(.turnInterrupted(nativeSessionId: "claude-native-interrupted"))

    let expected: [ChatItem] = [
        .agentMessage(id: "agent-before-interrupt", text: "interrupted answer", timestamp: fixedChatItemTimestamp()),
    ]
    try await waitUntil {
        await (try? store.loadTranscript(for: sessionID)) == expected
    }
    let batches = await store.upsertedBatches
    #expect(batches.last == expected)
    #expect(vm.chatNativeSessionId == "claude-native-interrupted")
}

@Test @MainActor
func chatSessionViewModel_backgroundTaskStartedAndCompletedMaintainsRunningList() async throws {
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
        taskId: "task-1",
        taskType: "local_bash",
        description: "swift test --package-path Packages/DashboardFeature",
        toolUseId: "toolu-1"
    ))

    try await waitUntil { vm.runningBackgroundTasks.count == 1 }
    let task = try #require(vm.runningBackgroundTasks.first)
    #expect(task.taskId == "task-1")
    #expect(task.taskType == "local_bash")
    #expect(task.description == "swift test --package-path Packages/DashboardFeature")
    #expect(task.toolUseId == "toolu-1")
    #expect(task.startedAt != .distantPast)

    client.yield(.backgroundTaskCompleted(taskId: "task-1", status: "completed", summary: "done"))

    try await waitUntil { vm.runningBackgroundTasks.isEmpty }
}

@Test @MainActor
func chatSessionViewModel_backgroundTasksClearOnNativeSessionGenerationChange() async throws {
    let client = EventYieldingStructuredClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.turnCompleted(nativeSessionId: "claude-native-1"))
    try await waitUntil { vm.chatNativeSessionId == "claude-native-1" }

    client.yield(.backgroundTaskStarted(
        taskId: "orphan-task",
        taskType: "local_agent",
        description: "Investigate failing tests",
        toolUseId: "toolu-agent"
    ))
    try await waitUntil { vm.runningBackgroundTasks.count == 1 }

    client.yield(.turnCompleted(nativeSessionId: "claude-native-2"))

    try await waitUntil {
        vm.chatNativeSessionId == "claude-native-2" && vm.runningBackgroundTasks.isEmpty
    }
}

@Test @MainActor
func chatSessionViewModel_terminateClearsRunningBackgroundTasks() async throws {
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
        taskId: "terminate-task",
        taskType: "local_bash",
        description: "sleep 60",
        toolUseId: "toolu-terminate"
    ))
    try await waitUntil { vm.runningBackgroundTasks.count == 1 }

    await vm.terminate()

    #expect(vm.runningBackgroundTasks.isEmpty)
}

@Test @MainActor
func chatSessionViewModel_spawnSettingsChangeClearsBackgroundTasksOnNextTurnStarted() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.backgroundTaskStarted(
        taskId: "respawn-orphan",
        taskType: "local_agent",
        description: "Review previous turn",
        toolUseId: "toolu-respawn"
    ))
    try await waitUntil { vm.runningBackgroundTasks.count == 1 }

    await vm.setSpawnAgentEffort("xhigh")
    client.yield(.turnStarted)

    try await waitUntil { vm.runningBackgroundTasks.isEmpty }
}

@Test @MainActor
func chatSessionViewModel_turnStartedWithoutSpawnSettingsChangeKeepsBackgroundTasks() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.backgroundTaskStarted(
        taskId: "ongoing-task",
        taskType: "local_bash",
        description: "tail -f build.log",
        toolUseId: "toolu-ongoing"
    ))
    try await waitUntil { vm.runningBackgroundTasks.count == 1 }

    client.yield(.turnStarted)

    try await waitUntil { vm.status == .running }
    #expect(vm.runningBackgroundTasks.map(\.taskId) == ["ongoing-task"])
}

@Test @MainActor
func chatSessionViewModel_backgroundTasksStayEmptyForCursorAndCodexSessions() async throws {
    let cursorClient = EventYieldingStructuredClient()
    let cursor = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: cursorClient,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await cursor.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    cursorClient.yield(.backgroundTaskStarted(
        taskId: "cursor-task",
        taskType: "local_bash",
        description: "ignored",
        toolUseId: "cursor-tool"
    ))
    try await waitUntil { cursor.rawEventLog.count >= 1 }
    #expect(cursor.runningBackgroundTasks.isEmpty)

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
        taskId: "codex-task",
        taskType: "local_agent",
        description: "ignored",
        toolUseId: "codex-tool"
    ))
    try await waitUntil { codex.rawEventLog.count >= 1 }
    #expect(codex.runningBackgroundTasks.isEmpty)
}

@Test @MainActor
func chatSessionViewModel_claudeRestoreLoadsTranscriptEvenWhenResumeFails() async throws {
    let store = RecordingTranscriptStore()
    let sessionID = SessionID()
    let persisted: [ChatItem] = [
        .userMessage(id: "user-1", text: "hi", timestamp: fixedChatItemTimestamp()),
        .agentMessage(id: "agent-1", text: "hello", timestamp: fixedChatItemTimestamp()),
    ]
    try await store.upsertTranscriptItems(persisted, for: sessionID)
    let vm = ChatSessionViewModel(
        id: sessionID,
        agentRef: .builtin(.claudeCode),
        client: FailingResumeStructuredClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        transcriptStore: store
    )

    await vm.restore(
        threadId: "claude-session-1",
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )

    #expect(vm.transcript == persisted)
    #expect(vm.restoreState == .failed(message: "resume"))
}

@Test @MainActor
func chatSessionViewModel_claudeRestoreResumesWithoutThrowawayStart() async throws {
    let client = CountingResumeStructuredClient()
    #expect(!(client is any CodexSettingsProviding))
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        transcriptStore: RecordingTranscriptStore()
    )

    await vm.restore(
        threadId: "44444444-4444-4444-8444-444444444444",
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )

    #expect(client.starts == 0)
    #expect(client.resumes == ["44444444-4444-4444-8444-444444444444"])
    #expect(vm.chatNativeSessionId == "44444444-4444-4444-8444-444444444444")
    #expect(vm.restoreState == .restored)
}

// task-10 成功基準1: Claude セッションは固定 alias {opus,sonnet,fable} を availableSpawnAgentModels に公開する。
@Test @MainActor
func chatSessionViewModel_claudeExposesFixedModelAliases() async throws {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: EventYieldingStructuredClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(vm.availableSpawnAgentModels == ["opus", "sonnet", "fable", "haiku"])
}

// task-10 成功基準2: Cursor は注入された provider（cursor-agent models 相当）の結果を公開する。
@Test @MainActor
func chatSessionViewModel_cursorLoadsModelsFromProvider() async throws {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: EventYieldingStructuredClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        spawnAgentModelsProvider: { ["gpt-5.2", "sonnet-4.5"] }
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(vm.availableSpawnAgentModels == ["gpt-5.2", "sonnet-4.5"])
}

// task-10 成功基準2: provider が空/未注入でもハードコード fallback で非空を保証（起動を妨げない）。
@Test @MainActor
func chatSessionViewModel_cursorFallsBackToHardcodedModelsWhenProviderEmpty() async throws {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: EventYieldingStructuredClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        spawnAgentModelsProvider: { [] }
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(!vm.availableSpawnAgentModels.isEmpty)
    #expect(vm.availableSpawnAgentModels == ChatSessionViewModel.cursorFallbackModels)
}

@Test @MainActor
func chatSessionViewModel_spawnAgentDefaultsPresetModelPermissionAndPlanAvailability() async throws {
    let claudeClient = RecordingSpawnSettingsClient()
    let claude = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: claudeClient,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await claude.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(claude.selectedModel == "opus")
    #expect(claude.selectedPermissionProfile == "bypassPermissions")
    #expect(claude.isPlanMode == false)
    #expect(claude.isPlanModeAvailable)
    #expect(claudeClient.calls == [
        RecordedSpawnSettingsCall(model: "opus", permissionOrMode: "bypassPermissions", effort: "high"),
    ])

    let cursorClient = RecordingSpawnSettingsClient()
    let cursor = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: cursorClient,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        spawnAgentModelsProvider: { ["gpt-5.2", "composer-2.5"] }
    )

    try await cursor.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(cursor.selectedModel == "composer-2.5")
    #expect(cursor.selectedPermissionProfile == nil)
    #expect(cursor.isPlanMode == false)
    #expect(cursor.isPlanModeAvailable)
    #expect(cursorClient.calls == [
        RecordedSpawnSettingsCall(model: "composer-2.5", permissionOrMode: nil, effort: nil),
    ])
}

@Test @MainActor
func chatSessionViewModel_spawnAgentNewBehaviorDoesNotDependOnTestClientTypeName() async throws {
    let client = ProductionLikeSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(vm.selectedModel == "opus")
    #expect(vm.selectedPermissionProfile == "bypassPermissions")
    #expect(vm.isPlanMode == false)
    #expect(vm.isPlanModeAvailable)
    #expect(client.calls == [
        RecordedSpawnSettingsCall(model: "opus", permissionOrMode: "bypassPermissions", effort: "high"),
    ])

    await vm.setSpawnAgentPermission("plan")

    #expect(vm.isPlanMode)
    #expect(vm.selectedPermissionProfile == "bypassPermissions")
    #expect(client.calls.last == RecordedSpawnSettingsCall(model: "opus", permissionOrMode: "plan", effort: "high"))

    await vm.setSpawnAgentPermission("acceptEdits")

    #expect(!vm.isPlanMode)
    #expect(vm.selectedPermissionProfile == "acceptEdits")
    #expect(client.calls.last == RecordedSpawnSettingsCall(model: "opus", permissionOrMode: "acceptEdits", effort: "high"))
}

@Test @MainActor
func chatSessionViewModel_spawnAgentPersistedSettingsOverrideDefaults() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    await vm.restore(
        threadId: "claude-session-1",
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write"),
        persistedSettings: CodexAppServerSessionSettings(
            selectedModel: "sonnet",
            selectedEffort: nil,
            selectedPermissionProfile: "acceptEdits",
            isPlanMode: nil
        )
    )

    #expect(vm.selectedModel == "sonnet")
    #expect(vm.selectedPermissionProfile == "acceptEdits")
    #expect(client.calls == [
        RecordedSpawnSettingsCall(model: "sonnet", permissionOrMode: "acceptEdits", effort: "high"),
    ])
}

@Test @MainActor
func chatSessionViewModel_spawnAgentMigratesPersistedPlanOutOfPermissionProfile() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    await vm.restore(
        threadId: "claude-session-1",
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write"),
        persistedSettings: CodexAppServerSessionSettings(
            selectedModel: "opus",
            selectedEffort: nil,
            selectedPermissionProfile: "plan",
            isPlanMode: nil
        )
    )

    #expect(vm.selectedModel == "opus")
    #expect(vm.selectedPermissionProfile == "bypassPermissions")
    #expect(vm.isPlanMode)
    #expect(client.calls == [
        RecordedSpawnSettingsCall(model: "opus", permissionOrMode: "plan", effort: "high"),
    ])
}

@Test @MainActor
func chatSessionViewModel_spawnPlanModeAppliesEffectiveModeWithoutOverwritingPermission() async throws {
    let claudeClient = RecordingSpawnSettingsClient()
    let claude = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: claudeClient,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await claude.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await claude.setPlanMode(true)
    #expect(claude.isPlanMode)
    #expect(claude.selectedPermissionProfile == "bypassPermissions")
    #expect(claudeClient.calls.last == RecordedSpawnSettingsCall(model: "opus", permissionOrMode: "plan", effort: "high"))

    try await claude.setPlanMode(false)
    #expect(!claude.isPlanMode)
    #expect(claude.selectedPermissionProfile == "bypassPermissions")
    #expect(claudeClient.calls.last == RecordedSpawnSettingsCall(model: "opus", permissionOrMode: "bypassPermissions", effort: "high"))

    let cursorClient = RecordingSpawnSettingsClient()
    let cursor = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: cursorClient,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        spawnAgentModelsProvider: { ["composer-2.5", "gpt-5.2"] }
    )

    try await cursor.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await cursor.setPlanMode(true)
    #expect(cursor.isPlanMode)
    #expect(cursor.selectedPermissionProfile == nil)
    #expect(cursorClient.calls.last == RecordedSpawnSettingsCall(model: "composer-2.5", permissionOrMode: "plan", effort: nil))

    try await cursor.setPlanMode(false)
    #expect(!cursor.isPlanMode)
    #expect(cursor.selectedPermissionProfile == nil)
    #expect(cursorClient.calls.last == RecordedSpawnSettingsCall(model: "composer-2.5", permissionOrMode: nil, effort: nil))
}

@Test @MainActor
func chatSessionViewModel_spawnAgentClaudeExposesEffortLevelsAndSelectionReachesActor() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(vm.claudeEffortLevels == ChatSessionViewModel.claudeEffortLevelOptions)
    #expect(vm.selectedEffort == "high")

    await vm.setSpawnAgentEffort("xhigh")

    #expect(vm.selectedEffort == "xhigh")
    #expect(client.calls.last == RecordedSpawnSettingsCall(
        model: "opus",
        permissionOrMode: "bypassPermissions",
        effort: "xhigh"
    ))
}

@Test
func chatSessionViewModel_claudeModelSupportsEffortCapability() {
    #expect(ChatSessionViewModel.claudeModelSupportsEffort("opus") == true)
    #expect(ChatSessionViewModel.claudeModelSupportsEffort("sonnet") == true)
    #expect(ChatSessionViewModel.claudeModelSupportsEffort("fable") == true)
    #expect(ChatSessionViewModel.claudeModelSupportsEffort("haiku") == false)
    #expect(ChatSessionViewModel.claudeModelSupportsEffort(nil) == false)
}

@Test @MainActor
func chatSessionViewModel_haikuHidesEffortLevelsAndDoesNotSendEffort() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    await vm.setSpawnAgentModel("haiku")

    #expect(vm.claudeEffortLevels.isEmpty)
    #expect(client.calls.last?.effort == nil)
}

@Test @MainActor
func chatSessionViewModel_sonnetKeepsEffortLevels() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    await vm.setSpawnAgentModel("sonnet")

    #expect(vm.claudeEffortLevels == ChatSessionViewModel.claudeEffortLevelOptions)
    #expect(!vm.claudeEffortLevels.isEmpty)
}

@Test @MainActor
func chatSessionViewModel_opusToHaikuClearsEffort() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    #expect(vm.selectedEffort == "high")

    await vm.setSpawnAgentModel("haiku")

    #expect(vm.selectedEffort == nil)
    #expect(client.calls.last?.effort == nil)
}

@Test @MainActor
func chatSessionViewModel_haikuToOpusRestoresDefaultEffort() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    await vm.setSpawnAgentModel("haiku")
    #expect(vm.selectedEffort == nil)

    await vm.setSpawnAgentModel("opus")

    #expect(vm.selectedEffort == ChatSessionViewModel.defaultClaudeEffort)
    #expect(client.calls.last?.effort == ChatSessionViewModel.defaultClaudeEffort)
}

@Test @MainActor
func chatSessionViewModel_spawnAgentCursorHasEmptyEffortLevels() async throws {
    let client = RecordingSpawnSettingsClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        spawnAgentModelsProvider: { ["composer-2.5"] }
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(vm.claudeEffortLevels.isEmpty)
    #expect(vm.selectedEffort == nil)
}

@Test @MainActor
func chatSessionViewModel_codexDefaultsToFullAccessWhenNoPersistedOrServerProfile() async throws {
    let transport = ScriptedAppServerTransport()
    transport.threadResponsePermissionProfile = nil
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(vm.permissionProfiles.contains { $0.id == ":danger-full-access" })
    #expect(vm.selectedPermissionProfile == ":danger-full-access")
}

@Test @MainActor
func chatSessionViewModel_startNewLoadsSettingsState() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    #expect(vm.availableModels.map(\.id) == ["gpt-5-codex", "o4-mini"])
    #expect(vm.permissionProfiles.map(\.id) == [":read-only", ":workspace", ":danger-full-access"])
    #expect(vm.selectedModel == "gpt-5-codex")
    #expect(vm.selectedEffort == "medium")
    #expect(vm.selectedPermissionProfile == ":workspace")
    #expect(vm.isPlanMode == false)
    #expect(vm.isPlanModeAvailable)
}

@Test @MainActor
func chatSessionViewModel_settingChangesUseThreadSettingsUpdate() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.setPlanMode(true)
    try await vm.setModel(model: "o4-mini", effort: "high")
    try await vm.setPermissionProfile(id: ":danger-full-access")

    let updates = transport.capturedParams(for: "thread/settings/update")
    #expect(updates.count == 3)
    let planUpdate = try #require(updates.first)
    #expect(planUpdate["threadId"] as? String == "thread-1")
    let planMode = try #require(planUpdate["collaborationMode"] as? [String: Any])
    #expect(planMode["mode"] as? String == "plan")
    let planSettings = try #require(planMode["settings"] as? [String: Any])
    #expect(planSettings["model"] as? String == "gpt-5-codex")
    #expect(planSettings["reasoning_effort"] as? String == "medium")

    let modelUpdate = try #require(updates.dropFirst().first)
    #expect(modelUpdate["model"] as? String == "o4-mini")
    #expect(modelUpdate["effort"] as? String == "high")
    let modelUpdateMode = try #require(modelUpdate["collaborationMode"] as? [String: Any])
    let modelUpdateSettings = try #require(modelUpdateMode["settings"] as? [String: Any])
    #expect(modelUpdateSettings["model"] as? String == "o4-mini")
    #expect(modelUpdateSettings["reasoning_effort"] as? String == "high")

    let permissionUpdate = try #require(updates.last)
    #expect(permissionUpdate["permissions"] as? String == ":danger-full-access")
    #expect(permissionUpdate["sandboxPolicy"] == nil)
}

@Test @MainActor
func chatSessionViewModel_threadSettingsUpdatedSynchronizesStateAndPersistenceCallback() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )
    var persisted: CodexAppServerSessionSettings?
    vm.codexSettingsDidChange = { settings in
        persisted = settings
    }

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"thread/settings/updated","params":{"threadId":"thread-1","threadSettings":{"cwd":"/tmp/work","model":"gpt-5-codex","modelProvider":"openai","effort":"medium","approvalPolicy":"never","approvalsReviewer":"user","sandboxPolicy":{"type":"workspaceWrite"},"activePermissionProfile":{"id":":read-only","extends":null},"serviceTier":null,"collaborationMode":{"mode":"plan","settings":{"model":"o4-mini","reasoning_effort":"high","developer_instructions":null}}}}}
    """)

    let synced = await waitUntil(timeoutNanoseconds: 1_000_000_000) {
        vm.selectedModel == "o4-mini" && vm.selectedPermissionProfile == ":read-only"
    }
    #expect(synced)
    #expect(vm.isPlanMode)
    #expect(vm.selectedEffort == "high")
    #expect(persisted?.selectedModel == "o4-mini")
    #expect(persisted?.selectedEffort == "high")
    #expect(persisted?.selectedPermissionProfile == ":read-only")
    #expect(persisted?.isPlanMode == true)
}

@Test @MainActor
func chatSessionViewModel_restoreReappliesPersistedSettingsAfterResume() async throws {
    let transport = ScriptedAppServerTransport()
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
    let methods = transport.sentMethods()
    #expect(methods.firstIndex(of: "thread/resume")! < methods.firstIndex(of: "thread/settings/update")!)
    #expect(methods.firstIndex(of: "thread/settings/update")! < methods.firstIndex(of: "thread/read")!)
    let update = try #require(transport.capturedParams(for: "thread/settings/update").first)
    #expect(update["model"] as? String == "o4-mini")
    #expect(update["effort"] as? String == "high")
    #expect(update["permissions"] as? String == ":read-only")
    let mode = try #require(update["collaborationMode"] as? [String: Any])
    #expect(mode["mode"] as? String == "plan")
    let settings = try #require(mode["settings"] as? [String: Any])
    #expect(settings["model"] as? String == "o4-mini")
    #expect(settings["reasoning_effort"] as? String == "high")
}

// task-7: startNew でも restore と同様に persisted model/effort を thread へ再適用する。
@Test @MainActor
func chatSessionViewModel_startNewReappliesPersistedSettingsForCodex() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write"),
        persistedSettings: CodexAppServerSessionSettings(
            selectedModel: "o4-mini",
            selectedEffort: "high"
        )
    )

    let methods = transport.sentMethods()
    #expect(methods.contains("thread/settings/update"))
    let update = try #require(transport.capturedParams(for: "thread/settings/update").first)
    #expect(update["model"] as? String == "o4-mini")
    #expect(update["effort"] as? String == "high")
    #expect(vm.selectedModel == "o4-mini")
    #expect(vm.selectedEffort == "high")
}

// task-7: spawn 系 startNew は persisted model/effort を loadSpawnAgentSettings 経由で反映する。
@Test @MainActor
func chatSessionViewModel_startNewAppliesPersistedSpawnSettings() async throws {
    let client = RecordingSpawnSettingsClient()
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
    #expect(client.calls.last == RecordedSpawnSettingsCall(model: "fable", permissionOrMode: "bypassPermissions", effort: "max"))
}

@Test @MainActor
func chatSessionViewModel_startNewSendsCodexCompatibleThreadStartSources() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    let params = try #require(transport.capturedThreadStartParams())
    #expect(params["threadSource"] as? String == ThreadSource.user.rawValue)
    #expect(params["sessionStartSource"] as? String == SessionStartSource.startup.rawValue)
}

@Test @MainActor
func chatSessionViewModel_buildsTranscriptAndCompletesTurns() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    #expect(vm.status == .idle)
    #expect(vm.threadId == "thread-1")
    #expect(vm.appServerUserAgent == "codex-test/1")

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"hello"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/reasoning/summaryTextDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"reason-1","delta":"thinking"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/commandExecution/outputDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"cmd-1","delta":"ok"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/fileChange/patchUpdated","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"file-1","changes":[{"path":"README.md","diff":"+hi"}]}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    try await waitUntil { vm.completedTurnSeq == 1 }
    #expect(vm.status == .idle)
    #expect(vm.lastTurnCompletedAt != nil)
    #expect(vm.transcript.contains(.agentMessage(id: "agent-1", text: "hello", timestamp: fixedChatItemTimestamp())))
    #expect(vm.transcript.contains(.reasoning(id: "reason-1", text: "thinking", timestamp: fixedChatItemTimestamp())))
    #expect(vm.transcript.contains(.commandExecution(id: "cmd-1", command: nil, output: "ok", timestamp: fixedChatItemTimestamp())))
    #expect(vm.readText(lines: 10).contains("README.md"))
}

@Test @MainActor
func chatSessionViewModel_accumulatesCommandOutputAfterCommandItemStarted() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/started","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"cmd-1","type":"command_execution","command":"swift test","text":""}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/commandExecution/outputDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"cmd-1","delta":"Build complete\\n"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/commandExecution/outputDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"cmd-1","delta":"Test Suite passed"}}
    """)

    try await waitUntil {
        vm.transcript.contains { item in
            if case .commandExecution("cmd-1", "swift test", "Build complete\nTest Suite passed", _) = item {
                return true
            }
            return false
        }
    }
}

@Test @MainActor
func chatSessionViewModel_accumulatesCommandOutputForCommandQualifiedEvents() async throws {
    let client = EventYieldingStructuredClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    client.yield(.commandExecution(itemId: "cmd-1", command: "swift test", outputDelta: ""))
    client.yield(.commandExecution(itemId: "cmd-1", command: "swift test", outputDelta: "Build complete\n"))
    client.yield(.commandExecution(itemId: "cmd-1", command: "swift test", outputDelta: "Test Suite passed"))

    try await waitUntil {
        vm.transcript.contains { item in
            if case .commandExecution("cmd-1", "swift test", "Build complete\nTest Suite passed", _) = item {
                return true
            }
            return false
        }
    }
}

@Test @MainActor
func chatSessionViewModel_warningAppendsMessageWithoutChangingStatus() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    try await waitUntil { vm.status == .running }

    transport.receive("""
    {"jsonrpc":"2.0","method":"warning","params":{"threadId":"thread-1","message":"heads up"}}
    """)

    try await waitUntil {
        vm.transcript.contains { item in
            if case .error(_, "heads up", _) = item {
                return true
            }
            return false
        }
    }
    #expect(vm.status == .running)
}

@Test @MainActor
func chatSessionViewModel_turnInterruptedDoesNotIncrementCompletedTurnSeq() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    try await waitUntil { vm.status == .running }

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/interrupted","params":{"threadId":"thread-1","turnId":"turn-1"}}
    """)

    try await waitUntil { vm.status == .idle }
    #expect(vm.completedTurnSeq == 0)
    #expect(vm.lastTurnCompletedAt == nil)
}

@Test @MainActor
func chatSessionViewModel_turnInterruptRecoversToIdleWhenClientInterruptFails() async throws {
    let client = ThrowingInterruptStructuredClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("first", submit: true)
    #expect(vm.status == .running)

    await vm.turnInterrupt()

    #expect(vm.status == .idle)
    #expect(
        vm.transcript.contains { item in
            if case .error(_, let message, _) = item {
                return message.contains("中止リクエストに失敗しました")
            }
            return false
        }
    )
}

@Test @MainActor
func chatSessionViewModel_turnInterruptAllowsResendAfterInterruptFailure() async throws {
    let client = ThrowingInterruptStructuredClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("first", submit: true)
    await vm.turnInterrupt()

    try await vm.sendText("retry", submit: true)

    #expect(client.recordedTurnTexts() == ["first", "retry"])
    #expect(vm.status == .running)
}

@Test @MainActor
func chatSessionViewModel_turnInterruptClearsRunningBackgroundTasks() async throws {
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
        taskId: "task-1",
        taskType: "local_bash",
        description: "sleep 1",
        toolUseId: "tool-1"
    ))
    try await waitUntil { !vm.runningBackgroundTasks.isEmpty }
    #expect(vm.runningBackgroundTasks.count == 1)

    await vm.turnInterrupt()

    #expect(vm.runningBackgroundTasks.isEmpty)
    #expect(vm.status == .idle)
}

@Test @MainActor
func chatSessionViewModel_threadStatusChangedReflectsNonApprovalStatus() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"thread/status/changed","params":{"threadId":"thread-1","status":{"type":"active","activeFlags":[]}}}
    """)
    try await waitUntil { vm.status == .running }

    transport.receive("""
    {"jsonrpc":"2.0","method":"thread/status/changed","params":{"threadId":"thread-1","status":{"type":"idle"}}}
    """)
    try await waitUntil { vm.status == .idle }
}

@Test @MainActor
func chatSessionViewModel_tracksApprovalAndResponds() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","id":99,"method":"item/commandExecution/requestApproval","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"cmd-1","startedAtMs":1,"command":"pwd","cwd":"/tmp","reason":"run pwd"}}
    """)

    try await waitUntil { vm.pendingApprovals.count == 1 }
    #expect(vm.status == .awaitingApproval(prompt: "run pwd"))
    await vm.respondToApproval(vm.pendingApprovals[0].id, decision: .accept)
    try await waitUntil { vm.pendingApprovals.isEmpty }
    #expect(vm.status == .running)
}

@Test @MainActor
func chatSessionViewModel_codexRestorePrefersTranscriptStoreOverThreadRead() async throws {
    let store = RecordingTranscriptStore()
    let sessionID = SessionID()
    let persisted: [ChatItem] = [
        .userMessage(id: "user-store", text: "inspect the workspace", timestamp: fixedChatItemTimestamp()),
        .commandExecution(id: "command-store", command: "pwd", output: "/tmp/work", timestamp: fixedChatItemTimestamp()),
        .agentMessage(id: "agent-store", text: "done", timestamp: fixedChatItemTimestamp()),
    ]
    try await store.upsertTranscriptItems(persisted, for: sessionID)

    let transport = ScriptedAppServerTransport()
    transport.readThreadJSON = [
        "id": "thread-1",
        "status": ["type": "idle"],
        "turns": [],
    ]
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: sessionID,
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work",
        transcriptStore: store
    )

    await vm.restore(
        threadId: "thread-1",
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )

    #expect(vm.restoreState == .restored)
    #expect(vm.status == .idle)
    #expect(vm.transcript == persisted)
    #expect(transport.sentMethods().contains("thread/resume"))
    #expect(!transport.sentMethods().contains("thread/read"))
}

@Test @MainActor
func chatSessionViewModel_codexRestoreFallsBackToThreadReadWhenTranscriptStoreIsEmpty() async throws {
    let transport = ScriptedAppServerTransport()
    transport.readThreadJSON = [
        "id": "thread-1",
        "status": ["type": "idle"],
        "turns": [[
            "id": "turn-1",
            "status": "completed",
            "items": [
                ["id": "user-thread", "type": "user_message", "text": "from thread"],
                ["id": "agent-thread", "type": "agent_message", "text": "fallback"],
            ],
        ]],
    ]
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work",
        transcriptStore: RecordingTranscriptStore()
    )

    await vm.restore(
        threadId: "thread-1",
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )

    #expect(vm.restoreState == .restored)
    #expect(vm.completedTurnSeq == 1)
    #expect(vm.transcript == [
        .userMessage(id: "user-thread", text: "from thread", timestamp: fixedChatItemTimestamp()),
        .agentMessage(id: "agent-thread", text: "fallback", timestamp: fixedChatItemTimestamp()),
    ])
    #expect(transport.sentMethods().contains("thread/read"))
}

@Test @MainActor
func chatSessionViewModel_restoresTranscriptFromThreadRead() async throws {
    let transport = ScriptedAppServerTransport()
    transport.readThreadJSON = [
        "id": "thread-1",
        "status": ["type": "idle"],
        "turns": [[
            "id": "turn-1",
            "status": "completed",
            "items": [
                ["id": "user-1", "type": "user_message", "text": "hi"],
                ["id": "agent-1", "type": "agent_message", "text": "hello"],
            ],
        ]],
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
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )

    #expect(vm.restoreState == .restored)
    #expect(vm.completedTurnSeq == 1)
    #expect(vm.transcript == [
        .userMessage(id: "user-1", text: "hi", timestamp: fixedChatItemTimestamp()),
        .agentMessage(id: "agent-1", text: "hello", timestamp: fixedChatItemTimestamp()),
    ])
}

@Test @MainActor
func chatSessionViewModel_restoresReasoningTextFromReasoningAndThinkingKeys() async throws {
    let transport = ScriptedAppServerTransport()
    transport.readThreadJSON = [
        "id": "thread-1",
        "status": ["type": "idle"],
        "turns": [[
            "id": "turn-1",
            "status": "completed",
            "items": [
                ["id": "reason-1", "type": "reasoning_summary", "reasoning": "checked the command output"],
                ["id": "reason-2", "type": "reasoning_summary", "thinking": "verified the transcript restore"],
            ],
        ]],
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
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )

    #expect(vm.transcript.contains(.reasoning(
        id: "reason-1",
        text: "checked the command output",
        timestamp: fixedChatItemTimestamp()
    )))
    #expect(vm.transcript.contains(.reasoning(
        id: "reason-2",
        text: "verified the transcript restore",
        timestamp: fixedChatItemTimestamp()
    )))
}

@Test @MainActor
func chatSessionViewModel_excludesEmptyMessagesFromRestore() async throws {
    let transport = ScriptedAppServerTransport()
    transport.readThreadJSON = [
        "id": "thread-1",
        "status": ["type": "idle"],
        "turns": [[
            "id": "turn-1",
            "status": "completed",
            "items": [
                ["id": "user-empty", "type": "user_message", "text": ""],
                ["id": "user-ws", "type": "user_message", "text": "   "],
                ["id": "agent-empty", "type": "agent_message", "text": ""],
                ["id": "user-1", "type": "user_message", "text": "hi"],
                ["id": "agent-1", "type": "agent_message", "text": "hello"],
            ],
        ]],
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
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )

    #expect(vm.transcript == [
        .userMessage(id: "user-1", text: "hi", timestamp: fixedChatItemTimestamp()),
        .agentMessage(id: "agent-1", text: "hello", timestamp: fixedChatItemTimestamp()),
    ])
}

@Test @MainActor
func chatSessionViewModel_excludesEmptyReasoningFromRestore() async throws {
    let transport = ScriptedAppServerTransport()
    transport.readThreadJSON = [
        "id": "thread-1",
        "status": ["type": "idle"],
        "turns": [[
            "id": "turn-1",
            "status": "completed",
            "items": [
                ["id": "reason-empty", "type": "reasoning_summary", "reasoning": ""],
                ["id": "reason-ws", "type": "reasoning_summary", "thinking": "   "],
                ["id": "reason-1", "type": "reasoning_summary", "reasoning": "visible"],
            ],
        ]],
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
        approvalPolicy: .named("on-request"),
        sandbox: .named("workspace-write")
    )

    #expect(!vm.transcript.contains { $0.id == "reason-empty" })
    #expect(!vm.transcript.contains { $0.id == "reason-ws" })
    #expect(vm.transcript.contains(.reasoning(id: "reason-1", text: "visible", timestamp: fixedChatItemTimestamp())))
}

// task-7 成功基準4（真の再現テスト）: turn 境界の bulk flush が空 reasoning を永続しないこと。
// 実 Codex では reasoning summary delta が空で先着し、空セルが transcript に残ったまま
// flushTranscriptAtTurnBoundary が transcript を丸ごと渡すため空 reasoning が保存される。
// 修正前は fail（空 reasoning が store へ渡る）、修正後は pass。
@Test @MainActor
func chatSessionViewModel_bulkFlushExcludesEmptyReasoningButKeepsNonEmpty() async throws {
    let store = RecordingTranscriptStore()
    let client = EventYieldingStructuredClient()
    #expect(!(client is any CodexSettingsProviding))
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
    client.yield(.reasoningDelta(itemId: "reason-empty", ""))
    client.yield(.reasoningDelta(itemId: "reason-full", "実際の思考"))
    client.yield(.turnCompleted(nativeSessionId: nil))

    try await waitUntil {
        guard let stored = await (try? store.loadTranscript(for: sessionID)) else { return false }
        return stored.contains { $0.id == "reason-full" }
    }
    let stored = try await store.loadTranscript(for: sessionID)
    #expect(stored.contains(.reasoning(id: "reason-full", text: "実際の思考", timestamp: fixedChatItemTimestamp())))
    #expect(!stored.contains { $0.id == "reason-empty" })
    let batches = await store.upsertedBatches
    #expect(batches.allSatisfy { batch in !batch.contains { $0.id == "reason-empty" } })
}

// task-7 成功基準1: ライブ delta で蓄積した非空 reasoning は、同 itemId・type 一致の
// 空 item/completed が来ても消えず・空化せず、非空のまま表示/永続される。
@Test @MainActor
func chatSessionViewModel_liveReasoningSurvivesEmptyCompletedSameType() async throws {
    let store = RecordingTranscriptStore()
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let sessionID = SessionID()
    let vm = ChatSessionViewModel(
        id: sessionID,
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work",
        transcriptStore: store
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/reasoning/summaryTextDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"reason-1","delta":"考えた"}}
    """)
    try await waitUntil {
        vm.transcript.contains(.reasoning(id: "reason-1", text: "考えた", timestamp: fixedChatItemTimestamp()))
    }
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"reason-1","type":"reasoning_summary","text":""}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    try await waitUntil { vm.completedTurnSeq == 1 }
    #expect(vm.transcript.contains(.reasoning(id: "reason-1", text: "考えた", timestamp: fixedChatItemTimestamp())))
    try await waitUntil {
        guard let stored = await (try? store.loadTranscript(for: sessionID)) else { return false }
        return stored.contains(.reasoning(id: "reason-1", text: "考えた", timestamp: fixedChatItemTimestamp()))
    }
}

// task-7 成功基準2: 空 item/completed の type が reasoning にマッチしない別名でも、
// ライブの非空 reasoning セルを潰さない（appendOrReplace の空 removeAll 分岐を塞ぐ）。
@Test @MainActor
func chatSessionViewModel_liveReasoningSurvivesEmptyCompletedMismatchedType() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/reasoning/summaryTextDelta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"reason-1","delta":"考えた"}}
    """)
    try await waitUntil {
        vm.transcript.contains(.reasoning(id: "reason-1", text: "考えた", timestamp: fixedChatItemTimestamp()))
    }
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"reason-1","type":"note","text":""}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    try await waitUntil { vm.completedTurnSeq == 1 }
    #expect(vm.transcript.contains(.reasoning(id: "reason-1", text: "考えた", timestamp: fixedChatItemTimestamp())))
}

// task-7 成功基準3: reasoningDelta 無しで空の started/completed だけが来たときは
// 空 reasoning セルが transcript にも永続先にも現れない。
@Test @MainActor
func chatSessionViewModel_emptyReasoningItemOnlyIsNotPersisted() async throws {
    let store = RecordingTranscriptStore()
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let sessionID = SessionID()
    let vm = ChatSessionViewModel(
        id: sessionID,
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work",
        transcriptStore: store
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/started","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"reason-x","type":"reasoning_summary","text":""}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"reason-x","type":"reasoning_summary","text":""}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    try await waitUntil { vm.completedTurnSeq == 1 }
    #expect(!vm.transcript.contains { $0.id == "reason-x" })
    let stored = try await store.loadTranscript(for: sessionID)
    #expect(!stored.contains { $0.id == "reason-x" })
}

@Test @MainActor
func chatSessionViewModel_agentMessageDeltaFillsAfterEmptyItemStarted() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/started","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"agent-1","type":"agent_message","text":""}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"hello"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    try await waitUntil { vm.completedTurnSeq == 1 }
    #expect(vm.transcript.contains(.agentMessage(id: "agent-1", text: "hello", timestamp: fixedChatItemTimestamp())))
    #expect(vm.readText(lines: 10).contains("Agent: hello"))
}

@Test @MainActor
func chatSessionViewModel_excludesEmptyMessagesFromItemEvents() async throws {
    let transport = ScriptedAppServerTransport()
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/work"
    )

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    transport.receive("""
    {"jsonrpc":"2.0","method":"item/started","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"user-empty","type":"user_message","text":""}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"user-empty","type":"user_message","text":""}}}
    """)

    try await waitUntil { vm.rawEventLog.count >= 2 }
    #expect(!vm.transcript.contains { $0.id == "user-empty" })
}

@Test @MainActor
func waitUntilDone_returnsDoneForChatSessionTurnCompletion() async throws {
    let ptyManager = MockPTYManager()
    let transport = ScriptedAppServerTransport()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/bin/codex"],
        appServerClientFactory: { _, _, _, _, handler in
            let client = CodexAppServerClient(transport: transport, serverRequestHandler: handler)
            return CodexStructuredAgentClient(client: client)
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(
        kind: .codex,
        backend: .appServer,
        launchContext: .orchestration
    )
    #expect(dashboard.sessions.isEmpty)
    #expect(dashboard.sessionNodes.count == 1)
    #expect(ptyManager.spawnCalls.isEmpty)

    let waitTask = Task {
        await dashboard.waitUntilDone(for: sessionID, timeout: .seconds(2), sentinel: nil)
    }
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"done"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    let result = await waitTask.value
    #expect(result == .done(output: "Agent: done"))
}

@Test @MainActor
func waitUntilDone_returnsDoneWhenChatTurnCompletedBeforeWaitStarts() async throws {
    let ptyManager = MockPTYManager()
    let transport = ScriptedAppServerTransport()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/bin/codex"],
        appServerClientFactory: { _, _, _, _, handler in
            let client = CodexAppServerClient(transport: transport, serverRequestHandler: handler)
            return CodexStructuredAgentClient(client: client)
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(
        kind: .codex,
        backend: .appServer,
        launchContext: .orchestration
    )
    let chat = try #require(dashboard.sessionNodes.first(where: { $0.id == sessionID })?.appServer)
    try await chat.sendText("do work", submit: true)

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"race-fixed"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    try await waitUntil { chat.completedTurnSeq == 1 }

    let result = await dashboard.waitUntilDone(for: sessionID, timeout: .seconds(2), sentinel: nil)
    #expect(result == .done(output: "User: do work\nAgent: race-fixed"))
}

@Test @MainActor
func waitUntilDone_doesNotReturnStaleDoneOnSecondWaitWithoutSubmit() async throws {
    let ptyManager = MockPTYManager()
    let transport = ScriptedAppServerTransport()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/bin/codex"],
        appServerClientFactory: { _, _, _, _, handler in
            let client = CodexAppServerClient(transport: transport, serverRequestHandler: handler)
            return CodexStructuredAgentClient(client: client)
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(
        kind: .codex,
        backend: .appServer,
        launchContext: .orchestration
    )
    let chat = try #require(dashboard.sessionNodes.first(where: { $0.id == sessionID })?.appServer)
    try await chat.sendText("do work", submit: true)

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"stale-test"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    try await waitUntil { chat.completedTurnSeq == 1 }

    let firstResult = await dashboard.waitUntilDone(for: sessionID, timeout: .seconds(2), sentinel: nil)
    #expect(firstResult == .done(output: "User: do work\nAgent: stale-test"))

    let secondResult = await dashboard.waitUntilDone(for: sessionID, timeout: .milliseconds(100), sentinel: nil)
    switch secondResult {
    case .timedOut:
        break
    default:
        Issue.record("Expected .timedOut on second wait without submit, got \(secondResult)")
    }
}

// 経路1（既存 completedTurnSeq > baselineTurnSeq）の consume 回帰を守る。
// 通常の dispatch フロー（submit → wait、wait 中に turn 完了）はこの経路で done を返すため、
// ここの consumeSubmitBaseline() が失われると、2回目 wait が submitBaseline 経路で stale-done を再発する。
@Test @MainActor
func waitUntilDone_doesNotReturnStaleDoneAfterPath1CompletionDuringWait() async throws {
    let ptyManager = MockPTYManager()
    let transport = ScriptedAppServerTransport()
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let environment = makeTestEnvironment(
        pty: ptyManager,
        hookStream: hookStream,
        agentBinaryPaths: [.codex: "/usr/bin/codex"],
        appServerClientFactory: { _, _, _, _, handler in
            let client = CodexAppServerClient(transport: transport, serverRequestHandler: handler)
            return CodexStructuredAgentClient(client: client)
        }
    )
    let dashboard = DashboardViewModel(environment: environment)
    await dashboard.start()

    let sessionID = try await dashboard.spawnNewSession(
        kind: .codex,
        backend: .appServer,
        launchContext: .orchestration
    )
    let chat = try #require(dashboard.sessionNodes.first(where: { $0.id == sessionID })?.appServer)
    try await chat.sendText("do work", submit: true)

    // wait を turn 完了より前に開始する → baselineTurnSeq=0。turn 完了で completedTurnSeq=1 になり経路1で done。
    let waitTask = Task {
        await dashboard.waitUntilDone(for: sessionID, timeout: .seconds(2), sentinel: nil)
    }
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"running"}}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{"threadId":"thread-1","turnId":"turn-1","itemId":"agent-1","delta":"path1-done"}}
    """)
    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-1","status":"completed"}}}
    """)

    #expect(await waitTask.value == .done(output: "User: do work\nAgent: path1-done"))

    // fresh submit 無しの2回目 wait は timedOut（経路1で consume 済みなら submitBaselineTurnSeq==nil）。
    let secondResult = await dashboard.waitUntilDone(for: sessionID, timeout: .milliseconds(100), sentinel: nil)
    switch secondResult {
    case .timedOut:
        break
    default:
        Issue.record("Expected .timedOut on second wait after path-1 completion, got \(secondResult)")
    }
}

// MARK: - task-9 esc 状態機械（白箱・境界/性質/interleaving）

/// interrupt 回数を数えつつイベントも yield できる軽量クライアント（esc 状態機械テスト用）。
final class EscInterruptCountingClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var interruptCount = 0

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        self.events = AsyncStream { captured = $0 }
        self.continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws { lock.withLock { interruptCount += 1 } }
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
    func interruptCalls() -> Int { lock.withLock { interruptCount } }
}

@MainActor
private func escStateMachineVM(client: EscInterruptCountingClient) async throws -> ChatSessionViewModel {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.cursor),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    return vm
}

@MainActor
private func escSeedCompletedUserTurn(_ vm: ChatSessionViewModel, client: EscInterruptCountingClient, text: String) async throws {
    try await vm.sendText(text, submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
}

// 境界: 直前 esc からちょうど 1.5 秒（窓の内側・包含）は 2連打としてピッカーを開く。
@Test @MainActor
func handleEscape_doubleTapBoundaryIsInclusiveAt1_5s() async throws {
    let client = EscInterruptCountingClient()
    let vm = try await escStateMachineVM(client: client)
    try await escSeedCompletedUserTurn(vm, client: client, text: "依頼A")

    let t0 = Date(timeIntervalSinceReferenceDate: 10_000)
    vm.handleEscapeKey(now: t0)
    vm.handleEscapeKey(now: t0.addingTimeInterval(1.5))
    #expect(vm.isHistoryPickerPresented)
}

// 境界: 1.5 秒を僅かに超えたら 2連打とみなさずピッカーは開かない。
@Test @MainActor
func handleEscape_doubleTapJustOverWindowDoesNotOpen() async throws {
    let client = EscInterruptCountingClient()
    let vm = try await escStateMachineVM(client: client)
    try await escSeedCompletedUserTurn(vm, client: client, text: "依頼A")

    let t0 = Date(timeIntervalSinceReferenceDate: 11_000)
    vm.handleEscapeKey(now: t0)
    vm.handleEscapeKey(now: t0.addingTimeInterval(1.5001))
    #expect(!vm.isHistoryPickerPresented)
}

// rule 4: idle の単発 esc は interrupt を呼ばず・ピッカーも開かない（時刻記録のみ）。
@Test @MainActor
func handleEscape_singleEscWhileIdleDoesNotInterrupt() async throws {
    let client = EscInterruptCountingClient()
    let vm = try await escStateMachineVM(client: client)
    try await escSeedCompletedUserTurn(vm, client: client, text: "依頼A")

    vm.handleEscapeKey(now: Date(timeIntervalSinceReferenceDate: 12_000))
    #expect(!vm.isHistoryPickerPresented)
    // Task が発火しないことの確認（少し待っても 0 のまま）。
    try? await Task.sleep(nanoseconds: 50_000_000)
    #expect(client.interruptCalls() == 0)
}

// ハザード3: running での単発 esc は interrupt を発火し、その完了を待たずに 2回目 esc でピッカーが開く。
@Test @MainActor
func handleEscape_hazard3_secondEscOpensPickerWithoutWaitingForInterrupt() async throws {
    let client = EscInterruptCountingClient()
    let vm = try await escStateMachineVM(client: client)
    try await escSeedCompletedUserTurn(vm, client: client, text: "依頼1")
    try await vm.sendText("依頼2", submit: true) // running のまま（turnCompleted を送らない）
    #expect(vm.status == .running)

    let t0 = Date(timeIntervalSinceReferenceDate: 13_000)
    vm.handleEscapeKey(now: t0)                        // 単発・running → interrupt を Task 発火
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.3)) // 2連打 → ピッカー（interrupt 完了非依存）

    #expect(vm.isHistoryPickerPresented)               // 即・同期で開く
    try await waitUntil { client.interruptCalls() == 1 } // interrupt は非同期に呼ばれる
}

// 性質: revertCandidates は userMessage のみを新しい順に返す（agent/reasoning を除外）。
@Test @MainActor
func revertCandidates_excludesNonUserItemsAndOrdersNewestFirst() async throws {
    let client = EscInterruptCountingClient()
    let vm = try await escStateMachineVM(client: client)
    try await vm.sendText("最初", submit: true)
    client.yield(.agentMessageDelta(itemId: "a1", "返答1"))
    client.yield(.reasoningDelta(itemId: "r1", "考え"))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    try await vm.sendText("二番目", submit: true)
    client.yield(.agentMessageDelta(itemId: "a2", "返答2"))
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    let candidates = vm.revertCandidates
    #expect(candidates.count == 2)
    #expect(candidates.allSatisfy { if case .userMessage = $0 { return true } else { return false } })
    #expect(candidates[0].plainText.contains("二番目"), "新しい順で並んでいない")
    #expect(candidates[1].plainText.contains("最初"))
}

// R1 判断の裏取り: ピッカーを閉じた esc は 2連打タイマをリセットし、直後の esc で再オープンしない。
@Test @MainActor
func handleEscape_closingPickerResetsDoubleTapTimer() async throws {
    let client = EscInterruptCountingClient()
    let vm = try await escStateMachineVM(client: client)
    try await escSeedCompletedUserTurn(vm, client: client, text: "依頼A")

    let t0 = Date(timeIntervalSinceReferenceDate: 14_000)
    vm.handleEscapeKey(now: t0)
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.3))
    try #require(vm.isHistoryPickerPresented)
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.6)) // 閉じる（タイマ reset）
    try #require(!vm.isHistoryPickerPresented)
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.7)) // 直後の esc は単発扱い＝再オープンしない
    #expect(!vm.isHistoryPickerPresented)
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

// PM 裁定（task-9 レビュー MEDIUM 対応）: esc 1回目の interrupt が未収束の running 窓で
// 履歴を確定しても無音 no-op にならない——confirmRevert が先に中断を完了させてからリバートする。
@Test @MainActor
func confirmRevert_whileStillRunning_interruptsThenReverts() async throws {
    let client = EscInterruptCountingClient()
    let vm = try await escStateMachineVM(client: client)
    try await escSeedCompletedUserTurn(vm, client: client, text: "依頼1")
    try await vm.sendText("依頼2", submit: true) // turnCompleted を流さない = running のまま
    #expect(vm.status == .running)

    let newest = try #require(vm.revertCandidates.first)
    await vm.confirmRevert(toUserMessageID: newest.id)

    #expect(client.interruptCalls() == 1)
    #expect(vm.status == .idle)
    #expect(vm.draftRestoration == "依頼2")
    #expect(!vm.transcript.map(\.plainText).joined().contains("依頼2"))
    #expect(!vm.isHistoryPickerPresented)
}
