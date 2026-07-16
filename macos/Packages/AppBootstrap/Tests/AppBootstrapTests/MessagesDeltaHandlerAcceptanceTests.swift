import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
import SessionFeature

// task-3 受け入れテスト（PM 著・凍結）。契約: docs/specs/mobile-api-extensions-contract.md 6。
// long-poll の待機ループはハンドラ層に置く設計（task-3.md）のため、stub の逐次応答で検証する。
// アサーションの変更は禁止。ハーネス欠陥を発見した場合は PM に報告し、承認を得たうえで
// ハーネス部分に限り修理してよい。

@MainActor
@Suite struct MessagesDeltaHandlerAcceptanceTests {
    @MainActor
    private final class DeltaDashboardStub: ControlActionDashboard {
        /// 呼び出しごとに先頭から消費する応答スクリプト。空になったら lastResponse を返し続ける。
        var deltaScript: [TranscriptDelta?] = []
        var lastResponse: TranscriptDelta?
        private(set) var deltaCallCount = 0
        private(set) var receivedSince: [String?] = []

        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? {
            deltaCallCount += 1
            receivedSince.append(since)
            if !deltaScript.isEmpty {
                return deltaScript.removeFirst()
            }
            return lastResponse
        }

        // --- 既存プロトコル要件（ダミー） ---
        var controlSessionSummaries: [ControlSessionSummary] = []
        func sendMessage(
            to recipient: Recipient,
            text: String,
            submit: Bool,
            from: SessionID?,
            inReplyTo: UUID?,
            images: [ControlImageAttachment]
        ) async -> DashboardViewModel.SendOutcome { .sent }
        func spawnSession(
            ref: AgentRef,
            from: SessionID?,
            backend: SessionBackend,
            workingDirectory: String?
        ) async throws -> SessionID { SessionID() }
        func isAuthorizedToRemove(_ id: SessionID, requester: SessionID?) -> Bool { true }
        func removeSession(_ id: SessionID) async -> Bool { true }
        func renameSession(_ id: SessionID, to name: String) {}
        func sessionOutput(for id: SessionID) -> String? { nil }
        func sessionChatMessages(for id: SessionID) -> [ChatItem]? { nil }
        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
        func waitUntilDone(
            for id: SessionID,
            timeout: Duration,
            sentinel: String?
        ) async -> DashboardViewModel.DoneResult { .done(output: "") }
        func listApprovals() async -> [ApprovalDTO] { [] }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .notFound }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
    }

    private func makeHandler(_ dashboard: DeltaDashboardStub) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        return handler
    }

    private func bodyJSON(_ response: ControlResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    private func messagesRequest(id: SessionID, since: String? = nil, wait: Int? = nil) -> ControlRequest {
        ControlRequest(requester: nil, action: .messages(id: id, since: since, wait: wait))
    }

    private static let ts = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func nonStructuredSessionReturns404() async throws {
        let dashboard = DeltaDashboardStub()
        dashboard.lastResponse = nil
        let handler = makeHandler(dashboard)

        let response = await handler.handle(messagesRequest(id: SessionID()))

        #expect(response.statusCode == 404)
    }

    @Test func legacyCallWithoutQueryAddsCursorAndOmitsSnapshot() async throws {
        let dashboard = DeltaDashboardStub()
        dashboard.lastResponse = TranscriptDelta(
            items: [.agentMessage(id: "m1", text: "hello", timestamp: Self.ts)],
            cursor: "c-000042",
            isSnapshot: false
        )
        let id = SessionID()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(messagesRequest(id: id))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["sessionId"] as? String == id.rawValue.uuidString)
        #expect(body["cursor"] as? String == "c-000042")
        // 通常応答（差分・全量初回）では snapshot キーを出さない（後方互換）
        #expect(body["snapshot"] == nil)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages.first?["id"] as? String == "m1")
        #expect(messages.first?["type"] as? String == "agent")
        #expect(dashboard.receivedSince == [nil])
    }

    @Test func snapshotFallbackSetsSnapshotTrue() async throws {
        let dashboard = DeltaDashboardStub()
        dashboard.lastResponse = TranscriptDelta(
            items: [.agentMessage(id: "m1", text: "full", timestamp: Self.ts)],
            cursor: "c-000043",
            isSnapshot: true
        )
        let handler = makeHandler(dashboard)

        let response = await handler.handle(messagesRequest(id: SessionID(), since: "expired-cursor"))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["snapshot"] as? Bool == true)
        #expect(body["cursor"] as? String == "c-000043")
        #expect(dashboard.receivedSince == ["expired-cursor"])
    }

    @Test func sinceIsForwardedToDashboard() async throws {
        let dashboard = DeltaDashboardStub()
        dashboard.lastResponse = TranscriptDelta(items: [], cursor: "c-7", isSnapshot: false)
        let handler = makeHandler(dashboard)

        let response = await handler.handle(messagesRequest(id: SessionID(), since: "c-000007"))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        let messages = try #require(body["messages"] as? [Any])
        #expect(messages.isEmpty)
        #expect(body["cursor"] as? String == "c-7")
        #expect(dashboard.receivedSince.first == "c-000007")
    }

    @Test func waitPollsUntilNewMessagesArrive() async throws {
        let dashboard = DeltaDashboardStub()
        let empty = TranscriptDelta(items: [], cursor: "c-10", isSnapshot: false)
        let ready = TranscriptDelta(
            items: [.agentMessage(id: "m-new", text: "arrived", timestamp: Self.ts)],
            cursor: "c-11",
            isSnapshot: false
        )
        dashboard.deltaScript = [empty, empty, ready]
        let handler = makeHandler(dashboard)

        let response = await handler.handle(messagesRequest(id: SessionID(), since: "c-10", wait: 10))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages.first?["id"] as? String == "m-new")
        #expect(body["cursor"] as? String == "c-11")
        // 空応答の間はポーリングを継続している（少なくとも3回呼ばれてから返る）
        #expect(dashboard.deltaCallCount >= 3)
    }

    @Test func waitTimeoutReturnsEmptyMessagesWithCurrentCursor() async throws {
        let dashboard = DeltaDashboardStub()
        dashboard.lastResponse = TranscriptDelta(items: [], cursor: "c-20", isSnapshot: false)
        let handler = makeHandler(dashboard)

        let start = ContinuousClock.now
        let response = await handler.handle(messagesRequest(id: SessionID(), since: "c-20", wait: 1))
        let elapsed = ContinuousClock.now - start

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        let messages = try #require(body["messages"] as? [Any])
        #expect(messages.isEmpty)
        #expect(body["cursor"] as? String == "c-20")
        // clamp(1...25) の下限 1 秒程度で返る（無限待ち・即時 return のどちらでもない）
        #expect(elapsed >= .milliseconds(700))
        #expect(elapsed < .seconds(10))
    }

    @Test func waitWithoutSinceReturnsImmediately() async throws {
        let dashboard = DeltaDashboardStub()
        dashboard.lastResponse = TranscriptDelta(items: [], cursor: "c-0", isSnapshot: false)
        let handler = makeHandler(dashboard)

        let response = await handler.handle(messagesRequest(id: SessionID(), since: nil, wait: 10))

        #expect(response.statusCode == 200)
        // since 省略時は wait を無視して即応答（ポーリングしない＝1回だけ取得）
        #expect(dashboard.deltaCallCount == 1)
    }

    @Test func snapshotDuringWaitReturnsImmediatelyWithSnapshot() async throws {
        let dashboard = DeltaDashboardStub()
        let empty = TranscriptDelta(items: [], cursor: "c-30", isSnapshot: false)
        let snapshot = TranscriptDelta(
            items: [.agentMessage(id: "m1", text: "full", timestamp: Self.ts)],
            cursor: "c-31",
            isSnapshot: true
        )
        dashboard.deltaScript = [empty, snapshot]
        let handler = makeHandler(dashboard)

        let response = await handler.handle(messagesRequest(id: SessionID(), since: "c-30", wait: 10))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        // wait 中に編集・置換（snapshot 化）が起きたら、それを即返す（握りつぶして空を返さない）
        #expect(body["snapshot"] as? Bool == true)
        let messages = try #require(body["messages"] as? [Any])
        #expect(messages.count == 1)
    }
}
