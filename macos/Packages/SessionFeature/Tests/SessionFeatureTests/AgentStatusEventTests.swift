import Foundation
import Testing
import AgentDomain
import StructuredChatKit
import CodexAppServerKit
@testable import SessionFeature

// エージェント状態カードが読む会話ログの書き込み（agent-status-card-design.md §3.1〜3.4）。
// 作業の終了時刻・Bash の説明・タスクの追記・入力ごとの終わり方（turnEnd）。

// MARK: - ハーネス

private final class StatusFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        if failTurnStart { throw StatusFakeError.sendFailed }
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }

    /// 次の送信を失敗させる（CLI へ書き込めなかった状況）。
    var failTurnStart = false
}

private enum StatusFakeError: Error { case sendFailed }

private enum WaitError: Error { case timedOut }

@MainActor
private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(2)
    while !condition() {
        guard ContinuousClock.now < deadline else { throw WaitError.timedOut }
        try await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private func makeViewModel() -> (ChatSessionViewModel, StatusFakeClient) {
    let client = StatusFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-agent-status-event-test"
    )
    return (vm, client)
}

@MainActor
private func command(_ vm: ChatSessionViewModel, _ id: String) -> (completedAt: Date?, intent: String?, output: String)? {
    for item in vm.transcript {
        if case .commandExecution(id, _, let output, _, let completedAt, let intent) = item {
            return (completedAt, intent, output)
        }
    }
    return nil
}

@MainActor
private func fileChangeCompletedAt(_ vm: ChatSessionViewModel, _ id: String) -> Date?? {
    for item in vm.transcript {
        if case .fileChange(id, _, _, let completedAt) = item { return .some(completedAt) }
    }
    return nil
}

@MainActor
private func turnEnds(_ vm: ChatSessionViewModel) -> [String] {
    vm.transcript.compactMap { item in
        if case .userMessage(_, _, _, _, let turnEnd) = item { return turnEnd?.outcome.rawValue ?? "none" }
        return nil
    }
}

@MainActor
private func snapshots(_ vm: ChatSessionViewModel) -> [(id: String, titles: [String])] {
    vm.transcript.compactMap {
        if case .taskList(let id, let tasks, _) = $0 { return (id, tasks.map(\.title)) }
        return nil
    }
}

/// `.warning(message: "barrier")` を流した後、それまでの通知が処理済みだと分かる印。
@MainActor
private func hasBarrier(_ vm: ChatSessionViewModel) -> Bool {
    vm.transcript.contains { if case .error(_, "barrier", _) = $0 { true } else { false } }
}

private func tasks(_ titles: String...) -> [AgentTaskItem] {
    titles.enumerated().map { AgentTaskItem(id: "t\($0.offset)", title: $0.element, status: .pending) }
}

// MARK: - 作業の終了時刻（.itemCompleted）

@Test @MainActor
func itemCompletedStampsTheCommandOnlyOnceItsResultArrives() async throws {
    let (vm, client) = makeViewModel()
    client.yield(.commandExecution(itemId: "c1", command: "swift test", outputDelta: ""))
    try await waitUntil { command(vm, "c1") != nil }
    #expect(command(vm, "c1")?.completedAt == nil, "結果が届く前は実行中")

    client.yield(.commandExecution(itemId: "c1", command: nil, outputDelta: "all passed"))
    client.yield(.itemCompleted(itemId: "c1"))
    try await waitUntil { command(vm, "c1")?.completedAt != nil }

    #expect(command(vm, "c1")?.output == "all passed", "結果の出力は終了時刻より先に反映される")
}

@Test @MainActor
func itemCompletedStampsAFileChange() async throws {
    let (vm, client) = makeViewModel()
    client.yield(.fileChange(itemId: "f1", [StructuredChatKit.FilePatchChange(path: "api.swift", diff: "+x", kind: "update")]))
    try await waitUntil { fileChangeCompletedAt(vm, "f1") != nil }
    #expect(fileChangeCompletedAt(vm, "f1") == .some(nil), "結果が届く前は実行中")

    client.yield(.itemCompleted(itemId: "f1"))
    try await waitUntil { fileChangeCompletedAt(vm, "f1") != .some(nil) }

    let completedAt = try #require(fileChangeCompletedAt(vm, "f1") ?? nil)
    #expect(completedAt >= vm.transcript[0].timestamp, "終了は開始より後")
}

@Test @MainActor
func itemCompletedKeepsTheFirstCompletionTime() async throws {
    let (vm, client) = makeViewModel()
    client.yield(.commandExecution(itemId: "c1", command: "ls", outputDelta: ""))
    client.yield(.itemCompleted(itemId: "c1"))
    try await waitUntil { command(vm, "c1")?.completedAt != nil }
    let first = command(vm, "c1")?.completedAt

    try await Task.sleep(for: .milliseconds(20))
    client.yield(.itemCompleted(itemId: "c1"))
    client.yield(.warning(message: "barrier"))
    try await waitUntil { vm.transcript.count == 2 }

    #expect(command(vm, "c1")?.completedAt == first)
}

@Test @MainActor
func itemCompletedForUnknownItemChangesNothing() async throws {
    let (vm, client) = makeViewModel()
    client.yield(.itemCompleted(itemId: "ghost"))
    client.yield(.warning(message: "barrier"))
    try await waitUntil { vm.transcript.count == 1 }

    #expect(command(vm, "ghost") == nil)
}

// MARK: - Bash の説明（intent）

@Test @MainActor
func commandIntentIsKeptWhenOutputAndCompletionArrive() async throws {
    let (vm, client) = makeViewModel()
    client.yield(.commandExecution(itemId: "c1", command: "swift test", outputDelta: "", intent: "テストを実行する"))
    try await waitUntil { command(vm, "c1") != nil }
    #expect(command(vm, "c1")?.intent == "テストを実行する")

    client.yield(.commandExecution(itemId: "c1", command: nil, outputDelta: "all passed"))
    client.yield(.itemCompleted(itemId: "c1"))
    try await waitUntil { command(vm, "c1")?.completedAt != nil }

    #expect(command(vm, "c1")?.intent == "テストを実行する")
    #expect(command(vm, "c1")?.output == "all passed")
}

// MARK: - タスクの追記

@Test @MainActor
func taskListUpdatesAreAppendedWithUniqueIDs() async throws {
    let (vm, client) = makeViewModel()
    client.yield(.taskListUpdated(tasks: tasks("調査する")))
    client.yield(.taskListUpdated(tasks: tasks("調査する", "実装する")))
    try await waitUntil { snapshots(vm).count == 2 }

    let cards = snapshots(vm)
    #expect(cards.map(\.titles) == [["調査する"], ["調査する", "実装する"]], "上書きせず、経過が残る")
    #expect(cards.allSatisfy { $0.id.hasPrefix("task-list-") })
    #expect(Set(cards.map(\.id)).count == 2)
}

@Test @MainActor
func identicalTaskListWithinTheSameInputIsNotAppendedAgain() async throws {
    let (vm, client) = makeViewModel()
    client.yield(.taskListUpdated(tasks: tasks("調査する")))
    client.yield(.taskListUpdated(tasks: tasks("調査する")))
    client.yield(.warning(message: "barrier"))
    try await waitUntil { vm.transcript.count == 2 }

    #expect(snapshots(vm).count == 1)
}

@Test @MainActor
func sameTaskListInANewInputIsAppendedAgain() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    client.yield(.taskListUpdated(tasks: tasks("調査する")))
    try await waitUntil { snapshots(vm).count == 1 }
    try await vm.sendText("次", submit: true)

    client.yield(.taskListUpdated(tasks: tasks("調査する")))
    try await waitUntil { snapshots(vm).count == 2 }

    #expect(snapshots(vm).count == 2, "前の入力の最後と同じでも、新しい入力の基準として記録する")
}

// MARK: - 入力の終わり方（turnEnd）

@Test @MainActor
func completedTurnMarksTheInputCompleted() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("直して", submit: true)
    #expect(turnEnds(vm) == ["none"], "実行中は終わり方が無い")

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["completed"] }

    guard case .userMessage(_, _, let timestamp, _, let turnEnd) = vm.transcript[0] else {
        Issue.record("userMessage が無い")
        return
    }
    #expect(try #require(turnEnd).at >= timestamp)
}

@Test @MainActor
func interruptedTurnMarksTheInputInterrupted() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("直して", submit: true)

    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["interrupted"] }
}

@Test @MainActor
func errorMarksTheInputError() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("直して", submit: true)

    client.yield(.error(message: "boom"))
    try await waitUntil { turnEnds(vm) == ["error"] }
    #expect(vm.status == .error(message: "boom"), "今の `.error` は実行中の状態を終える。だからターンの終わりとして数える")
}

@Test @MainActor
func processExitDuringATurnMarksTheInputError() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("直して", submit: true)

    client.yield(.processExited(exitCode: 137))
    try await waitUntil { turnEnds(vm) == ["error"] }
}

private struct LegacyTranscriptStore: TranscriptStore {
    let items: [ChatItem]
    func loadSessionTotalCost(for sessionID: SessionID) async throws -> SessionTotalCost? { nil }
    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] { items }
    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {}
    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {}
    func saveTurnUsageSnapshot(_ usage: TurnUsage, for sessionID: SessionID) async throws {}
}

/// この機能より前に保存された会話（`turnEnd` が無い入力）を復元した直後。
@MainActor
private func restoredLegacyViewModel() async -> (ChatSessionViewModel, StatusFakeClient) {
    let client = StatusFakeClient()
    let legacy: [ChatItem] = [
        .userMessage(id: "u1", text: "昔の入力", timestamp: Date(timeIntervalSince1970: 1_700_000_000), attachments: []),
        .agentMessage(id: "a1", text: "はい", timestamp: Date(timeIntervalSince1970: 1_700_000_001)),
    ]
    let vm = ChatSessionViewModel(
        id: SessionID(), agentRef: .builtin(.claudeCode), client: client,
        approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/phlox-agent-status-event-test",
        transcriptStore: LegacyTranscriptStore(items: legacy)
    )
    await vm.restore(threadId: "thread", approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    return (vm, client)
}

@Test @MainActor
func processExitDoesNotStampARestoredInputThatWasNotRunning() async throws {
    let (vm, client) = await restoredLegacyViewModel()
    #expect(turnEnds(vm) == ["none"])

    client.yield(.processExited(exitCode: 1))
    try await waitUntil { vm.processExit != nil }

    #expect(turnEnds(vm) == ["none"], "この機能より前の入力を、後から届いた終了でエラーにしない")
}

@Test @MainActor
func errorDoesNotStampARestoredInputThatWasNotRunning() async throws {
    let (vm, client) = await restoredLegacyViewModel()

    client.yield(.error(message: "boom"))
    try await waitUntil { vm.status == .error(message: "boom") }

    #expect(turnEnds(vm) == ["none"])
}

@Test @MainActor
func sendingWhileRunningMarksThePreviousInputSuperseded() async throws {
    let (vm, _) = makeViewModel()
    try await vm.sendText("最初", submit: true)

    try await vm.sendText("次", submit: true)

    #expect(turnEnds(vm) == ["superseded", "none"])
}

@Test @MainActor
func sendingAfterTheTurnCompletedDoesNotRewriteThePreviousEnd() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["completed"] }

    try await vm.sendText("次", submit: true)

    #expect(turnEnds(vm) == ["completed", "none"])
}

@Test @MainActor
func aTurnEndThatIsAlreadyRecordedIsNotOverwritten() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("直して", submit: true)
    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["interrupted"] }

    client.yield(.turnCompleted(nativeSessionId: nil))
    client.yield(.processExited(exitCode: 1))
    try await waitUntil { vm.processExit != nil }

    #expect(turnEnds(vm) == ["interrupted"])
}

@Test @MainActor
func turnEndIsWrittenOnTheLatestInputOnly() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["completed"] }
    try await vm.sendText("次", submit: true)

    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["completed", "interrupted"] }
}

// MARK: - Codex の終了時刻

private actor CodexStatusClient: StructuredAgentClient, CodexOrderedEventsProviding {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let orderedEvents: AsyncStream<CodexStructuredEvent>
    nonisolated let continuation: AsyncStream<CodexStructuredEvent>.Continuation
    private let normalizedContinuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        (events, normalizedContinuation) = AsyncStream.makeStream()
        (orderedEvents, continuation) = AsyncStream.makeStream()
    }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish(); normalizedContinuation.finish() }
}

private func threadItem(_ json: String) throws -> ThreadItem {
    try JSONDecoder().decode(ThreadItem.self, from: Data(json.utf8))
}

// MARK: - 実行中の再送信の後に遅れて届く終了
//
// 実行中に次の入力 B を送ると前の入力 A は superseded で閉じる。その後に届く終了は、届いた順に
// 「A の終わり」として吸収し、B には書かない。B の終わりは B のターンの終わりで書く。
// 根拠: Claude の通知は turn を識別できない（ADR 0222）。Codex の入力欄の送信は常に turn/start で、
// turn/steer は非同期の質問への回答（userMessage を足さない）にしか使わない。
// 実 CLI が B を A に合流させて result を 1 件しか返すかどうかは未確認。その場合は B の終わりが
// 書かれず、見出しは「終了」（終わり方の記録なし）になる。

@Test @MainActor
func lateCompletionOfASupersededInputDoesNotEndTheNewInput() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    try await vm.sendText("次", submit: true)

    client.yield(.turnCompleted(nativeSessionId: nil))
    client.yield(.warning(message: "barrier"))
    try await waitUntil { vm.transcript.count == 3 }
    #expect(turnEnds(vm) == ["superseded", "none"], "前の入力の完了は新しい入力に書かない")

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["superseded", "completed"] }
}

@Test @MainActor
func lateErrorOfASupersededInputDoesNotEndTheNewInput() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    try await vm.sendText("次", submit: true)

    client.yield(.error(message: "boom"))
    client.yield(.warning(message: "barrier"))
    try await waitUntil { vm.transcript.count == 4 }
    #expect(turnEnds(vm) == ["superseded", "none"])
}

@Test @MainActor
func singleCompletionAfterASupersedeLeavesTheNewInputWithoutAnEnd() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    try await vm.sendText("次", submit: true)

    client.yield(.turnCompleted(nativeSessionId: nil))
    client.yield(.warning(message: "barrier"))
    try await waitUntil { vm.transcript.count == 3 }

    #expect(turnEnds(vm) == ["superseded", "none"], "合流して 1 件だけ届いた場合は、B の終わりを推測しない（終了と表示される）")
}

@Test @MainActor
func processExitAfterASupersedeEndsTheNewInputWithError() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    try await vm.sendText("次", submit: true)

    client.yield(.processExited(exitCode: 137))
    try await waitUntil { turnEnds(vm) == ["superseded", "error"] }
}

@Test @MainActor
func userInterruptAfterASupersedeEndsTheNewInputAsInterrupted() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    try await vm.sendText("次", submit: true)
    await vm.turnInterrupt()

    client.yield(.turnInterrupted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["superseded", "interrupted"] }
}

@Test @MainActor
func lateInterruptionOfASupersededCodexInputDoesNotEndTheNewInput() async throws {
    let client = CodexStatusClient()
    let vm = ChatSessionViewModel(
        id: SessionID(), agentRef: .builtin(.codex), client: client,
        approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/phlox-agent-status-event-test"
    )
    await vm.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
    try await vm.sendText("最初", submit: true)
    try await vm.sendText("次", submit: true)

    client.continuation.yield(.normalized(.turnInterrupted(nativeSessionId: "thread")))
    client.continuation.yield(.normalized(.warning(message: "barrier")))
    try await waitUntil { vm.transcript.count == 3 }
    #expect(turnEnds(vm) == ["superseded", "none"], "A の中断は新しい入力に書かない")

    client.continuation.yield(.normalized(.turnCompleted(nativeSessionId: "thread")))
    try await waitUntil { turnEnds(vm) == ["superseded", "completed"] }
    await vm.terminate()
}

@Test @MainActor
func errorAfterAnAbsorbedCompletionEndsTheNewInputWithError() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    try await vm.sendText("次", submit: true)

    client.yield(.turnCompleted(nativeSessionId: nil))
    client.yield(.error(message: "boom"))
    try await waitUntil { turnEnds(vm) == ["superseded", "error"] }
}

@Test @MainActor
func processExitAfterAnAbsorbedCompletionEndsTheNewInputWithError() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)
    try await vm.sendText("次", submit: true)

    client.yield(.turnCompleted(nativeSessionId: nil))
    client.yield(.processExited(exitCode: 137))
    try await waitUntil { turnEnds(vm) == ["superseded", "error"] }
}

@Test @MainActor
func eachEndOfASupersededInputIsAbsorbedEvenWhenTheTurnWasAlreadyCleared() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("一", submit: true)
    try await vm.sendText("二", submit: true)
    try await vm.sendText("三", submit: true)

    client.yield(.turnCompleted(nativeSessionId: nil))
    client.yield(.error(message: "boom"))
    client.yield(.warning(message: "barrier"))
    try await waitUntil { hasBarrier(vm) }
    #expect(turnEnds(vm) == ["superseded", "superseded", "none"], "一の完了と二のエラーは、それぞれの入力の終わりとして吸収する")

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["superseded", "superseded", "completed"] }
}

// MARK: - 送信に失敗したとき

@Test @MainActor
func failedSendDoesNotMarkThePreviousInputSuperseded() async throws {
    let (vm, client) = makeViewModel()
    try await vm.sendText("最初", submit: true)

    client.failTurnStart = true
    await #expect(throws: StatusFakeError.self) { try await vm.sendText("次", submit: true) }

    #expect(turnEnds(vm) == ["none", "none"], "届かなかった入力に続くとは言わない")
    client.failTurnStart = false
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { turnEnds(vm) == ["completed", "none"] }
}

// MARK: - Codex の計画（AC-13）

@Test @MainActor
func codexPlanAppearsAsTasksOfTheStatusCard() async throws {
    let client = CodexStatusClient()
    let vm = ChatSessionViewModel(
        id: SessionID(), agentRef: .builtin(.codex), client: client,
        approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/phlox-agent-status-event-test"
    )
    await vm.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
    try await vm.sendText("直して", submit: true)
    let plan = ThreadEvent.planUpdated(
        threadId: "thread", turnId: "turn",
        plan: [
            TurnPlanStep(step: "調査する", status: .completed),
            TurnPlanStep(step: "実装する", status: .inProgress),
            TurnPlanStep(step: "検証する", status: .pending),
        ],
        explanation: nil
    )
    let normalized = try #require(CodexStructuredAgentClient.normalizedEvent(from: plan))

    client.continuation.yield(.normalized(normalized))
    try await waitUntil { vm.transcript.contains { if case .taskList = $0 { true } else { false } } }

    let cards = AgentStatusCardBuilder.build(
        items: vm.transcript,
        liveState: AgentStatusLiveState(isProcessing: true, activityState: .thinking, hangAssessment: nil, isAwaitingReply: false)
    ).compactMap { block -> AgentStatusCard? in if case .statusCard(let card) = block { card } else { nil } }
    let tasks = cards.flatMap(\.rows).compactMap { row -> AgentStatusTask? in if case .task(let task) = row { task } else { nil } }
    #expect(cards.count == 1)
    #expect(tasks.map(\.title) == ["調査する", "実装する", "検証する"])
    #expect(tasks.map(\.state) == [.completed, .inProgress, .pending])
    await vm.terminate()
}

@Test @MainActor
func codexItemCompletedStampsCommandAndFileChange() async throws {
    let client = CodexStatusClient()
    let vm = ChatSessionViewModel(
        id: SessionID(), agentRef: .builtin(.codex), client: client,
        approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp/phlox-agent-status-event-test"
    )
    await vm.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
    let startedCommand = try threadItem(#"{"id":"cmd","type":"commandExecution","command":"pwd"}"#)
    let doneCommand = try threadItem(#"{"id":"cmd","type":"commandExecution","command":"pwd","aggregatedOutput":"ok"}"#)
    let doneFile = try threadItem(#"{"id":"file","type":"fileChange","changes":[{"path":"api.swift","kind":{"type":"update"},"diff":"+x"}]}"#)

    client.continuation.yield(.thread(.itemStarted(threadId: "thread", turnId: "turn", item: startedCommand)))
    try await waitUntil { command(vm, "cmd") != nil }
    #expect(command(vm, "cmd")?.completedAt == nil, "開始の通知では終了時刻を書かない")

    client.continuation.yield(.thread(.itemCompleted(threadId: "thread", turnId: "turn", item: doneCommand)))
    client.continuation.yield(.thread(.itemCompleted(threadId: "thread", turnId: "turn", item: doneFile)))
    try await waitUntil { command(vm, "cmd")?.completedAt != nil && fileChangeCompletedAt(vm, "file") != nil }

    #expect(command(vm, "cmd")?.output == "ok")
    #expect(fileChangeCompletedAt(vm, "file") != .some(nil))
    await vm.terminate()
}
