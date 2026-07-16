import Foundation
import Testing
import PhloxCore
import Features

// task-3 受け入れテスト（PM 著・凍結。実装役は編集禁止 — ハーネス欠陥は PM 承認の上ハーネス部分のみ修理可）。
// 通知タップ→遷移要求の契約（前方互換・consume の原子性）を固定する。
// ※ このファイルは task-3 ディスパッチ時に Packages/PhloxKit/Tests/FeaturesTests/ へ配置・コミットされる。

@MainActor
struct PushCoordinatorAcceptanceTests {

    private func tapUserInfo(type: String = "session_completed", sessionId: String? = "sess-9") -> [AnyHashable: Any] {
        var phlox: [String: Any] = ["v": 1, "type": type]
        if let sessionId { phlox["sessionId"] = sessionId }
        return ["aps": ["alert": ["title": "t", "body": "b"]], "phlox": phlox]
    }

    @Test func session_completedのタップで遷移要求が積まれる() {
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: tapUserInfo(type: "session_completed"))
        #expect(coordinator.pendingSessionID == "sess-9")
    }

    @Test func approval_pendingのタップで遷移要求が積まれる() {
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: tapUserInfo(type: "approval_pending"))
        #expect(coordinator.pendingSessionID == "sess-9")
    }

    @Test func 未知typeでもsessionIdがあれば遷移する() {
        // タップ遷移は type 非依存の汎用挙動（前方互換: 未知 type でクラッシュ・誤動作しない）
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: tapUserInfo(type: "future_event"))
        #expect(coordinator.pendingSessionID == "sess-9")
    }

    @Test func 解釈不能なuserInfoは無視する() {
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: ["aps": ["alert": ["title": "t"]]])
        #expect(coordinator.pendingSessionID == nil)
        coordinator.handleNotificationTap(userInfo: tapUserInfo(sessionId: nil))
        #expect(coordinator.pendingSessionID == nil)
    }

    @Test func consumeで取り出すとクリアされる() {
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: tapUserInfo())
        #expect(coordinator.consumePendingSessionID() == "sess-9")
        #expect(coordinator.pendingSessionID == nil)
        #expect(coordinator.consumePendingSessionID() == nil)
    }

    @Test func 連続タップは後勝ち() {
        let coordinator = PushCoordinator()
        coordinator.handleNotificationTap(userInfo: tapUserInfo(sessionId: "first"))
        coordinator.handleNotificationTap(userInfo: tapUserInfo(sessionId: "second"))
        #expect(coordinator.pendingSessionID == "second")
    }
}
