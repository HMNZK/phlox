import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
import SessionFeature

// task-1 受け入れテスト（PM 著・凍結）。契約: docs/specs/mobile-api-extensions-contract.md 1〜4。
// wire JSON のキー名・ステータスコードは契約書のフィクスチャと一字一句一致させる。
// アサーションの変更は禁止。ハーネス欠陥を発見した場合は PM に報告し、承認を得たうえで
// ハーネス部分に限り修理してよい。

@MainActor
@Suite struct MobileControlHandlerAcceptanceTests {
    @MainActor
    private final class MobileDashboardStub: ControlActionDashboard {
        // --- task-1 で追加される面 ---
        var interruptOutcome: ControlInterruptOutcome = .accepted
        var subAgentSummaries: [SubAgentControlSummary]?
        var subAgentMessages: [ChatItem]?
        var usage: ControlSessionUsage?
        private(set) var interruptedID: SessionID?
        private(set) var requestedSubAgentID: String?

        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome {
            interruptedID = id
            return interruptOutcome
        }

        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? {
            subAgentSummaries
        }

        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? {
            requestedSubAgentID = subAgentID
            return subAgentMessages
        }

        func sessionUsage(for id: SessionID) -> ControlSessionUsage? {
            usage
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
        func sessionChatMessagesDelta(for id: SessionID, since: String?) -> TranscriptDelta? { nil }
        func waitUntilReady(for id: SessionID, timeout: Duration) async -> DashboardViewModel.ReadinessResult { .ready }
        func waitUntilDone(
            for id: SessionID,
            timeout: Duration,
            sentinel: String?
        ) async -> DashboardViewModel.DoneResult { .done(output: "") }
        func listApprovals() async -> [ApprovalDTO] { [] }
        func respondToApproval(id: String, decision: ApprovalDecision) async -> Bool { true }
    }

    private func makeHandler(_ dashboard: MobileDashboardStub?) -> ControlActionHandler {
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

    // MARK: - 契約1 interrupt

    @Test func interruptAcceptedReturns204NoContent() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.interruptOutcome = .accepted
        let id = SessionID()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.interrupt(id: id)))

        #expect(response.statusCode == 204)
        #expect(response.body.isEmpty)
        #expect(dashboard.interruptedID == id)
    }

    @Test func interruptNotFoundReturns404() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.interruptOutcome = .notFound
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.interrupt(id: SessionID())))

        #expect(response.statusCode == 404)
    }

    @Test func interruptUnsupportedReturns409WithContractError() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.interruptOutcome = .unsupported
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.interrupt(id: SessionID())))

        #expect(response.statusCode == 409)
        let body = try bodyJSON(response)
        #expect(body["error"] as? String == "interrupt unsupported")
    }

    // MARK: - 契約2 subagents

    @Test func subAgentsNilReturns404() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.subAgentSummaries = nil
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.subAgents(id: SessionID())))

        #expect(response.statusCode == 404)
    }

    @Test func subAgentsEmptyReturns200WithEmptyArray() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.subAgentSummaries = []
        let id = SessionID()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.subAgents(id: id)))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["sessionId"] as? String == id.rawValue.uuidString)
        let subAgents = try #require(body["subAgents"] as? [Any])
        #expect(subAgents.isEmpty)
    }

    @Test func subAgentsMatchesContractFixtureShape() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.subAgentSummaries = [
            SubAgentControlSummary(
                id: "sa-1",
                name: "explore-map",
                status: .running,
                messageCount: 12,
                markerMessageId: "msg-42"
            ),
        ]
        let id = SessionID()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.subAgents(id: id)))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["sessionId"] as? String == id.rawValue.uuidString)
        let subAgents = try #require(body["subAgents"] as? [[String: Any]])
        let entry = try #require(subAgents.first)
        #expect(entry["id"] as? String == "sa-1")
        #expect(entry["name"] as? String == "explore-map")
        #expect(entry["status"] as? String == "running")
        #expect(entry["messageCount"] as? Int == 12)
        #expect(entry["markerMessageId"] as? String == "msg-42")
        // 契約のキーのみが wire に出る（余計なフィールドを漏らさない）
        #expect(Set(entry.keys) == Set(["id", "name", "status", "messageCount", "markerMessageId"]))
    }

    @Test func subAgentsStatusMappingCoversThreeWireValues() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.subAgentSummaries = [
            SubAgentControlSummary(id: "s1", name: "a", status: .running, messageCount: 0, markerMessageId: nil),
            SubAgentControlSummary(id: "s2", name: "b", status: .completed, messageCount: 0, markerMessageId: nil),
            // domain の failed は契約3値（running|completed|unknown）に無いため unknown へ写像する
            SubAgentControlSummary(id: "s3", name: "c", status: .failed, messageCount: 0, markerMessageId: nil),
        ]
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.subAgents(id: SessionID())))

        let body = try bodyJSON(response)
        let subAgents = try #require(body["subAgents"] as? [[String: Any]])
        let statuses = subAgents.compactMap { $0["status"] as? String }
        #expect(statuses == ["running", "completed", "unknown"])
    }

    @Test func subAgentsOmitsMarkerMessageIdWhenNil() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.subAgentSummaries = [
            SubAgentControlSummary(id: "s1", name: "a", status: .running, messageCount: 3, markerMessageId: nil),
        ]
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.subAgents(id: SessionID())))

        let body = try bodyJSON(response)
        let subAgents = try #require(body["subAgents"] as? [[String: Any]])
        let entry = try #require(subAgents.first)
        #expect(entry["markerMessageId"] == nil)
        #expect(Set(entry.keys) == Set(["id", "name", "status", "messageCount"]))
    }

    // MARK: - 契約3 subagent messages

    @Test func subAgentMessagesNilReturns404() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.subAgentMessages = nil
        let handler = makeHandler(dashboard)

        let response = await handler.handle(
            request(.subAgentMessages(id: SessionID(), subAgentID: "sa-unknown"))
        )

        #expect(response.statusCode == 404)
        #expect(dashboard.requestedSubAgentID == "sa-unknown")
    }

    @Test func subAgentMessagesMatchesContractFixtureShape() async throws {
        let dashboard = MobileDashboardStub()
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        dashboard.subAgentMessages = [
            .agentMessage(id: "m1", text: "…", timestamp: ts),
        ]
        let id = SessionID()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(
            request(.subAgentMessages(id: id, subAgentID: "sa-1"))
        )

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["sessionId"] as? String == id.rawValue.uuidString)
        #expect(body["subAgentId"] as? String == "sa-1")
        let messages = try #require(body["messages"] as? [[String: Any]])
        let entry = try #require(messages.first)
        // body 形状は既存 /messages と同一（ChatMessageDTO 写像の再利用）
        #expect(entry["id"] as? String == "m1")
        #expect(entry["type"] as? String == "agent")
        #expect(entry["text"] as? String == "…")
    }

    @Test func subAgentMessagesEmptyTranscriptReturns200EmptyArray() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.subAgentMessages = []
        let handler = makeHandler(dashboard)

        let response = await handler.handle(
            request(.subAgentMessages(id: SessionID(), subAgentID: "sa-1"))
        )

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        let messages = try #require(body["messages"] as? [Any])
        #expect(messages.isEmpty)
    }

    // MARK: - 契約4 usage

    @Test func usageNilReturns404() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.usage = nil
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.usage(id: SessionID())))

        #expect(response.statusCode == 404)
    }

    @Test func usageWithoutTurnReturnsExplicitNull() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.usage = ControlSessionUsage(turn: nil)
        let id = SessionID()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.usage(id: id)))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["sessionId"] as? String == id.rawValue.uuidString)
        // 契約: まだターンが無い場合は "turn": null（キー省略ではなく明示 null）
        #expect(body.keys.contains("turn"))
        #expect(body["turn"] is NSNull)
    }

    @Test func usageMatchesContractFixtureAndLeaksNoExtraFields() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.usage = ControlSessionUsage(turn: TurnUsage(
            costUSD: 0.1234,
            inputTokens: 111,
            outputTokens: 222,
            cacheReadTokens: 3,
            cacheCreationTokens: 4,
            contextUsedTokens: 45_678,
            contextWindowTokens: 200_000
        ))
        let id = SessionID()
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.usage(id: id)))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["sessionId"] as? String == id.rawValue.uuidString)
        let turn = try #require(body["turn"] as? [String: Any])
        #expect(turn["costUSD"] as? Double == 0.1234)
        #expect(turn["contextUsedTokens"] as? Int == 45_678)
        #expect(turn["contextWindowTokens"] as? Int == 200_000)
        // wire に出すのは契約の3キーのみ（inputTokens 等の内部フィールドを漏らさない）
        #expect(Set(turn.keys) == Set(["costUSD", "contextUsedTokens", "contextWindowTokens"]))
    }

    @Test func usageOmitsMissingTurnFields() async throws {
        let dashboard = MobileDashboardStub()
        dashboard.usage = ControlSessionUsage(turn: TurnUsage(contextUsedTokens: 10))
        let handler = makeHandler(dashboard)

        let response = await handler.handle(request(.usage(id: SessionID())))

        let body = try bodyJSON(response)
        let turn = try #require(body["turn"] as? [String: Any])
        #expect(turn["contextUsedTokens"] as? Int == 10)
        #expect(turn["costUSD"] == nil)
        #expect(turn["contextWindowTokens"] == nil)
    }

    @Test func dashboardAbsentReturns503ForAllNewActions() async throws {
        let handler = makeHandler(nil)

        let interrupt = await handler.handle(request(.interrupt(id: SessionID())))
        let subAgents = await handler.handle(request(.subAgents(id: SessionID())))
        let messages = await handler.handle(
            request(.subAgentMessages(id: SessionID(), subAgentID: "sa-1"))
        )
        let usage = await handler.handle(request(.usage(id: SessionID())))

        #expect(interrupt.statusCode == 503)
        #expect(subAgents.statusCode == 503)
        #expect(messages.statusCode == 503)
        #expect(usage.statusCode == 503)
    }
}
