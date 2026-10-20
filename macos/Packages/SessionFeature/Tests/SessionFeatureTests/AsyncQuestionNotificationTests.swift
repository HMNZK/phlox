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
            #expect(vm.transcript.allSatisfy { if case .userQuestion = $0 { false } else { true } })
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
            #expect(vm.transcript.contains { $0.id == "history" })
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

    private func withSession(restoresActive: Bool = false, historyText: String = "以前の質問です", _ body: (ChatSessionViewModel, QuestionWire, MockRemoteSessionNotifier) async throws -> Void) async throws {
        let wire = QuestionWire(restoresActive: restoresActive, historyText: historyText)
        let client = CodexStructuredAgentClient(client: CodexAppServerClient(transport: wire))
        let vm = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.codex), client: client,
                                      approvalBroker: ChatApprovalBroker(), workingDirectory: nil)
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

private final class QuestionWire: AppServerTransport, Sendable {
    let receivedLines: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private let restoresActive: Bool
    private let historyText: String

    init(restoresActive: Bool = false, historyText: String = "以前の質問です") {
        self.restoresActive = restoresActive
        self.historyText = historyText
        (receivedLines, continuation) = AsyncStream.makeStream()
    }

    func send(_ data: Data) async throws {
        let request = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let id = request["id"] else { return }
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
        case "model/list", "permissionProfile/list", "collaborationMode/list", "skills/list", "thread/list":
            result = .object(["data": .array([])])
        default: result = .object([:])
        }
        try receive(.object(["id": id, "result": result]))
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

    func question(_ id: String, method: String = "item/completed", thread: String = "live", turn: String = "turn") throws {
        try item(id, method: method, thread: thread, turn: turn, question: true)
    }

    func barrier(_ id: String, turn: String = "turn") throws {
        try item(id, method: "item/completed", thread: "live", turn: turn, question: false)
    }

    private func item(_ id: String, method: String, thread: String, turn: String, question: Bool) throws {
        var item: [String: JSONValue] = ["id": .string(id), "type": .string("agentMessage"),
                                        "text": .string(question ? "順番に検証してよいですか？" : id)]
        if question {
            item["delivery"] = .string("async")
            item["questions"] = .array([.object(["title": .string("順番に検証してよいですか？"),
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
