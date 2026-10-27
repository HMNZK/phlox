import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite("Async question notifications")
@MainActor
struct AsyncQuestionNotificationTests {
    @Test("実wire形式の質問は実行を止めず通知し、再送は重複しない")
    func liveQuestions() async throws {
        try await withSession { vm, wire, notifications in
            try wire.turnStarted()
            try await wait { vm.status == .running }
            try wire.question("q1", method: "item/started")
            try wire.question("q1")
            try wire.question("q1")
            try wire.question("q2")
            try wire.barrier("received")
            try await wait { vm.transcript.last?.id == "received" }
            #expect(notifications.approvalPendingCalls.count == 2)
            #expect(vm.status == .running)
            #expect(vm.displayStatus == .awaitingUserQuestion)
            #expect(vm.showsProcessingIndicator)
            let cards = vm.transcript.filter { if case .userQuestion = $0 { true } else { false } }
            #expect(cards.count == 2)
            if case .userQuestion(_, _, _, _, _, let timestamp) = cards[0] {
                #expect(SessionNode.appServer(vm).statusEnteredAt == timestamp)
            }
            #expect(!vm.transcript.contains { $0.id == "q1" || $0.id == "q2" })
            let first = try #require(pendingRequestID(vm))
            #expect(await vm.declineUserQuestion(requestId: first))
            #expect(vm.displayStatus == .awaitingUserQuestion)
            if case .userQuestion(_, _, _, _, _, let timestamp) = cards[1] {
                #expect(SessionNode.appServer(vm).statusEnteredAt == timestamp)
            }
        }
    }

    @Test("過去・別thread・終了後の質問は通知せず、新しいturnは通知する")
    func historyAndIdentity() async throws {
        try await withSession { vm, wire, notifications in
            try wire.question("history")
            try wire.barrier("history-received")
            try await wait { vm.transcript.last?.id == "history-received" }
            #expect(notifications.approvalPendingCalls.isEmpty)

            try wire.turnStarted()
            try await wait { vm.status == .running }
            try wire.question("wrong-thread", thread: "other")
            try wire.question("wrong-turn", turn: "past")
            try wire.barrier("identity-checked")
            try await wait { vm.transcript.last?.id == "identity-checked" }
            #expect(notifications.approvalPendingCalls.isEmpty)

            try wire.question("q1")
            try wire.barrier("live-received")
            try await wait { vm.transcript.last?.id == "live-received" }
            #expect(notifications.approvalPendingCalls.count == 1)
            try wire.turnCompleted()
            try await wait { vm.status == .idle }
            try wire.question("late")
            try wire.turnStarted(turn: "next")
            try wire.question("q1", turn: "next")
            try wire.barrier("next-received", turn: "next")
            try await wait { vm.transcript.last?.id == "next-received" }
            #expect(notifications.approvalPendingCalls.count == 2)
        }
    }

    @Test("到達性ゲートで禁止したモバイル通知は送らない")
    func remoteGate() async throws {
        try await withSession { vm, wire, notifications in
            vm.userNotificationGate = { _ in false }
            try wire.turnStarted()
            try wire.question("q1")
            try wire.barrier("gated")
            try await wait { vm.transcript.last?.id == "gated" }
            #expect(notifications.approvalPendingCalls.isEmpty)
            #expect(vm.status == .running)
        }
    }

    @Test("実行中の会話を復元した後も新しい質問は通知し、履歴は再通知しない")
    func resumedActiveTurn() async throws {
        try await withSession(restoresActive: true) { vm, wire, notifications in
            #expect(vm.status == .running)
            #expect(vm.transcript.contains { if case .userQuestion(_, _, _, _, .expired, _) = $0 { true } else { false } })
            #expect(notifications.approvalPendingCalls.isEmpty)
            try wire.question("history")
            try wire.question("new-question")
            try wire.barrier("restored-live")
            try await wait { vm.transcript.last?.id == "restored-live" }
            #expect(notifications.approvalPendingCalls.count == 1)
            #expect(vm.status == .running)
        }
    }

    @Test("復元直後に過去turnが先に届いても、現在turnの質問を妨げない")
    func restoredTurnIdentity() async throws {
        try await withSession(restoresActive: true) { vm, wire, notifications in
            try wire.question("late-old-question", turn: "past")
            try wire.barrier("past-checked")
            try await wait { vm.transcript.last?.id == "past-checked" }
            #expect(notifications.approvalPendingCalls.isEmpty)
            try wire.question("current-question")
            try wire.barrier("current-checked")
            try await wait { vm.transcript.last?.id == "current-checked" }
            #expect(notifications.approvalPendingCalls.count == 1)
        }
    }

    @Test("履歴と同じitem IDでも、別turnの新しい質問は通知する")
    func itemIDIsScopedToTurn() async throws {
        try await withSession(restoresActive: true) { vm, wire, notifications in
            try wire.turnCompleted()
            try await wait { vm.status == .idle }
            try wire.turnStarted(turn: "next")
            try wire.question("history", turn: "next")
            try wire.barrier("next-checked", turn: "next")
            try await wait { vm.transcript.last?.id == "next-checked" }
            #expect(notifications.approvalPendingCalls.count == 1)
        }
    }

    @Test("本文が空で描画されない履歴質問も再通知しない")
    func emptyHistoryText() async throws {
        try await withSession(restoresActive: true, historyText: "") { vm, wire, notifications in
            try wire.question("history")
            try wire.barrier("empty-checked")
            try await wait { vm.transcript.last?.id == "empty-checked" }
            #expect(notifications.approvalPendingCalls.isEmpty)
        }
    }

    @Test("表示中でも質問と承認の通知を省略しない")
    func visibleSessionPolicy() {
        #expect(!SessionCompletionNotifier.shouldSuppressWhileShowing(.awaitingQuestion(question: "続けますか？", isSecret: false)))
        #expect(!SessionCompletionNotifier.shouldSuppressWhileShowing(.awaitingApproval(prompt: "実行許可")))
        #expect(SessionCompletionNotifier.shouldSuppressWhileShowing(.completed))
    }

    @Test("非同期回答を進行ターンへ送り、下書きと実行状態を維持する")
    func answersRunningQuestion() async throws {
        try await withSession { vm, wire, _ in
            try wire.turnStarted()
            try wire.question("answer")
            try wire.barrier("answer-ready")
            try await wait { vm.transcript.last?.id == "answer-ready" }
            let requestID = try #require(pendingRequestID(vm))
            vm.draft = "編集中の文章"
            #expect(await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["原因を調査"]]))
            let sent = try #require(wire.requests.last { $0["method"]?.stringValue == "turn/steer" })
            #expect(sent["params"]?["threadId"]?.stringValue == "live")
            #expect(sent["params"]?["expectedTurnId"]?.stringValue == "turn")
            #expect(messageText(sent)?.contains("原因を調査") == true)
            #expect(vm.status == .running)
            #expect(vm.displayStatus == .running)
            #expect(vm.draft == "編集中の文章")
            #expect(pendingRequestID(vm) == nil)
            #expect(!(await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["重複"]])))
        }
    }

    @Test("通常完了では質問を残し、完了後の回答は新しい入力として送る")
    func answersAfterCompletion() async throws {
        try await withSession { vm, wire, _ in
            try wire.turnStarted()
            try wire.question("later")
            try wire.barrier("later-ready")
            try await wait { vm.transcript.last?.id == "later-ready" }
            let requestID = try #require(pendingRequestID(vm))
            try wire.turnCompleted()
            try await wait { vm.status == .idle }
            #expect(pendingRequestID(vm) == requestID)
            #expect(vm.displayStatus == .awaitingUserQuestion)
            #expect(await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["順番に実行"]]))
            #expect(vm.displayStatus != .awaitingUserQuestion)
            #expect(wire.requests.filter { $0["method"]?.stringValue == "turn/start" }.count == 1)
            #expect(!wire.requests.contains { $0["method"]?.stringValue == "turn/steer" })
        }
    }

    @Test("非同期カードを閉じても独立作業を中断しない")
    func declinesAsyncOnly() async throws {
        try await withSession { vm, wire, _ in
            try wire.turnStarted()
            try wire.question("dismiss")
            try wire.barrier("dismiss-ready")
            try await wait { vm.transcript.last?.id == "dismiss-ready" }
            let requestID = try #require(pendingRequestID(vm))
            #expect(await vm.declineUserQuestion(requestId: requestID))
            #expect(vm.status == .running)
            #expect(vm.displayStatus == .running)
            #expect(pendingRequestID(vm) == nil)
            #expect(!wire.requests.contains { $0["method"]?.stringValue == "turn/interrupt" })
        }
    }

    @Test("回答送信中に閉じても独立作業を中断せず、回答の配送を維持する")
    func dismissDuringAnswerDoesNotInterrupt() async throws {
        try await withSession { vm, wire, _ in
            try wire.turnStarted()
            try wire.question("sending")
            try wire.barrier("sending-ready")
            try await wait { vm.transcript.last?.id == "sending-ready" }
            let requestID = try #require(pendingRequestID(vm))
            wire.holdsMessages = true
            defer { wire.releaseMessages() }
            let sending = Task { await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["A"]]) }
            try await wait { wire.heldMessageCount == 1 }
            await vm.dismissUserQuestion(requestId: requestID)
            #expect(vm.status == .running)
            #expect(pendingRequestID(vm) == requestID)
            #expect(!wire.requests.contains { $0["method"]?.stringValue == "turn/interrupt" })
            wire.releaseMessages()
            #expect(await sending.value)
            #expect(pendingRequestID(vm) == nil)
        }
    }

    @Test("完了後の回答・拒否は追加のイベントやflushなしで保存される", arguments: [false, true])
    func persistsResolvedQuestion(answering: Bool) async throws {
        let store = QuestionTranscriptStore(items: [])
        var sessionID: SessionID?
        try await withSession(transcriptStore: store) { vm, wire, _ in
            sessionID = vm.id
            try wire.turnStarted()
            try wire.question("persist")
            try wire.barrier("persist-ready")
            try await wait { vm.transcript.last?.id == "persist-ready" }
            let requestID = try #require(pendingRequestID(vm))
            try wire.turnCompleted()
            try await wait { vm.status == .idle }
            await vm.flushTranscriptNow()
            let pending = try await store.loadTranscript(for: vm.id)
            #expect(pending.contains { if case .userQuestion(_, _, _, _, .pending, _) = $0 { true } else { false } })
            if answering {
                #expect(await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["A"]]))
            } else {
                #expect(await vm.declineUserQuestion(requestId: requestID))
            }
        }
        let savedSessionID = try #require(sessionID)
        let saved = try await store.loadTranscript(for: savedSessionID)
        let expected: ChatUserQuestionState = answering ? .answered : .expired
        #expect(saved.contains { if case .userQuestion(_, _, _, _, let state, _) = $0 { state == expected } else { false } })
        #expect(!saved.contains { if case .userQuestion(_, _, _, _, .pending, _) = $0 { true } else { false } })
        if answering {
            #expect(saved.contains { if case .userQuestion(_, _, _, let answers, _, _) = $0 { answers == ["question-0": ["A"]] } else { false } })
        }
    }

    @Test("終了時の非同期質問の失効は追加のflushなしで保存される")
    func terminationPersistsExpiration() async throws {
        let store = QuestionTranscriptStore(items: [])
        var sessionID: SessionID?
        try await withSession(transcriptStore: store) { vm, wire, _ in
            sessionID = vm.id
            try wire.turnStarted()
            try wire.question("terminate")
            try wire.barrier("terminate-ready")
            try await wait { vm.transcript.last?.id == "terminate-ready" }
            await vm.flushTranscriptNow()
            let pending = try await store.loadTranscript(for: vm.id)
            #expect(pending.contains { if case .userQuestion(_, _, _, _, .pending, _) = $0 { true } else { false } })
        }
        let savedSessionID = try #require(sessionID)
        let saved = try await store.loadTranscript(for: savedSessionID)
        #expect(saved.contains { if case .userQuestion(_, _, _, _, .expired, _) = $0 { true } else { false } })
        #expect(!saved.contains { if case .userQuestion(_, _, _, _, .pending, _) = $0 { true } else { false } })
    }

    @Test("回答送信失敗は未回答のまま残し、再試行できる")
    func answerFailure() async throws {
        try await withSession { vm, wire, _ in
            try wire.turnStarted()
            try wire.question("retry")
            try wire.barrier("retry-ready")
            try await wait { vm.transcript.last?.id == "retry-ready" }
            let requestID = try #require(pendingRequestID(vm))
            wire.rejectsMessages = true
            #expect(!(await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["A"]])))
            #expect(pendingRequestID(vm) == requestID)
            #expect(vm.status == .running)
            #expect(vm.displayStatus == .awaitingUserQuestion)
            #expect(vm.transcript.contains { if case .error = $0 { true } else { false } })
            wire.rejectsMessages = false
            #expect(await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["A"]]))
            #expect(pendingRequestID(vm) == nil)
            #expect(vm.displayStatus == .running)
        }
    }

    @Test("同文質問は別の回答キーを持ち、不完全な回答を送信しない")
    func duplicateTitles() async throws {
        try await withSession { vm, wire, _ in
            try wire.turnStarted()
            try wire.question("duplicates", questions: [.object(["title": .string("同じ質問")]), .object(["title": .string("同じ質問")])])
            try wire.barrier("duplicates-ready")
            try await wait { vm.transcript.last?.id == "duplicates-ready" }
            let requestID = try #require(pendingRequestID(vm))
            #expect(!(await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["A"]])))
            #expect(!wire.requests.contains { $0["method"]?.stringValue == "turn/steer" })
            #expect(await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["A"], "question-1": ["B"]]))
            let sent = try #require(wire.requests.last { $0["method"]?.stringValue == "turn/steer" })
            #expect(messageText(sent) == "1. 同じ質問\nA\n\n2. 同じ質問\nB")
        }
    }

    @Test("中断は非同期カードも失効させ、未回答を送信しない")
    func interruptionExpires() async throws {
        try await withSession { vm, wire, _ in
            try wire.turnStarted()
            try wire.question("interrupted")
            try wire.barrier("interrupt-ready")
            try await wait { vm.transcript.last?.id == "interrupt-ready" }
            let requestID = try #require(pendingRequestID(vm))
            await vm.turnInterrupt()
            #expect(pendingRequestID(vm) == nil)
            #expect(!(await vm.respondToUserQuestion(requestId: requestID, answers: ["question-0": ["A"]])))
        }
    }

    @Test("保存済みの質問状態を復元し、実行中の新しい質問は受け付ける", arguments: [ChatUserQuestionState.pending, .answered, .expired])
    func restoresSavedQuestionState(_ savedState: ChatUserQuestionState) async throws {
        let origin = try #require(CodexAsyncQuestionID(threadID: "live", turnID: "turn", itemID: "history"))
        let questions = [ChatUserQuestion(question: "以前の質問です", header: "", options: [], multiSelect: false, id: "question-0")]
        let saved = ChatItem.userQuestion(id: "question-\(origin.requestID)", requestId: origin.requestID,
                                         questions: questions, answers: savedState == .answered ? ["question-0": ["回答"]] : nil,
                                         state: savedState, timestamp: Date())
        try await withSession(restoresActive: true, persisted: [saved]) { vm, wire, notifications in
            #expect(vm.transcript.contains(saved))
            #expect(notifications.approvalPendingCalls.isEmpty)
            try wire.question("history")
            try wire.question("new")
            try wire.barrier("saved-restored")
            try await wait { vm.transcript.last?.id == "saved-restored" }
            #expect(vm.transcript.contains(saved))
            #expect(notifications.approvalPendingCalls.count == 1)
        }
    }

    private func pendingRequestID(_ vm: ChatSessionViewModel) -> String? {
        vm.transcript.compactMap { item in
            if case .userQuestion(_, let requestID, _, _, .pending, _) = item { requestID } else { nil }
        }.first
    }

    private func messageText(_ request: JSONValue) -> String? {
        guard case .array(let inputs)? = request["params"]?["input"] else { return nil }
        return inputs.first?["text"]?.stringValue
    }

    private func withSession(restoresActive: Bool = false, historyText: String = "以前の質問です", persisted: [ChatItem]? = nil, transcriptStore: (any TranscriptStore)? = nil, _ body: (ChatSessionViewModel, QuestionWire, MockRemoteSessionNotifier) async throws -> Void) async throws {
        let wire = QuestionWire(restoresActive: restoresActive, historyText: historyText)
        let client = CodexStructuredAgentClient(client: CodexAppServerClient(transport: wire))
        let store: (any TranscriptStore)? = transcriptStore ?? persisted.map { QuestionTranscriptStore(items: $0) }
        let vm = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.codex), client: client,
                                      approvalBroker: ChatApprovalBroker(), workingDirectory: nil, transcriptStore: store)
        let notifications = MockRemoteSessionNotifier()
        vm.remoteSessionNotifier = notifications
        do {
            if restoresActive {
                await vm.restore(threadId: "live", approvalPolicy: .named("never"), sandbox: .named("danger-full-access"))
            } else {
                try await vm.startNew(approvalPolicy: .named("never"), sandbox: .named("danger-full-access"))
            }
            try await body(vm, wire, notifications)
        } catch {
            await vm.terminate()
            throw error
        }
        await vm.terminate()
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw WaitError.timedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
    private enum WaitError: Error { case timedOut }
}

private actor QuestionTranscriptStore: TranscriptStore {
    private var items: [ChatItem]
    init(items: [ChatItem]) { self.items = items }
    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] { items }
    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        for item in items {
            if let index = self.items.firstIndex(where: { $0.id == item.id }) {
                self.items[index] = item
            } else {
                self.items.append(item)
            }
        }
    }
    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws { self.items = items }
    func saveTurnUsageSnapshot(_ usage: TurnUsage, for sessionID: SessionID) async throws {}
}

final class QuestionWire: AppServerTransport, @unchecked Sendable {
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let restoresActive: Bool
    private let historyText: String
    private let lock = NSLock()
    private var recordedRequests: [JSONValue] = []
    private var rejectsInput = false
    private var holdsInput = false
    private var heldResponses: [Data] = []
    var requests: [JSONValue] { lock.withLock { recordedRequests } }
    var heldMessageCount: Int { lock.withLock { heldResponses.count } }
    var holdsMessages: Bool {
        get { lock.withLock { holdsInput } }
        set { lock.withLock { holdsInput = newValue } }
    }
    var rejectsMessages: Bool {
        get { lock.withLock { rejectsInput } }
        set { lock.withLock { rejectsInput = newValue } }
    }

    init(restoresActive: Bool = false, historyText: String = "以前の質問です") {
        self.restoresActive = restoresActive
        self.historyText = historyText
        (receivedLines, continuation) = AsyncStream.makeStream()
    }

    func send(_ data: Data) async throws {
        let request = try JSONDecoder().decode(JSONValue.self, from: data)
        lock.withLock { recordedRequests.append(request) }
        guard let id = request["id"] else { return }
        if rejectsMessages, ["turn/steer", "turn/start"].contains(request["method"]?.stringValue ?? "") {
            try receive(.object(["id": id, "error": .object(["code": .number(-32000), "message": .string("input rejected")])]))
            return
        }
        let result: JSONValue
        switch request["method"]?.stringValue {
        case "initialize":
            result = .object(["codexHome": .string("/verification"), "platformFamily": .string("macOS"),
                              "platformOs": .string("macOS"), "userAgent": .string("question-test")])
        case "thread/start", "thread/read", "thread/resume":
            result = .object(["thread": .object([
                "id": .string("live"), "status": .object(["type": .string(restoresActive ? "active" : "idle")]),
                "turns": .array(restoresActive ? [.object([
                    "id": .string("turn"), "status": .string("inProgress"),
                    "items": .array([.object(["id": .string("history"), "type": .string("agentMessage"),
                        "text": .string(historyText), "delivery": .string("async"),
                        "questions": .array([.object(["title": .string("以前の質問です")])])])]),
                ])] : []),
            ])])
        case "skills/list":
            if case .array(let cwds)? = request["params"]?["cwds"] {
                result = .object(["data": .array(cwds.map { cwd in
                    .object(["cwd": cwd, "errors": .array([]), "skills": .array([])])
                })])
            } else {
                result = .object(["data": .array([])])
            }
        case "model/list", "permissionProfile/list", "collaborationMode/list", "thread/list":
            result = .object(["data": .array([])])
        case "turn/steer": result = .object(["turnId": request["params"]?["expectedTurnId"] ?? .null])
        default: result = .object([:])
        }
        let response = try JSONEncoder().encode(JSONValue.object(["id": id, "result": result]))
        if ["turn/steer", "turn/start"].contains(request["method"]?.stringValue ?? ""),
           lock.withLock({
               guard holdsInput else { return false }
               heldResponses.append(response)
               return true
           }) { return }
        continuation.yield(response)
    }

    func releaseMessages() {
        let responses = lock.withLock {
            holdsInput = false
            let responses = heldResponses
            heldResponses.removeAll()
            return responses
        }
        for response in responses { continuation.yield(response) }
    }

    func close() async { continuation.finish() }

    func turnStarted(turn: String = "turn") throws {
        try receive(.object(["method": .string("turn/started"), "params": .object([
            "threadId": .string("live"), "turn": .object(["id": .string(turn), "status": .string("inProgress")]),
        ])]))
    }

    func turnCompleted() throws {
        try receive(.object(["method": .string("turn/completed"), "params": .object([
            "threadId": .string("live"), "turn": .object(["id": .string("turn"), "status": .string("completed")]),
        ])]))
    }

    func question(_ id: String, method: String = "item/completed", thread: String = "live", turn: String = "turn", questions: [JSONValue]? = nil) throws {
        try item(id, method: method, thread: thread, turn: turn, question: true, questions: questions)
    }

    func barrier(_ id: String, turn: String = "turn") throws {
        try item(id, method: "item/completed", thread: "live", turn: turn, question: false)
    }

    private func item(_ id: String, method: String, thread: String, turn: String, question: Bool, questions: [JSONValue]? = nil) throws {
        var item: [String: JSONValue] = ["id": .string(id), "type": .string("agentMessage"),
                                        "text": .string(question ? "順番に検証してよいですか？" : id)]
        if question {
            item["delivery"] = .string("async")
            item["questions"] = .array(questions ?? [.object(["title": .string("順番に検証してよいですか？"),
                                                 "options": .array([.string("順番に実行"), .string("原因を調査")])])])
        }
        try receive(.object(["method": .string(method), "params": .object([
            "threadId": .string(thread), "turnId": .string(turn), "item": .object(item),
        ])]))
    }

    private func receive(_ message: JSONValue) throws {
        continuation.yield(try JSONEncoder().encode(message))
    }
}
