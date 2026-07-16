import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

@Suite struct TeamTimelineModelTests {
    @Test func mergeOrdersMessagesByAscendingTimestampAcrossSessions() {
        let t1 = Date(timeIntervalSince1970: 10)
        let t2 = Date(timeIntervalSince1970: 20)
        let t3 = Date(timeIntervalSince1970: 30)
        let first = source(
            "00000000-0000-0000-0000-000000000001",
            messages: [
                message("first-late", timestamp: t3),
            ]
        )
        let second = source(
            "00000000-0000-0000-0000-000000000002",
            messages: [
                message("second-early", timestamp: t1),
                message("second-middle", timestamp: t2),
            ]
        )

        let merged = TeamTimelineModel.merge([first, second])

        #expect(merged.map(\.sourceMessageID) == ["second-early", "second-middle", "first-late"])
    }

    @Test func mergeUsesSessionOrderThenOriginalOrderForEqualTimestamps() {
        let timestamp = Date(timeIntervalSince1970: 10)
        let first = source(
            "00000000-0000-0000-0000-000000000001",
            messages: [
                message("first-1", timestamp: timestamp),
                message("first-2", timestamp: timestamp),
            ]
        )
        let second = source(
            "00000000-0000-0000-0000-000000000002",
            messages: [
                message("second-1", timestamp: timestamp),
            ]
        )

        let merged = TeamTimelineModel.merge([first, second])

        #expect(merged.map(\.sourceMessageID) == ["first-1", "first-2", "second-1"])
    }

    @Test func mergePlacesMissingTimestampsDeterministicallyAfterDatedMessages() {
        let first = source(
            "00000000-0000-0000-0000-000000000001",
            messages: [
                message("first-missing-1", timestamp: nil),
                message("first-missing-2", timestamp: nil),
            ]
        )
        let second = source(
            "00000000-0000-0000-0000-000000000002",
            messages: [
                message("second-dated", timestamp: Date(timeIntervalSince1970: 10)),
                message("second-missing", timestamp: nil),
            ]
        )

        let merged = TeamTimelineModel.merge([first, second])

        #expect(merged.map(\.sourceMessageID) == [
            "second-dated",
            "first-missing-1",
            "first-missing-2",
            "second-missing",
        ])
    }

    private func source(
        _ uuid: String,
        messages: [TeamTimelineSourceMessage]
    ) -> TeamTimelineSource {
        TeamTimelineSource(
            id: SessionID(rawValue: UUID(uuidString: uuid)!),
            displayName: "Session",
            agentDescriptor: AgentRegistry.descriptor(for: .claudeCode),
            messages: messages
        )
    }

    private func message(_ id: String, timestamp: Date?) -> TeamTimelineSourceMessage {
        TeamTimelineSourceMessage(
            id: id,
            timestamp: timestamp,
            content: .terminalText(id)
        )
    }
}
