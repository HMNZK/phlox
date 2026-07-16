import Foundation
import Testing
import AgentDomain
import ControlServer
import DashboardFeature
import StructuredChatKit
import AppBootstrap
import SessionFeature

// task-2 受け入れテスト（PM 著・凍結）。契約: docs/specs/mobile-api-extensions-contract.md 5。
// アサーションの変更は禁止。ハーネス欠陥を発見した場合は PM に報告し、承認を得たうえで
// ハーネス部分に限り修理してよい。

@MainActor
@Suite struct SendImagesHandlerAcceptanceTests {
    @MainActor
    private final class SendImagesDashboardStub: ControlActionDashboard {
        var sendOutcome: DashboardViewModel.SendOutcome = .sent
        private(set) var receivedText: String?
        private(set) var receivedImages: [ControlImageAttachment]?

        func sendMessage(
            to recipient: Recipient,
            text: String,
            submit: Bool,
            from: SessionID?,
            inReplyTo: UUID?,
            images: [ControlImageAttachment]
        ) async -> DashboardViewModel.SendOutcome {
            receivedText = text
            receivedImages = images
            return sendOutcome
        }

        // --- 既存プロトコル要件（ダミー） ---
        var controlSessionSummaries: [ControlSessionSummary] = []
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
        func interruptSession(_ id: SessionID) async -> ControlInterruptOutcome { .notFound }
        func sessionSubAgents(for id: SessionID) -> [SubAgentControlSummary]? { nil }
        func sessionSubAgentMessages(for id: SessionID, subAgentID: String) -> [ChatItem]? { nil }
        func sessionUsage(for id: SessionID) -> ControlSessionUsage? { nil }
    }

    private func makeHandler(_ dashboard: SendImagesDashboardStub) -> ControlActionHandler {
        let handler = ControlActionHandler()
        handler.dashboard = dashboard
        return handler
    }

    private func bodyJSON(_ response: ControlResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    private func sendAction(images: [ControlImageAttachment]) -> ControlRequest {
        ControlRequest(
            requester: nil,
            action: .sendText(
                to: .name("agent-alpha"),
                text: "この画面を見て",
                submit: true,
                inReplyTo: nil,
                images: images
            )
        )
    }

    @Test func imagesUnsupportedMapsTo409WithContractError() async throws {
        let dashboard = SendImagesDashboardStub()
        dashboard.sendOutcome = .imagesUnsupported
        let handler = makeHandler(dashboard)
        let images = [ControlImageAttachment(mediaType: "image/png", data: Data([0x01, 0x02]))]

        let response = await handler.handle(sendAction(images: images))

        #expect(response.statusCode == 409)
        let body = try bodyJSON(response)
        #expect(body["error"] as? String == "images unsupported")
    }

    @Test func sentWithImagesReturns200AndPassesImagesThrough() async throws {
        let dashboard = SendImagesDashboardStub()
        dashboard.sendOutcome = .sent
        let handler = makeHandler(dashboard)
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47])
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let images = [
            ControlImageAttachment(mediaType: "image/png", data: pngBytes),
            ControlImageAttachment(mediaType: "image/jpeg", data: jpegBytes),
        ]

        let response = await handler.handle(sendAction(images: images))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["ok"] as? Bool == true)
        let received = try #require(dashboard.receivedImages)
        #expect(received.count == 2)
        #expect(received[0].mediaType == "image/png")
        #expect(received[0].data == pngBytes)
        #expect(received[1].mediaType == "image/jpeg")
        #expect(received[1].data == jpegBytes)
        #expect(dashboard.receivedText == "この画面を見て")
    }

    @Test func emptyImagesKeepsLegacyBehavior() async throws {
        let dashboard = SendImagesDashboardStub()
        dashboard.sendOutcome = .sent
        let handler = makeHandler(dashboard)

        let response = await handler.handle(sendAction(images: []))

        #expect(response.statusCode == 200)
        let body = try bodyJSON(response)
        #expect(body["ok"] as? Bool == true)
        let received = try #require(dashboard.receivedImages)
        #expect(received.isEmpty)
    }

    @Test func notFoundStillMapsTo404WithImages() async throws {
        let dashboard = SendImagesDashboardStub()
        dashboard.sendOutcome = .notFound
        let handler = makeHandler(dashboard)
        let images = [ControlImageAttachment(mediaType: "image/png", data: Data([0x01]))]

        let response = await handler.handle(sendAction(images: images))

        #expect(response.statusCode == 404)
        let body = try bodyJSON(response)
        #expect(body["error"] as? String == "recipient not found")
    }
}
