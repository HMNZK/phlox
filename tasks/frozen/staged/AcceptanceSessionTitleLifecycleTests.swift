// 実パス（凍結時に PM が移す）:
// macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionTitleLifecycleTests.swift
//
// task-44（UX-01b）受け入れテスト。チャット本文の候補採用・PTY 非導出・titleState 窓口。
// 実バックエンド（claude / codex / cursor）は起動しない。StructuredAgentClient のテスト用実装のみ。
//
// 契約: tasks/task-44.md VM・共通窓口 / チャット本文の候補採用 / PTY 方針 / 成功基準 2。
// 期待値は契約リテラル。被検査関数から生成しない。実装役はアサーションを変更禁止。
//
// 解釈（契約の曖昧点）: 新規 VM の花名状態は init の `titleState:` で渡す。
// 通常の `name` 代入は renamed(to:) による手動化であり、花名の初期化には使わない。
// サーバー履歴は local TranscriptStore ではなく Codex `threadRead` へ注入する。
// ユーザー項目のサーバー反映は `.itemStarted` / `.itemCompleted` → `chatItem` → `appendOrReplace`。
// 由来の識別は同一本文に `originalText` があるかないかだけを変える（本文の見た目では推測しない）。

import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import PTYKit
import StructuredChatKit
import TerminalUI
@testable import SessionFeature

private enum TitleLifecycleJSON {
    static let decoder = JSONDecoder()

    static func decode<T: Decodable>(_ json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    static func threadItem(_ json: String) throws -> ThreadItem {
        try decode(json)
    }

    static func initializeResponse() throws -> InitializeResponse {
        try decode(#"{"codexHome":"/tmp","platformFamily":"macOS","platformOs":"macOS","userAgent":"test"}"#)
    }

    static func threadResponse(id: String) throws -> ThreadResponse {
        try decode("{\"thread\":{\"id\":\"\(id)\",\"status\":{\"type\":\"idle\"}}}")
    }

    static func threadReadResponse(threadId: String, itemsJSON: String) throws -> ThreadReadResponse {
        try decode(
            "{\"thread\":{\"id\":\"\(threadId)\",\"turns\":[{\"id\":\"turn-1\",\"status\":\"completed\",\"items\":\(itemsJSON)}]}}"
        )
    }
}

private final class TitleLifecycleClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var turnStartInputs: [[ChatInput]] = []
    var turnStartError: Error?

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }

    func recordedTurnStarts() -> [[ChatInput]] {
        lock.withLock { turnStartInputs }
    }

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        lock.withLock { turnStartInputs.append(input) }
        if let turnStartError {
            throw turnStartError
        }
    }

    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

private final class TitleCodexClient: StructuredAgentClient, CodexSettingsProviding, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let threadEvents: AsyncStream<ThreadEvent>
    private let eventContinuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let threadEventContinuation: AsyncStream<ThreadEvent>.Continuation
    private let lock = NSLock()
    private var turnStartInputs: [[ChatInput]] = []
    var turnStartError: Error?
    var liveThreadID = "thread-live"
    var threadReadItemsJSON = "[]"
    var shouldGateThreadRead = false
    private var threadReadEntered = false
    private var threadReadEnteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var threadReadHold: CheckedContinuation<Void, Never>?

    init() {
        var capturedEvent: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { capturedEvent = $0 }
        eventContinuation = capturedEvent!
        var capturedThread: AsyncStream<ThreadEvent>.Continuation?
        threadEvents = AsyncStream { capturedThread = $0 }
        threadEventContinuation = capturedThread!
    }

    func yield(_ event: NormalizedChatEvent) {
        eventContinuation.yield(event)
    }

    func yieldThread(_ event: ThreadEvent) {
        threadEventContinuation.yield(event)
    }

    func recordedTurnStarts() -> [[ChatInput]] {
        lock.withLock { turnStartInputs }
    }

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        lock.withLock { turnStartInputs.append(input) }
        if let turnStartError {
            throw turnStartError
        }
    }

    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async {
        eventContinuation.finish()
        threadEventContinuation.finish()
    }

    func activeThreadId() async -> String? { liveThreadID }

    func initialize(_ params: InitializeParams) async throws -> InitializeResponse {
        try TitleLifecycleJSON.initializeResponse()
    }

    func threadStart(_ params: ThreadStartParams) async throws -> ThreadResponse {
        try TitleLifecycleJSON.threadResponse(id: liveThreadID)
    }

    func threadResume(_ params: ThreadResumeParams) async throws -> ThreadResponse {
        liveThreadID = params.threadId
        try TitleLifecycleJSON.threadResponse(id: params.threadId)
    }

    func threadRead(_ params: ThreadReadParams) async throws -> ThreadReadResponse {
        if shouldGateThreadRead {
            lock.withLock {
                threadReadEntered = true
                threadReadEnteredWaiters.forEach { $0.resume() }
                threadReadEnteredWaiters.removeAll()
            }
            await withCheckedContinuation { continuation in
                lock.withLock { threadReadHold = continuation }
            }
        }
        return try TitleLifecycleJSON.threadReadResponse(
            threadId: params.threadId,
            itemsJSON: threadReadItemsJSON
        )
    }

    func waitUntilThreadReadEntered() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if threadReadEntered {
                    continuation.resume()
                } else {
                    threadReadEnteredWaiters.append(continuation)
                }
            }
        }
    }

    func releaseThreadRead() {
        lock.withLock {
            threadReadHold?.resume()
            threadReadHold = nil
        }
    }

    func listModels(_ params: ModelListParams) async throws -> ModelListResponse {
        try TitleLifecycleJSON.decode(#"{"data":[]}"#)
    }

    func listPermissionProfiles(_ params: PermissionProfileListParams) async throws -> PermissionProfileListResponse {
        try TitleLifecycleJSON.decode(#"{"data":[]}"#)
    }

    func listCollaborationModes(_ params: CollaborationModeListParams) async throws -> CollaborationModeListResponse {
        try TitleLifecycleJSON.decode(#"{"data":[]}"#)
    }

    func updateThreadSettings(_ params: ThreadSettingsUpdateParams) async throws -> ThreadSettingsUpdateResponse {
        ThreadSettingsUpdateResponse()
    }
}

private struct TitleTurnStartFailure: Error {}

private final class TitleLifecyclePTY: PTYManagerProtocol, @unchecked Sendable {
    func spawn(
        command: String,
        args: [String],
        env: [String: String],
        id: SessionID?,
        initialSize: PTYInitialSize?,
        workingDirectory: String?
    ) async throws -> SessionID {
        id ?? SessionID()
    }

    func write(_ data: Data, to id: SessionID) async throws {}
    func kill(_ id: SessionID) async {}
    func resize(_ id: SessionID, cols: UInt16, rows: UInt16) async throws {}
    func outputStream(for id: SessionID) -> AsyncStream<Data> {
        AsyncStream { $0.finish() }
    }

    func exitStream(for id: SessionID) -> AsyncStream<Int32> {
        AsyncStream { $0.finish() }
    }

    func getWinsize(_ id: SessionID) async -> (cols: UInt16, rows: UInt16)? {
        nil
    }
}

private final class TitleLifecycleTranscriptStore: TranscriptStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ChatItem]
    var shouldGateLoad = false
    private var loadEntered = false
    private var loadEnteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var loadHold: CheckedContinuation<Void, Never>?

    init(_ items: [ChatItem] = []) {
        self.items = items
    }

    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] {
        if shouldGateLoad {
            lock.withLock {
                loadEntered = true
                loadEnteredWaiters.forEach { $0.resume() }
                loadEnteredWaiters.removeAll()
            }
            await withCheckedContinuation { continuation in
                lock.withLock { loadHold = continuation }
            }
        }
        return lock.withLock { items }
    }

    func waitUntilLoadEntered() async {
        await withCheckedContinuation { continuation in
            lock.withLock {
                if loadEntered {
                    continuation.resume()
                } else {
                    loadEnteredWaiters.append(continuation)
                }
            }
        }
    }

    func releaseLoad() {
        lock.withLock {
            loadHold?.resume()
            loadHold = nil
        }
    }

    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        lock.withLock { self.items.append(contentsOf: items) }
    }

    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {
        lock.withLock { self.items = items }
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () async -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while await !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@MainActor
private func makeChatVM(
    titleState: SessionTitleState = .generated(flowerName: "Rose"),
    client: TitleLifecycleClient = TitleLifecycleClient(),
    transcriptStore: (any TranscriptStore)? = nil,
    historyProvider: (@Sendable () -> [ClaudeSessionHistoryEntry])? = nil,
    historyTranscriptLoader: (@Sendable (ClaudeSessionHistoryEntry) -> [ChatItem])? = nil
) -> (ChatSessionViewModel, TitleLifecycleClient) {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        transcriptStore: transcriptStore,
        historyProvider: historyProvider,
        historyTranscriptLoader: historyTranscriptLoader,
        titleState: titleState
    )
    return (vm, client)
}

@MainActor
private func makeCodexVM(
    titleState: SessionTitleState = .generated(flowerName: "Rose"),
    client: TitleCodexClient = TitleCodexClient(),
    transcriptStore: (any TranscriptStore)? = nil
) -> (ChatSessionViewModel, TitleCodexClient) {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        transcriptStore: transcriptStore,
        titleState: titleState
    )
    return (vm, client)
}

@MainActor
private func makePTYVM(
    titleState: SessionTitleState = .generated(flowerName: "Rose")
) async -> SessionViewModel {
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let vm = SessionViewModel(
        id: SessionID(),
        ptyManager: TitleLifecyclePTY(),
        hookEvents: hookStream,
        terminalCoordinator: TerminalCoordinator(),
        spawnRequest: SessionViewModel.SpawnRequest(
            command: "/bin/cat",
            args: [],
            env: ["TERM": "xterm-256color"],
            workingDirectory: "/tmp/work",
            kind: .claudeCode,
            statusBootstrap: .viaHook
        ),
        titleState: titleState
    )
    await vm.start()
    await vm.spawnEager()
    return vm
}

private func expectState(
    _ state: SessionTitleState,
    _ name: String,
    _ source: SessionTitleSource,
    _ flowerName: String?,
    _ fullDerivedTitle: String?,
    _ label: String
) {
    #expect(state.name == name, Comment(rawValue: "\(label) name"))
    #expect(state.source == source, Comment(rawValue: "\(label) source"))
    #expect(state.flowerName == flowerName, Comment(rawValue: "\(label) flowerName"))
    #expect(state.fullDerivedTitle == fullDerivedTitle, Comment(rawValue: "\(label) fullDerivedTitle"))
}

private func subAgent() -> SubAgentRef {
    SubAgentRef(
        id: "toolu_01TITLE",
        subagentType: "general-purpose",
        description: "調査",
        status: .completed,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

private func unidentifiedSupplementJSON(id: String) -> String {
    "{\"id\":\"\(id)\",\"type\":\"user\",\"text\":\"/review\\nログイン画面を修正\"}"
}

private func identifiedOriginalJSON(id: String, originalText: String) -> String {
    "{\"id\":\"\(id)\",\"type\":\"user\",\"text\":\"/review\\nログイン画面を修正\",\"originalText\":\(jsonString(originalText))}"
}

private func identifiedPlainJSON(id: String, text: String) -> String {
    "{\"id\":\"\(id)\",\"type\":\"user\",\"text\":\(jsonString(text)),\"originalText\":\(jsonString(text))}"
}

private func jsonString(_ value: String) -> String {
    let data = try! JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8)!
}

@MainActor
private func firstUserMessageID(_ vm: ChatSessionViewModel) -> String? {
    for item in vm.transcript {
        if case .userMessage(let id, _, _, _) = item {
            return id
        }
    }
    return nil
}

@MainActor
private func yieldUserItem(
    _ client: TitleCodexClient,
    threadId: String,
    itemJSON: String
) async throws {
    let item = try TitleLifecycleJSON.threadItem(itemJSON)
    client.yieldThread(.itemStarted(threadId: threadId, turnId: "turn-1", item: item))
    client.yieldThread(.itemCompleted(threadId: threadId, turnId: "turn-1", item: item))
}

@Suite("task-44: session title lifecycle")
struct AcceptanceSessionTitleLifecycleTests {
    @Test @MainActor
    func 公開窓口titleStateとdisplayNameのfallbackはshortID() {
        let (vm, _) = makeChatVM(titleState: .legacy(name: ""))
        expectState(vm.titleState, "", .manual, nil, nil, "empty chat")
        #expect(vm.displayName == SessionViewModel.shortID(for: vm.id))
        #expect(SessionNode.appServer(vm).titleState == vm.titleState)
        #expect((vm as any ControllableSession).titleState == vm.titleState)
    }

    @Test @MainActor
    func name代入はrenamedによる手動化であり花名をflowerに戻さない() {
        let (vm, _) = makeChatVM()
        vm.name = "Rose"
        expectState(vm.titleState, "Rose", .manual, "Rose", nil, "assign name")
        #expect(vm.name == "Rose")
        #expect(SessionNode.appServer(vm).titleState.source == .manual)
    }

    @Test @MainActor
    func 未確定入力submit_falseではflowerを維持する() async throws {
        let (vm, _) = makeChatVM()
        try await vm.sendText("ログイン画面を修正", submit: false)
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "submit false")
    }

    @Test @MainActor
    func 添付のみではflowerを維持する() async throws {
        let (vm, _) = makeChatVM()
        let attached = vm.attachmentStore.addImage(
            data: Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
            mediaType: "image/png"
        )
        #expect(attached != nil)
        try await vm.sendText("", submit: true)
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "attachment only")
    }

    @Test @MainActor
    func 適格本文でも送信前ガードで拒否されればflowerのまま本文は確定しない() async throws {
        let (vm, client) = makeChatVM()
        vm.attachmentStore = ComposerAttachmentStore(attachments: [
            ComposerAttachment(data: Data(count: 3 * 1024 * 1024), mediaType: "image/png"),
            ComposerAttachment(data: Data(count: 3 * 1024 * 1024), mediaType: "image/png"),
            ComposerAttachment(data: Data(count: 3 * 1024 * 1024), mediaType: "image/png"),
        ])
        try await vm.sendText("ログイン画面を修正", submit: true)
        #expect(client.recordedTurnStarts().isEmpty, Comment(rawValue: "turnStart not called"))
        #expect(firstUserMessageID(vm) == nil, Comment(rawValue: "body not committed"))
        #expect(vm.status != .running, Comment(rawValue: "not a successful send"))
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "rejected eligible send")
    }

    @Test @MainActor
    func ローカル確定はpendingInputとtextの元本文から導出する() async throws {
        let (vm, _) = makeChatVM()
        try await vm.sendText("ログイン画面を", submit: false)
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "pending only")
        try await vm.sendText("修正", submit: true)
        expectState(
            vm.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "pendingInput + text"
        )
    }

    @Test @MainActor
    func ローカル確定後の通信失敗でも導出名を保持し成功状態へは遷移しない() async throws {
        let client = TitleLifecycleClient()
        client.turnStartError = TitleTurnStartFailure()
        let (vm, _) = makeChatVM(client: client)
        do {
            try await vm.sendText("ログイン画面を修正", submit: true)
        } catch is TitleTurnStartFailure {
        }
        #expect(client.recordedTurnStarts().count == 1, Comment(rawValue: "turnStart called"))
        #expect(firstUserMessageID(vm) != nil, Comment(rawValue: "body committed"))
        #expect(vm.status == .idle, Comment(rawValue: "not left running"))
        expectState(
            vm.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "turnStart failure keeps derived"
        )
    }

    @Test @MainActor
    func follow_upはメインtranscriptの元本文だけを使う() async throws {
        let (vm, client) = makeChatVM()
        try await vm.sendSubAgentFollowUp(subAgent: subAgent(), text: "ログイン画面を修正")
        expectState(
            vm.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "follow-up original"
        )
        let sent = client.recordedTurnStarts().flatMap { $0 }.compactMap { input -> String? in
            if case .text(let text) = input { return text }
            return nil
        }.joined()
        #expect(sent.contains("ログイン画面を修正"))
        #expect(sent.contains("toolu_01TITLE"))
    }

    @Test @MainActor
    func assistant_tool_error_質問回答_別transcriptからは導出しない() async throws {
        let (vm, client) = makeCodexVM()
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        let threadId = try #require(vm.threadId)
        let assistant = try TitleLifecycleJSON.threadItem(
            #"{"id":"a1","type":"agentMessage","text":"ログイン画面を修正"}"#
        )
        let command = try TitleLifecycleJSON.threadItem(
            #"{"id":"t1","type":"commandExecution","text":"通知を修正","command":"ls"}"#
        )
        let error = try TitleLifecycleJSON.threadItem(
            #"{"id":"e1","type":"error","text":"ログイン画面を修正"}"#
        )
        client.yieldThread(.itemStarted(threadId: threadId, turnId: "turn-1", item: assistant))
        client.yieldThread(.itemCompleted(threadId: threadId, turnId: "turn-1", item: assistant))
        client.yieldThread(.itemStarted(threadId: threadId, turnId: "turn-1", item: command))
        client.yieldThread(.itemCompleted(threadId: threadId, turnId: "turn-1", item: command))
        client.yieldThread(.itemStarted(threadId: threadId, turnId: "turn-1", item: error))
        client.yieldThread(.itemCompleted(threadId: threadId, turnId: "turn-1", item: error))
        client.yield(.subAgentOutput(toolUseId: "s1", text: "通知を修正"))
        try await waitUntil { vm.transcript.contains { $0.id == "a1" } }
        try await waitUntil { vm.transcript.contains { $0.id == "e1" } }
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "out of scope items")
    }

    @Test @MainActor
    func 質問回答の入力はタイトル候補にしない() async throws {
        let (vm, client) = makeChatVM()
        client.yield(.userQuestionRequested(
            requestId: "q1",
            questions: [
                ChatUserQuestion(
                    question: "ログイン画面を修正しますか",
                    header: "確認",
                    options: [ChatUserQuestionOption(label: "ログイン画面を修正")],
                    multiSelect: false
                ),
            ]
        ))
        try await waitUntil {
            vm.transcript.contains { item in
                if case .userQuestion(_, "q1", _, _, _, _) = item { return true }
                return false
            }
        }
        let accepted = await vm.respondToUserQuestion(
            requestId: "q1",
            answers: ["ログイン画面を修正しますか": ["ログイン画面を修正"]]
        )
        #expect(accepted)
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "question answer")
    }

    @Test @MainActor
    func ローカル_review_の補足付き送信文字列をitemCompletedで返してもflowerのまま() async throws {
        let (vm, client) = makeCodexVM()
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        try await vm.sendText("/review", submit: true)
        let userID = try #require(firstUserMessageID(vm))
        let threadId = try #require(vm.threadId)
        try await yieldUserItem(
            client,
            threadId: threadId,
            itemJSON: unidentifiedSupplementJSON(id: userID)
        )
        try await waitUntil {
            vm.transcript.contains { item in
                if case .userMessage(userID, let text, _, _) = item {
                    return text.contains("ログイン画面を修正") || text == "/review"
                }
                return false
            } || vm.titleState.source == .flower
        }
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "/review plus supplement")
    }

    @Test @MainActor
    func ローカル本文と対応付くitemCompletedはローカル元本文を使い補足で先に確定しない() async throws {
        let (vm, client) = makeCodexVM()
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        try await vm.sendText("ログイン画面を修正", submit: true)
        expectState(
            vm.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "local commit before server"
        )
        let userID = try #require(firstUserMessageID(vm))
        let threadId = try #require(vm.threadId)
        try await yieldUserItem(
            client,
            threadId: threadId,
            itemJSON: unidentifiedSupplementJSON(id: userID)
        )
        try await waitUntil { vm.transcript.contains { $0.id == userID } }
        expectState(
            vm.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "local original wins"
        )
    }

    @Test @MainActor
    func 元本文_review_と補足を識別できる場合も補足だけを候補にしない() async throws {
        let (vm, _) = makeChatVM()
        try await vm.sendText("/review", submit: true)
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "identifiable /review")
        try await vm.sendText("ログイン画面を修正", submit: false)
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "does not take supplement")
    }

    @Test @MainActor
    func 確定後の置換と再読込と巻き戻しは名前を変更しない() async throws {
        let store = TitleLifecycleTranscriptStore()
        let (vm, client) = makeCodexVM(transcriptStore: store)
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        try await vm.sendText("ログイン画面を修正", submit: true)
        let derived = vm.titleState
        let userID = try #require(firstUserMessageID(vm))
        let threadId = try #require(vm.threadId)
        try await yieldUserItem(
            client,
            threadId: threadId,
            itemJSON: identifiedPlainJSON(id: userID, text: "通知を修正")
        )
        try await waitUntil { vm.transcript.contains { $0.id == userID } }
        expectState(
            vm.titleState,
            derived.name,
            .derived,
            "Rose",
            "ログイン画面を修正",
            "item replace does not retitle"
        )

        try await store.replaceTranscript(
            for: vm.id,
            with: [.userMessage(id: "u-reload", text: "通知を修正", timestamp: Date())]
        )
        await vm.restore(
            threadId: threadId,
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        try await waitUntil { vm.restoreState == .restored }
        expectState(
            vm.titleState,
            derived.name,
            .derived,
            "Rose",
            "ログイン画面を修正",
            "reload does not retitle"
        )

        _ = await vm.revert(toUserMessageID: userID)
        expectState(
            vm.titleState,
            derived.name,
            .derived,
            "Rose",
            "ログイン画面を修正",
            "revert does not retitle"
        )
    }

    @Test @MainActor
    func 復元待機中のrenameは適格履歴の解放後も手動名を保持する() async throws {
        let store = TitleLifecycleTranscriptStore([
            .userMessage(id: "hist-1", text: "ログイン画面を修正", timestamp: Date()),
        ])
        store.shouldGateLoad = true
        let (vm, _) = makeChatVM(transcriptStore: store)
        let restoreTask = Task { @MainActor in
            await vm.restore(
                threadId: "thread-wait",
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
        }
        await store.waitUntilLoadEntered()
        vm.name = "通知を修正"
        expectState(vm.titleState, "通知を修正", .manual, "Rose", nil, "rename during restore")
        store.releaseLoad()
        await restoreTask.value
        expectState(vm.titleState, "通知を修正", .manual, "Rose", nil, "manual after await")
    }

    @Test @MainActor
    func 復元待機中のderivedは適格履歴の解放後も導出名を保持する() async throws {
        let derived = SessionTitleState(
            name: "ログイン画面を修正",
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "ログイン画面を修正"
        )
        let client = TitleCodexClient()
        client.shouldGateThreadRead = true
        client.threadReadItemsJSON = "[\(identifiedPlainJSON(id: "srv-later", text: "通知を修正"))]"
        let (vm, _) = makeCodexVM(titleState: derived, client: client)
        let restoreTask = Task { @MainActor in
            await vm.restore(
                threadId: "thread-derived-wait",
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
        }
        await client.waitUntilThreadReadEntered()
        expectState(
            vm.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "derived during gated read"
        )
        client.releaseThreadRead()
        await restoreTask.value
        expectState(
            vm.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "derived after gated read"
        )
    }

    @Test @MainActor
    func 状態復元_flower_derived_manual_空名を保持する() async throws {
        let flowerStore = TitleLifecycleTranscriptStore()
        let (flowerVM, _) = makeChatVM(
            titleState: .generated(flowerName: "Rose"),
            transcriptStore: flowerStore
        )
        await flowerVM.restore(
            threadId: "t-flower",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        expectState(flowerVM.titleState, "Rose", .flower, "Rose", nil, "restore flower")

        let derivedState = SessionTitleState(
            name: "ログイン画面を修正",
            source: .derived,
            flowerName: "Rose",
            fullDerivedTitle: "ログイン画面を修正"
        )
        let (derivedVM, _) = makeChatVM(titleState: derivedState)
        await derivedVM.restore(
            threadId: "t-derived",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        expectState(
            derivedVM.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "restore derived"
        )

        let (manualVM, _) = makeChatVM(
            titleState: SessionTitleState.legacy(name: " 手動\n名 ")
        )
        await manualVM.restore(
            threadId: "t-manual",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        expectState(manualVM.titleState, " 手動\n名 ", .manual, nil, nil, "restore manual")

        let (emptyVM, _) = makeChatVM(titleState: .legacy(name: ""))
        await emptyVM.restore(
            threadId: "t-empty",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        expectState(emptyVM.titleState, "", .manual, nil, nil, "restore empty")
        #expect(emptyVM.displayName == SessionViewModel.shortID(for: emptyVM.id))
    }

    @Test @MainActor
    func ローカル履歴の識別可能本文は採用しサーバー履歴とは分離する() async throws {
        let store = TitleLifecycleTranscriptStore([
            .userMessage(id: "local-1", text: "ログイン画面を修正", timestamp: Date()),
        ])
        let (vm, _) = makeChatVM(transcriptStore: store)
        await vm.restore(
            threadId: "thread-local",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        expectState(
            vm.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "local history original"
        )
    }

    @Test @MainActor
    func ローカル履歴なしのthreadReadで由来の無い同一本文はflowerのまま() async throws {
        let client = TitleCodexClient()
        client.threadReadItemsJSON = "[\(unidentifiedSupplementJSON(id: "srv-1"))]"
        let (vm, _) = makeCodexVM(client: client)
        await vm.restore(
            threadId: "thread-unidentified",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        try await waitUntil { vm.restoreState == .restored || vm.restoreState != .restoring }
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "unidentified server history")
    }

    @Test @MainActor
    func 同一本文でもoriginalTextがあればサーバー履歴からログイン画面を修正を採用できる() async throws {
        let client = TitleCodexClient()
        client.threadReadItemsJSON = "[\(identifiedOriginalJSON(id: "srv-2", originalText: "ログイン画面を修正"))]"
        let (vm, _) = makeCodexVM(client: client)
        await vm.restore(
            threadId: "thread-identifiable",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        try await waitUntil { vm.restoreState == .restored }
        expectState(
            vm.titleState,
            "ログイン画面を修正",
            .derived,
            "Rose",
            "ログイン画面を修正",
            "identifiable server history"
        )
    }

    @Test @MainActor
    func 由来不能項目の後の由来ある通知を修正をthreadReadで採用する() async throws {
        let client = TitleCodexClient()
        client.threadReadItemsJSON = """
        [\(unidentifiedSupplementJSON(id: "bad")),\
        {"id":"a","type":"agentMessage","text":"作業します"},\
        \(identifiedPlainJSON(id: "good", text: "通知を修正"))]
        """
        let (vm, _) = makeCodexVM(client: client)
        await vm.restore(
            threadId: "thread-skip",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        try await waitUntil { vm.restoreState == .restored }
        expectState(
            vm.titleState,
            "通知を修正",
            .derived,
            "Rose",
            "通知を修正",
            "skip then adopt"
        )
    }

    @Test @MainActor
    func サーバー履歴でoriginalTextが_review_なら補足を候補にしない() async throws {
        let client = TitleCodexClient()
        client.threadReadItemsJSON = "[\(identifiedOriginalJSON(id: "srv-review", originalText: "/review"))]"
        let (vm, _) = makeCodexVM(client: client)
        await vm.restore(
            threadId: "thread-review-original",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        try await waitUntil { vm.restoreState == .restored || vm.restoreState != .restoring }
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "identifiable /review original")
    }

    @Test @MainActor
    func PTY_の_sendText_と直接入力は導出しない() async throws {
        let vm = await makePTYVM()
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "pty start")
        try await vm.sendText("ログイン画面を修正", submit: true)
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "pty sendText")
        await vm.sendInput(Data("通知を修正".utf8))
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "pty sendInput")
        #expect(SessionNode.pty(vm).titleState.source == .flower)
        vm.name = "通知を修正"
        expectState(vm.titleState, "通知を修正", .manual, "Rose", nil, "pty rename")
    }
}
