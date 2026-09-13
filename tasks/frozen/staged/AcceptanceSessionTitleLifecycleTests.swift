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

import Foundation
import Testing
import AgentDomain
import PTYKit
import StructuredChatKit
import TerminalUI
@testable import SessionFeature

private final class TitleLifecycleClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let lock = NSLock()
    private var turnStartInputs: [[ChatInput]] = []
    var turnStartError: Error?
    var shouldGateResume = false
    var resumeContinuation: CheckedContinuation<Void, Never>?

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

    func resume(sessionRef: String) async throws {
        guard shouldGateResume else { return }
        await withCheckedContinuation { continuation in
            resumeContinuation = continuation
        }
    }

    func releaseResume() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func interrupt() async throws {}
    func close() async { continuation.finish() }
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

    init(_ items: [ChatItem] = []) {
        self.items = items
    }

    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] {
        lock.withLock { items }
    }

    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        lock.withLock {
            self.items.append(contentsOf: items)
        }
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
    func ローカル確定後の通信失敗でも導出名を保持する() async throws {
        let client = TitleLifecycleClient()
        client.turnStartError = TitleTurnStartFailure()
        let (vm, _) = makeChatVM(client: client)
        do {
            try await vm.sendText("ログイン画面を修正", submit: true)
        } catch is TitleTurnStartFailure {
        }
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
        let (vm, client) = makeChatVM()
        client.yield(.agentMessageDelta(itemId: "a1", "ログイン画面を修正"))
        client.yield(.commandExecution(itemId: "t1", command: "ls", outputDelta: "通知を修正"))
        client.yield(.error(message: "ログイン画面を修正"))
        client.yield(.userQuestionRequested(
            requestId: "q1",
            questions: [
                ChatUserQuestion(
                    question: "ログイン画面を修正しますか",
                    header: "確認",
                    options: [ChatUserQuestionOption(label: "はい")],
                    multiSelect: false
                ),
            ]
        ))
        client.yield(.subAgentOutput(toolUseId: "s1", text: "通知を修正"))
        try await waitUntil { vm.transcript.isEmpty == false || vm.status == .idle }
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "out of scope")
    }

    @Test @MainActor
    func ローカル_review_の補足付き送信文字列をサーバー開始完了で返してもflowerのまま() async throws {
        let (vm, client) = makeChatVM()
        try await vm.sendText("/review", submit: true)
        client.yield(.turnStarted)
        client.yield(.agentMessageDelta(itemId: "a1", "ログイン画面を修正"))
        client.yield(.turnCompleted(nativeSessionId: "thread-1"))
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "/review plus supplement")
    }

    @Test @MainActor
    func ローカル本文と対応付くサーバー反映はローカル元本文を使い補足で先に確定しない() async throws {
        let (vm, client) = makeChatVM()
        try await vm.sendText("ログイン画面を修正", submit: true)
        client.yield(.turnStarted)
        client.yield(.agentMessageDelta(itemId: "a1", "/review\nログイン画面を修正"))
        client.yield(.turnCompleted(nativeSessionId: "thread-1"))
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
    func 確定後の置換と巻き戻しは名前を変更しない() async throws {
        let store = TitleLifecycleTranscriptStore()
        let (vm, _) = makeChatVM(transcriptStore: store)
        try await vm.sendText("ログイン画面を修正", submit: true)
        let derived = vm.titleState
        try await store.replaceTranscript(
            for: vm.id,
            with: [.userMessage(id: "u2", text: "通知を修正", timestamp: Date())]
        )
        let restored = try await store.loadTranscript(for: vm.id)
        #expect(restored.contains { item in
            if case .userMessage(_, "通知を修正", _, _) = item { return true }
            return false
        })
        expectState(
            vm.titleState,
            derived.name,
            .derived,
            "Rose",
            "ログイン画面を修正",
            "replace does not retitle"
        )
    }

    @Test @MainActor
    func 復元待機中のrenameはawait後も手動名を保持する() async throws {
        let client = TitleLifecycleClient()
        client.shouldGateResume = true
        let (vm, _) = makeChatVM(client: client)
        let restoreTask = Task { @MainActor in
            await vm.restore(
                threadId: "thread-wait",
                approvalPolicy: .named("on-request"),
                sandbox: .named("workspace-write")
            )
        }
        try await waitUntil { client.resumeContinuation != nil }
        vm.name = "通知を修正"
        expectState(vm.titleState, "通知を修正", .manual, "Rose", nil, "rename during restore")
        client.releaseResume()
        await restoreTask.value
        expectState(vm.titleState, "通知を修正", .manual, "Rose", nil, "manual after await")
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
    func ローカル履歴なしのサーバー復元で補足付き文字列を識別できなければflowerのまま() async throws {
        let unidentified = ChatItem.userMessage(
            id: "srv-1",
            text: "/review\nログイン画面を修正",
            timestamp: Date()
        )
        let store = TitleLifecycleTranscriptStore([unidentified])
        let (vm, _) = makeChatVM(transcriptStore: store)
        await vm.restore(
            threadId: "thread-unidentified",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
        expectState(vm.titleState, "Rose", .flower, "Rose", nil, "unidentified server history")
    }

    @Test @MainActor
    func 元本文が独立して識別できるサーバー履歴のログイン画面を修正は採用できる() async throws {
        let identifiable = ChatItem.userMessage(
            id: "srv-2",
            text: "ログイン画面を修正",
            timestamp: Date()
        )
        let store = TitleLifecycleTranscriptStore([identifiable])
        let (vm, _) = makeChatVM(transcriptStore: store)
        await vm.restore(
            threadId: "thread-identifiable",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
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
    func 識別不能項目の後の識別可能な通知を修正を採用する() async throws {
        let items: [ChatItem] = [
            .userMessage(id: "bad", text: "/review\nログイン画面を修正", timestamp: Date()),
            .agentMessage(id: "a", text: "作業します", timestamp: Date()),
            .userMessage(id: "good", text: "通知を修正", timestamp: Date()),
        ]
        let store = TitleLifecycleTranscriptStore(items)
        let (vm, _) = makeChatVM(transcriptStore: store)
        await vm.restore(
            threadId: "thread-skip",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
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
