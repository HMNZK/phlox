import Foundation
import Testing
@testable import PhloxCore

@Suite struct SessionActivityContractTests {
    @Test func attributesAndContentStateUseLiveActivityWireKeys() throws {
        let attributes = SessionActivityAttributes(
            sessionId: "session-123",
            sessionName: "Bright Lily"
        )
        let state = SessionActivityAttributes.ContentState(
            sessionId: "session-123",
            sessionName: "Bright Lily",
            status: "approval_pending",
            summary: "Approval pending"
        )

        #expect(try keys(of: attributes) == ["sessionId", "sessionName"])
        #expect(try keys(of: state) == ["sessionId", "sessionName", "status", "summary"])
    }

    @Test func APNsEnvelopeUsesAppleLiveActivityKeys() throws {
        let envelope = SessionLiveActivityPushEnvelope(
            aps: .init(
                timestamp: 1_700_000_000,
                event: "start",
                contentState: .init(
                    sessionId: "session-123",
                    sessionName: "Bright Lily",
                    status: "approval_pending",
                    summary: "Approval pending"
                ),
                staleDate: 1_700_000_900,
                attributesType: "SessionActivityAttributes",
                attributes: .init(sessionId: "session-123", sessionName: "Bright Lily")
            )
        )

        #expect(try keys(of: envelope.aps) == [
            "attributes", "attributes-type", "content-state", "event", "stale-date", "timestamp",
        ])
    }

    @Test func coordinatorSessionIndexRejectsDuplicateActivityForSameSession() {
        var index = LiveActivitySessionIndex()

        #expect(index.claim(sessionId: "session-123", activityId: "activity-1") == .accepted)
        #expect(index.claim(sessionId: "session-123", activityId: "activity-1") == .alreadyTracked)
        #expect(index.claim(sessionId: "session-123", activityId: "activity-2") == .duplicate)
        #expect(index.claim(sessionId: "session-456", activityId: "activity-2") == .accepted)
    }

    private func keys<T: Encodable>(of value: T) throws -> Set<String> {
        let data = try JSONEncoder().encode(value)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return Set(object.keys)
    }
}
