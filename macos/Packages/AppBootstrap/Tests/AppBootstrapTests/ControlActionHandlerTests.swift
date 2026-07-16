import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
import SessionFeature

/// Control API の outcome → HTTP ステータス対応は phlox CLI とアプリ内
/// オーケストレーション(spawn/wait プロトコル)の契約そのもの。全対応表を固定する。
@MainActor
@Suite struct ControlActionHandlerTests {
    @MainActor
    private final class DashboardStub: ControlActionDashboard {
        var controlSessionSummaries: [ControlSessionSummary] = []
        var sendOutcome: DashboardViewModel.SendOutcome = .sent
        var spawnResult: Result<SessionID, any Error> = .success(SessionID())
        var isAuthorized = true
        var removeExisted = true
        private(set) var renamedTo: (id: SessionID, name: String)?
        var outputText: String?
        var chatMessages: [ChatItem]?
        var readiness: DashboardViewModel.ReadinessResult = .ready
        var doneResult: DashboardViewModel.DoneResult = .done(output: "")
        private(set) var readyTimeout: Duration?
        private(set) var waitTimeout: Duration?

        func sendMessage(
            to recipient: Recipient,
            text: String,
            submit: Bool,
            from: SessionID?,
            inReplyTo: UUID?,
            images: [ControlImageAttachment]
        ) async -> DashboardViewModel.SendOutcome {
            sendOutcome
        }

        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?
        ) async throws -> SessionID {
            try spawnResult.get()
        }

        func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool {
            isAuthorized
        }

        func removeSession(_ id: SessionID) async -> Bool {
            removeExisted
        }

        func renameSession(_ id: SessionID, to name: String) {
            renamedTo = (id, name)
        }

        func sessionOutput(for id: SessionID) -> String? {
            outputText
        }

        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? {
            guard let items = chatMessages else { return nil }
            return TranscriptDelta(items: items, cursor: "test-cursor", isSnapshot: false)
        }

        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult {
            readyTimeout = timeout
            return readiness
        }

        func waitUntilDone(
            for id: SessionID,
            timeout: Duration,
            sentinel: String?
        ) async -> DashboardViewModel.DoneResult {
            waitTimeout = timeout
            return doneResult
        }

        // 承認 witness: DashboardStub は既存テストが使う。デフォルト実装で空を返す。
        func listApprovals() async -> [ApprovalDTO] { [] }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .accepted }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
    }

    private func makeHandler(_ dashboard: DashboardStub?) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        return handler
    }

    private func request(_ action: ControlRequest.Action) -> ControlRequest {
        ControlRequest(requester: nil, action: action)
    }

    private func bodyJSON(_ response: ControlResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    // MARK: - approval spy witness 用スタブ拡張

    // DashboardStub はすでに上記で定義済み。承認関連のプロパティを追加するため
    // テスト内ローカルサブクラスを使う代わりに、DashboardStub を拡張してプロパティ追加。
    // → Swift では stored property を extension で追加できないので、
    //   承認テストは別の DashboardStub2 で行う。

    @MainActor
    private final class ApprovalDashboardStub: ControlActionDashboard {
        // --- 承認 spy ---
        var approvals: [ApprovalDTO] = []
        private(set) var lastRespondedID: String?
        private(set) var lastDecision: ApprovalDecision?
        var respondResult: Bool = true  // true → 200, false → 404

        // --- 既存 stub (ControlActionDashboard 要件を満たすためのダミー) ---
        var controlSessionSummaries: [ControlSessionSummary] = []
        var sendOutcome: DashboardViewModel.SendOutcome = .sent
        var spawnResult: Result<SessionID, any Error> = .success(SessionID())
        var isAuthorized = true
        var removeExisted = true
        var outputText: String?
        var readiness: DashboardViewModel.ReadinessResult = .ready
        var doneResult: DashboardViewModel.DoneResult = .done(output: "")

        func listApprovals() async -> [ApprovalDTO] { approvals }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool {
            lastRespondedID = id
            lastDecision = decision
            return respondResult
        }

        func sendMessage(to recipient: Recipient, text: String, submit: Bool, from: SessionID?, inReplyTo: UUID?, images: [ControlImageAttachment]) async -> DashboardViewModel.SendOutcome { sendOutcome }
        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?
        ) async throws -> SessionID { try spawnResult.get() }
        func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { isAuthorized }
        func removeSession(_ id: SessionID) async -> Bool { removeExisted }
        func renameSession(_ id: SessionID, to name: String) {}
        func sessionOutput(for id: SessionID) -> String? { outputText }
        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? { nil }
        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { readiness }
        func waitUntilDone(for id: SessionID, timeout: Duration, sentinel: String?) async -> DashboardViewModel.DoneResult { doneResult }
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .accepted }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
    }

    // MARK: - listApprovals

    @Test func listApprovalsReturnsEmptyArrayWhenWitnessReturnsNone() async throws {
        let dashboard = ApprovalDashboardStub()
        dashboard.approvals = []
        let handler = ControlActionHandler()
        handler.dashboard = dashboard

        let response = await handler.handle(request(.listApprovals))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        let list = try #require(body["approvals"] as? [Any])
        #expect(list.isEmpty)
    }

    @Test func listApprovalsReturnsMappedDTOs() async throws {
        let dashboard = ApprovalDashboardStub()
        dashboard.approvals = [
            ApprovalDTO(id: "id1", sessionID: "sess1", kind: "claudeCode", prompt: "Allow?"),
            ApprovalDTO(id: "id2", sessionID: "sess2", kind: "cursor", prompt: "Write?"),
        ]
        let handler = ControlActionHandler()
        handler.dashboard = dashboard

        let response = await handler.handle(request(.listApprovals))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        let list = try #require(body["approvals"] as? [[String: Any]])
        #expect(list.count == 2)
        #expect(list[0]["id"] as? String == "id1")
        #expect(list[0]["sessionID"] as? String == "sess1")
        #expect(list[0]["kind"] as? String == "claudeCode")
        #expect(list[0]["prompt"] as? String == "Allow?")
    }

    // MARK: - respondApproval

    @Test func respondApprovalAcceptDelegatesToWitnessAndReturns200() async {
        let dashboard = ApprovalDashboardStub()
        dashboard.respondResult = true
        let handler = ControlActionHandler()
        handler.dashboard = dashboard

        let response = await handler.handle(request(.respondApproval(id: "id-abc", decision: .accept)))

        #expect(response.statusCode == 200)
        #expect(dashboard.lastRespondedID == "id-abc")
        #expect(dashboard.lastDecision == .accept)
    }

    @Test func respondApprovalUnknownIDReturns404() async {
        let dashboard = ApprovalDashboardStub()
        dashboard.respondResult = false
        let handler = ControlActionHandler()
        handler.dashboard = dashboard

        let response = await handler.handle(request(.respondApproval(id: "missing", decision: .decline)))

        #expect(response.statusCode == 404)
        #expect(dashboard.lastRespondedID == "missing")
    }

    @Test(arguments: [
        AgentDomain.ApprovalDecision.accept,
        .decline,
        .acceptForSession,
        .cancel,
    ])
    func respondApprovalAllFourDecisionsDelegate(decision: AgentDomain.ApprovalDecision) async {
        let dashboard = ApprovalDashboardStub()
        dashboard.respondResult = true
        let handler = ControlActionHandler()
        handler.dashboard = dashboard

        let response = await handler.handle(request(.respondApproval(id: "x", decision: decision)))

        #expect(response.statusCode == 200)
        #expect(dashboard.lastDecision == decision)
    }

    @Test func respondApprovalWithNoDashboardReturns503() async {
        let handler = ControlActionHandler()
        // dashboard を nil のまま

        let response = await handler.handle(request(.respondApproval(id: "x", decision: .accept)))

        #expect(response.statusCode == 503)
    }

    // MARK: - dashboard 未接続

    @Test func returns503WhenDashboardIsGone() async {
        let handler = makeHandler(nil)
        let response = await handler.handle(request(.listSessions))
        #expect(response.statusCode == 503)
    }

    // MARK: - listSessions

    @Test func listSessionsMapsEveryStatusToStableString() async throws {
        let dashboard = DashboardStub()
        let statuses: [SessionStatus] = [
            .starting,
            .idle,
            .running,
            .awaitingApproval(prompt: "approve?"),
            .completed(exitCode: 0),
            .error(message: "boom"),
        ]
        dashboard.controlSessionSummaries = statuses.enumerated().map { index, status in
            ControlSessionSummary(
                id: SessionID(),
                name: "session-\(index)",
                agentID: "claudeCode",
                status: status,
                workspaceName: "ws-\(index)"
            )
        }
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.listSessions))

        #expect(response.statusCode == 200)
        let sessions = try #require(bodyJSON(response)["sessions"] as? [[String: Any]])
        #expect(sessions.map { $0["status"] as? String } == [
            "starting", "idle", "running", "awaitingApproval", "completed", "error",
        ])
        #expect(sessions.first?["name"] as? String == "session-0")
        #expect(sessions.first?["kind"] as? String == "claudeCode")
        #expect(sessions.first?["workspace"] as? String == "ws-0")
    }

    // MARK: - messages（GET /sessions/{id}/messages）

    @Test func messagesReturns404WhenSessionIsNotStructured() async throws {
        let dashboard = DashboardStub()
        dashboard.chatMessages = nil  // 非構造化/不在 → モバイルはターミナル output へフォールバック
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.messages(id: SessionID(), since: nil, wait: nil)))

        #expect(response.statusCode == 404)
        #expect(try bodyJSON(response)["error"] as? String == "session not found")
    }

    @Test func messagesReturns200WithEmptyArrayWhenTranscriptEmpty() async throws {
        let dashboard = DashboardStub()
        dashboard.chatMessages = []  // 構造化だが transcript 空（例: Claude/Cursor 再起動直後）
        let id = SessionID()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.messages(id: id, since: nil, wait: nil)))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["sessionId"] as? String == id.rawValue.uuidString)
        let messages = try #require(body["messages"] as? [Any])
        #expect(messages.isEmpty)
    }

    @Test func messagesMapsAllChatItemKindsToWireDTO() async throws {
        let dashboard = DashboardStub()
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        dashboard.chatMessages = [
            .userMessage(id: "u1", text: "hello", timestamp: ts),
            .agentMessage(id: "a1", text: "hi there", timestamp: ts),
            .reasoning(id: "r1", text: "thinking", timestamp: ts),
            .commandExecution(id: "c1", command: "ls -la", output: "file.txt", timestamp: ts),
            .fileChange(id: "f1", changes: [
                FilePatchChange(path: "Sources/A.swift", diff: "@@ -1 +1 @@", kind: "modified"),
            ], timestamp: ts),
            .error(id: "e1", message: "boom", timestamp: ts),
        ]
        let id = SessionID()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.messages(id: id, since: nil, wait: nil)))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["sessionId"] as? String == id.rawValue.uuidString)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 6)

        #expect(messages[0]["id"] as? String == "u1")
        #expect(messages[0]["type"] as? String == "user")
        #expect(messages[0]["text"] as? String == "hello")
        #expect(messages[0]["command"] == nil)  // 不要キーは省略される

        #expect(messages[1]["type"] as? String == "agent")
        #expect(messages[1]["text"] as? String == "hi there")

        #expect(messages[2]["type"] as? String == "reasoning")
        #expect(messages[2]["text"] as? String == "thinking")

        #expect(messages[3]["type"] as? String == "command")
        #expect(messages[3]["command"] as? String == "ls -la")
        #expect(messages[3]["output"] as? String == "file.txt")

        #expect(messages[4]["type"] as? String == "fileChange")
        let changes = try #require(messages[4]["changes"] as? [[String: Any]])
        #expect(changes.count == 1)
        #expect(changes[0]["path"] as? String == "Sources/A.swift")
        #expect(changes[0]["diff"] as? String == "@@ -1 +1 @@")
        #expect(changes[0]["kind"] as? String == "modified")

        #expect(messages[5]["type"] as? String == "error")
        #expect(messages[5]["message"] as? String == "boom")
    }

    @Test func messagesReturns503WhenDashboardIsGone() async {
        let handler = makeHandler(nil)
        let response = await handler.handle(request(.messages(id: SessionID(), since: nil, wait: nil)))
        #expect(response.statusCode == 503)
    }

    // MARK: - sendText の outcome → ステータス全対応表

    @Test(arguments: [
        (DashboardViewModel.SendOutcome.sent, 200),
        (.notFound, 404),
        (.ambiguous([SessionID()]), 409),
        (.rejected(reason: "control-characters"), 400),
        (.notSpawned, 425),
        (.deliveryFailed, 500),
        (.rateLimited, 429),
    ])
    func sendTextMapsOutcomeToStatusCode(outcome: DashboardViewModel.SendOutcome, expected: Int) async {
        let dashboard = DashboardStub()
        dashboard.sendOutcome = outcome
        let handler = makeHandler(dashboard)

        let response = await handler.handle(
            request(.sendText(to: .name("worker"), text: "hi", submit: true, inReplyTo: nil, images: []))
        )

        #expect(response.statusCode == expected)
    }

    @Test func sendTextAmbiguousIncludesCandidateIDs() async throws {
        let dashboard = DashboardStub()
        let candidates = [SessionID(), SessionID()]
        dashboard.sendOutcome = .ambiguous(candidates)
        let handler = makeHandler(dashboard)

        let response = await handler.handle(
            request(.sendText(to: .name("worker"), text: "hi", submit: true, inReplyTo: nil, images: []))
        )

        let body = try bodyJSON(response)
        #expect(body["candidates"] as? [String] == candidates.map { $0.rawValue.uuidString })
    }

    // MARK: - spawn のエラー → ステータス全対応表

    @Test func spawnSuccessReturns201WithSessionID() async throws {
        let dashboard = DashboardStub()
        let id = SessionID()
        dashboard.spawnResult = .success(id)
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.spawn(
            ref: .builtin(.claudeCode),
            backend: .pty,
            workingDirectory: nil
        )))

        #expect(response.statusCode == 201)
        #expect(try bodyJSON(response)["id"] as? String == id.rawValue.uuidString)
    }

    @Test(arguments: [
        (AgentSpawnError.spawnRateLimited, 429),
        (.depthLimitExceeded, 403),
        (.noProject, 400),
    ])
    func spawnFailureMapsErrorToStatusCode(error: AgentSpawnError, expected: Int) async {
        let dashboard = DashboardStub()
        dashboard.spawnResult = .failure(error)
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.spawn(
            ref: .builtin(.claudeCode),
            backend: .pty,
            workingDirectory: nil
        )))

        #expect(response.statusCode == expected)
    }

    // MARK: - remove(認可 → 存在判定)

    @Test func removeWithoutAuthorizationReturns403() async {
        let dashboard = DashboardStub()
        dashboard.isAuthorized = false
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.remove(id: SessionID())))

        #expect(response.statusCode == 403)
    }

    @Test func removeExistingSessionReturns200() async {
        let dashboard = DashboardStub()
        dashboard.removeExisted = true
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.remove(id: SessionID())))

        #expect(response.statusCode == 200)
    }

    @Test func removeMissingSessionReturns404() async {
        let dashboard = DashboardStub()
        dashboard.removeExisted = false
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.remove(id: SessionID())))

        #expect(response.statusCode == 404)
    }

    // MARK: - rename

    @Test func renameDelegatesAndReturns200() async {
        let dashboard = DashboardStub()
        let handler = makeHandler(dashboard)
        let id = SessionID()

        let response = await handler.handle(request(.rename(id: id, name: "renamed")))

        #expect(response.statusCode == 200)
        #expect(dashboard.renamedTo?.id == id)
        #expect(dashboard.renamedTo?.name == "renamed")
    }

    // MARK: - output

    @Test func outputReturns200WithScreenText() async throws {
        let dashboard = DashboardStub()
        dashboard.outputText = "screen text"
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.output(id: SessionID(), mode: .screen)))

        #expect(response.statusCode == 200)
        #expect(try bodyJSON(response)["text"] as? String == "screen text")
    }

    @Test func outputForMissingSessionReturns404() async {
        let dashboard = DashboardStub()
        dashboard.outputText = nil
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.output(id: SessionID(), mode: .screen)))

        #expect(response.statusCode == 404)
    }

    // MARK: - waitReady(結果マッピング + 1...60 丸め)

    @Test func waitReadyReadyReturns200True() async throws {
        let dashboard = DashboardStub()
        dashboard.readiness = .ready
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.waitReady(id: SessionID(), timeoutSeconds: 5)))

        #expect(response.statusCode == 200)
        #expect(try bodyJSON(response)["ready"] as? Bool == true)
    }

    @Test func waitReadyTimedOutReturns200False() async throws {
        let dashboard = DashboardStub()
        dashboard.readiness = .timedOut
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.waitReady(id: SessionID(), timeoutSeconds: 5)))

        #expect(response.statusCode == 200)
        #expect(try bodyJSON(response)["ready"] as? Bool == false)
    }

    @Test func waitReadyMissingSessionReturns404() async {
        let dashboard = DashboardStub()
        dashboard.readiness = .notFound
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.waitReady(id: SessionID(), timeoutSeconds: 5)))

        #expect(response.statusCode == 404)
    }

    @Test func waitReadyClampsTimeoutBelowToOneSecond() async {
        let dashboard = DashboardStub()
        let handler = makeHandler(dashboard)

        _ = await handler.handle(request(.waitReady(id: SessionID(), timeoutSeconds: 0)))

        #expect(dashboard.readyTimeout == .seconds(1))
    }

    @Test func waitReadyClampsTimeoutAboveToSixtySeconds() async {
        let dashboard = DashboardStub()
        let handler = makeHandler(dashboard)

        _ = await handler.handle(request(.waitReady(id: SessionID(), timeoutSeconds: 9999)))

        #expect(dashboard.readyTimeout == .seconds(60))
    }

    // MARK: - wait(結果マッピング + 1...600 丸め)

    @Test func waitDoneReturns200WithOutput() async throws {
        let dashboard = DashboardStub()
        dashboard.doneResult = .done(output: "final output")
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.wait(id: SessionID(), timeoutSeconds: 10, sentinel: nil)))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["done"] as? Bool == true)
        #expect(body["output"] as? String == "final output")
    }

    @Test func waitTimedOutReturns408WithPartialOutput() async throws {
        let dashboard = DashboardStub()
        dashboard.doneResult = .timedOut(output: "partial")
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.wait(id: SessionID(), timeoutSeconds: 10, sentinel: nil)))

        #expect(response.statusCode == 408)
        let body = try bodyJSON(response)
        #expect(body["done"] as? Bool == false)
        #expect(body["output"] as? String == "partial")
    }

    @Test func waitMissingSessionReturns404() async {
        let dashboard = DashboardStub()
        dashboard.doneResult = .notFound
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.wait(id: SessionID(), timeoutSeconds: 10, sentinel: nil)))

        #expect(response.statusCode == 404)
    }

    @Test func waitClampsTimeoutBelowToOneSecond() async {
        let dashboard = DashboardStub()
        let handler = makeHandler(dashboard)

        _ = await handler.handle(request(.wait(id: SessionID(), timeoutSeconds: 0, sentinel: nil)))

        #expect(dashboard.waitTimeout == .seconds(1))
    }

    @Test func waitClampsTimeoutAboveToSixHundredSeconds() async {
        let dashboard = DashboardStub()
        let handler = makeHandler(dashboard)

        _ = await handler.handle(request(.wait(id: SessionID(), timeoutSeconds: 9999, sentinel: nil)))

        #expect(dashboard.waitTimeout == .seconds(600))
    }
}
