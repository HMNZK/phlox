import Foundation
import Testing
import APNsClient
import AgentDomain
import SessionFeature
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
            "summary": "承認待ち",
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

// C-62・B5・C-60: パソコンの通知と同じ種類をスマホにも送る。中身（質問文など）は入れず、種類の言葉だけ。
extension LiveActivityBridgeTests {
    @Test(arguments: [
        (RemoteSessionNotification.question, "question_pending", "質問があります", "update", 900),
        (.error, "session_error", "エラーで止まりました", "update", 900),
        (.stalled, "session_stalled", "応答がありません", "update", 900),
        (.exited(code: 2), "session_exited", "セッションが終了しました · exit 2", "end", 60),
    ])
    func eachKindIsSentWithItsOwnTypeAndWords(
        kind: RemoteSessionNotification, type: String, summary: String, event: String, stale: Int
    ) async throws {
        let store = InMemoryDeviceTokenStore()
        try store.upsert(try #require(DeviceTokenRegistration(
            deviceToken: "abcdef0123456789",
            bundleId: "com.phlox.mobile.PhloxMobile",
            environment: .sandbox
        )))
        try store.upsert(try #require(DeviceTokenRegistration(
            deviceToken: "1234567890abcdef",
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

        await bridge.notify(APNsNotificationBridge.NotificationEvent(kind: kind, sessionId: "session-123", sessionName: "Bright Lily"))

        let calls = await sender.calls
        let alert = try #require(calls.first { $0.pushType != .liveactivity })
        let alertJSON = try #require(JSONSerialization.jsonObject(with: alert.payload) as? [String: Any])
        #expect((alertJSON["phlox"] as? [String: Any])?["type"] as? String == type)
        #expect(((alertJSON["aps"] as? [String: Any])?["alert"] as? [String: String])?["body"] == summary)
        let activity = try #require(calls.first { $0.pushType == .liveactivity })
        let aps = try #require((try JSONSerialization.jsonObject(with: activity.payload) as? [String: Any])?["aps"] as? [String: Any])
        #expect(aps["event"] as? String == event)
        #expect(aps["stale-date"] as? Int == 1_700_000_000 + stale)
        #expect((aps["content-state"] as? [String: String])?["status"] == type)
        #expect((aps["content-state"] as? [String: String])?["summary"] == summary)
    }
}
