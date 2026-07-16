import Foundation
import Testing
import PhloxCore
import Features

@MainActor
struct PushCoordinatorTests {

    private func tapUserInfo(type: String = "session_completed", sessionId: String = "sess-1") -> [AnyHashable: Any] {
        [
            "aps": ["alert": ["title": "t", "body": "b"]],
            "phlox": ["v": 1, "type": type, "sessionId": sessionId] as [String: Any],
        ]
    }

    @Test func 初期状態では遷移要求はない() {
        let coordinator = PushCoordinator()
        #expect(coordinator.pendingSessionID == nil)
        #expect(coordinator.consumePendingSessionID() == nil)
    }

    @Test func consumeは取り出しとクリアが一体() {
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: tapUserInfo(sessionId: "sess-42"))
        let consumed = coordinator.consumePendingSessionID()
        #expect(consumed == "sess-42")
        #expect(coordinator.pendingSessionID == nil)
    }

    @Test func consume後に再度タップできる() {
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: tapUserInfo(sessionId: "first"))
        #expect(coordinator.consumePendingSessionID() == "first")

        coordinator.handleNotificationTap(userInfo: tapUserInfo(sessionId: "second"))
        #expect(coordinator.pendingSessionID == "second")
    }

    @Test func 解釈不能なuserInfoは既存の遷移要求を上書きしない() {
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: tapUserInfo(sessionId: "keep-me"))
        coordinator.handleNotificationTap(userInfo: ["aps": ["alert": ["title": "t"]]])
        #expect(coordinator.pendingSessionID == "keep-me")
    }

    @Test func PhloxPushPayloadと同じsessionIdが積まれる() {
        let userInfo: [AnyHashable: Any] = [
            "phlox": ["sessionId": "from-payload", "type": "session_completed"] as [String: Any],
        ]
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: userInfo)
        #expect(coordinator.pendingSessionID == PhloxPushPayload(userInfo: userInfo)?.sessionID)
    }
}
