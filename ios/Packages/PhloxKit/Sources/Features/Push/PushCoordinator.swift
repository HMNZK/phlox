import Observation
import PhloxCore

/// 通知タップと SwiftUI ナビゲーションの中継点。
/// AppDelegate（task-4）が userInfo を渡し、AppRoot（task-4）が pendingSessionID を監視して
/// router.push(.sessionDetail(id:)) → consume する。
@MainActor
@Observable
public final class PushCoordinator {
    /// タップ由来の未処理遷移要求。AppRoot が消費するまで保持する。
    public private(set) var pendingSessionID: String?

    public init() {}

    /// 通知タップ時に AppDelegate から呼ぶ。契約 v1 ペイロードとして解釈できれば遷移要求を積む。
    /// 未知 type でも sessionId があれば遷移する（タップ遷移は type 非依存の汎用挙動。前方互換）。
    /// 解釈不能（phlox 欠落・sessionId 欠落）なら何もしない（クラッシュしない）。
    public func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        guard let payload = PhloxPushPayload(userInfo: userInfo) else {
            return
        }
        pendingSessionID = payload.sessionID
    }

    /// 遷移要求を取り出してクリアする（なければ nil）。
    public func consumePendingSessionID() -> String? {
        let id = pendingSessionID
        pendingSessionID = nil
        return id
    }
}
