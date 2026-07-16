import Foundation
import Testing
import APNsClient
import AgentDomain
@testable import AppBootstrap

@Suite struct LiveActivityBridgeTests {
    @Test func approvalStartsLiveActivityWithMatchingContentState() async throws {
        let store = InMemoryDeviceTokenStore()
        let registration = try #require(DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile.PhloxMobile",
            environment: .sandbox,
            tokenType: .liveActivityPushToStart
        ))
        try store.upsert(registration)
        let sender = RecordingBridgeSender()
        let bridge = APNsNotificationBridge(
            deviceTokenStore: store,
            sender: sender,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        await bridge.notify(.approvalPending(sessionId: "session-123", sessionName: "Bright Lily"))

        let call = try #require(await sender.calls.first)
        #expect(call.pushType == .liveactivity)
        #expect(call.registration == registration)
        let json = try #require(JSONSerialization.jsonObject(with: call.payload) as? [String: Any])
        let aps = try #require(json["aps"] as? [String: Any])
        #expect(aps["event"] as? String == "start")
        #expect(aps["timestamp"] as? Int == 1_700_000_000)
        #expect(aps["stale-date"] as? Int == 1_700_000_900)
        #expect(aps["attributes-type"] as? String == "SessionActivityAttributes")
        #expect(aps["attributes"] as? [String: String] == [
            "sessionId": "session-123", "sessionName": "Bright Lily",
        ])
        #expect(aps["content-state"] as? [String: String] == [
            "sessionId": "session-123",
            "sessionName": "Bright Lily",
            "status": "approval_pending",
            "summary": "Approval pending",
        ])
    }

    @Test func completionEndsExistingSessionActivity() async throws {
        let store = InMemoryDeviceTokenStore()
        try store.upsert(try #require(DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile.PhloxMobile",
            environment: .sandbox,
            tokenType: .liveActivityUpdate,
            activityId: "activity-1",
            sessionId: "session-123"
        )))
        let sender = RecordingBridgeSender()
        let bridge = APNsNotificationBridge(
            deviceTokenStore: store,
            sender: sender,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        await bridge.notify(.sessionCompleted(sessionId: "session-123", sessionName: "Bright Lily"))

        let call = try #require(await sender.calls.first)
        let json = try #require(JSONSerialization.jsonObject(with: call.payload) as? [String: Any])
        let aps = try #require(json["aps"] as? [String: Any])
        #expect(aps["event"] as? String == "end")
        #expect((aps["content-state"] as? [String: String])?["status"] == "session_completed")
        #expect(aps["dismissal-date"] as? Int == 1_700_000_000)
    }

    @Test func approvalWithExistingUpdateTokenSendsUpdateWithoutAttributes() async throws {
        let store = InMemoryDeviceTokenStore()
        try store.upsert(try #require(DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile.PhloxMobile",
            environment: .sandbox,
            tokenType: .liveActivityUpdate,
            activityId: "activity-1",
            sessionId: "session-123"
        )))
        let sender = RecordingBridgeSender()
        let bridge = APNsNotificationBridge(
            deviceTokenStore: store,
            sender: sender,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        await bridge.notify(.approvalPending(sessionId: "session-123", sessionName: "Bright Lily"))

        let call = try #require(await sender.calls.first)
        let json = try #require(JSONSerialization.jsonObject(with: call.payload) as? [String: Any])
        let aps = try #require(json["aps"] as? [String: Any])
        #expect(aps["event"] as? String == "update")
        #expect(aps["attributes-type"] == nil)
        #expect(aps["attributes"] == nil)
        #expect(aps["stale-date"] as? Int == 1_700_000_900)
    }

    @Test func completionWithoutExistingActivityStartsAlreadyCompletedLiveActivity() async throws {
        let store = InMemoryDeviceTokenStore()
        try store.upsert(try #require(DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile.PhloxMobile",
            environment: .sandbox,
            tokenType: .liveActivityPushToStart
        )))
        let sender = RecordingBridgeSender()
        let bridge = APNsNotificationBridge(
            deviceTokenStore: store,
            sender: sender,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        await bridge.notify(.sessionCompleted(sessionId: "session-999", sessionName: "Quiet Fern"))

        let call = try #require(await sender.calls.first)
        let json = try #require(JSONSerialization.jsonObject(with: call.payload) as? [String: Any])
        let aps = try #require(json["aps"] as? [String: Any])
        #expect(aps["event"] as? String == "start")
        #expect((aps["content-state"] as? [String: String])?["status"] == "session_completed")
        #expect(aps["stale-date"] as? Int == 1_700_000_060)
        #expect(aps["attributes-type"] as? String == "SessionActivityAttributes")
    }

    @Test func rapidApprovalPendingBeforeUpdateTokenRegistersSendsOneStart() async throws {
        let store = InMemoryDeviceTokenStore()
        try store.upsert(try #require(DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile.PhloxMobile",
            environment: .sandbox,
            tokenType: .liveActivityPushToStart
        )))
        let sender = RecordingBridgeSender()
        let bridge = APNsNotificationBridge(
            deviceTokenStore: store,
            sender: sender,
            clock: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        await bridge.notify(.approvalPending(sessionId: "session-123", sessionName: "Bright Lily"))
        await bridge.notify(.approvalPending(sessionId: "session-123", sessionName: "Bright Lily"))

        let calls = await sender.calls
        let startCount = calls.filter { call in
            let object = try? JSONSerialization.jsonObject(with: call.payload)
            let json = object as? [String: Any]
            let aps = json?["aps"] as? [String: Any]
            return aps?["event"] as? String == "start"
        }.count
        #expect(startCount == 1)
    }
}

private actor RecordingBridgeSender: APNsNotificationSending {
    struct Call: Sendable {
        let registration: DeviceTokenRegistration
        let pushType: APNsPushType
        let payload: Data
    }

    private(set) var calls: [Call] = []

    func send(
        registration: DeviceTokenRegistration,
        collapseID: String,
        payload: Data
    ) async throws -> APNsSendResult {
        calls.append(.init(registration: registration, pushType: .alert, payload: payload))
        return .success
    }

    func send(
        registration: DeviceTokenRegistration,
        collapseID: String,
        payload: Data,
        pushType: APNsPushType
    ) async throws -> APNsSendResult {
        calls.append(.init(registration: registration, pushType: pushType, payload: payload))
        return .success
    }
}
