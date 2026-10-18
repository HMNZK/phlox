import Observation
import PhloxCore
import Foundation

/// 通知・ウィジェット・Live Activity のタップと SwiftUI ナビゲーションの中継点。
/// AppRoot が pendingSessionID を監視し、解除・一覧取得後に openPendingSession で開く。
@MainActor
@Observable
public final class PushCoordinator {
    /// タップ由来の未処理遷移要求。AppRoot が消費するまで保持する。
    public private(set) var pendingSessionID: String?
    private var pendingRequestedAt: Date?

    public init() {}

    public enum Destination: Equatable {
        case session(String)
        case notFound
    }

    /// ウィジェット・Live Activity も通知と同じ保留要求へ送る。
    @discardableResult
    public func handleSessionURL(_ url: URL) -> Bool {
        guard let id = SessionURL.sessionID(from: url) else { return false }
        pendingSessionID = id
        pendingRequestedAt = Date()
        return true
    }

    /// ロック中・取得前・通信失敗では要求を保持し、取得成功後だけ存在を判定する。
    public func openPendingSession(
        canNavigate: Bool, listState: SessionsState, fetchedAt: Date?, router: NavigationRouter
    ) -> Destination? {
        guard canNavigate, let id = pendingSessionID,
              let requestedAt = pendingRequestedAt, let fetchedAt, fetchedAt >= requestedAt else { return nil }
        let sessions: [Session]
        switch listState {
        case .loaded(let values): sessions = values
        case .empty: sessions = []
        case .loading, .offline, .error: return nil
        }
        _ = consumePendingSessionID()
        router.dismiss()
        router.popToRoot()
        guard sessions.contains(where: { $0.id == id }) else { return .notFound }
        router.push(.sessionDetail(id: id))
        return .session(id)
    }

    /// 通知タップ時に AppDelegate から呼ぶ。契約 v1 ペイロードとして解釈できれば遷移要求を積む。
    /// 未知 type でも sessionId があれば遷移する（タップ遷移は type 非依存の汎用挙動。前方互換）。
    /// 解釈不能（phlox 欠落・sessionId 欠落）なら何もしない（クラッシュしない）。
    public func handleNotificationTap(userInfo: [AnyHashable: Any]) {
        guard let payload = PhloxPushPayload(userInfo: userInfo) else {
            return
        }
        pendingSessionID = payload.sessionID
        pendingRequestedAt = Date()
    }

    /// 遷移要求を取り出してクリアする（なければ nil）。
    public func consumePendingSessionID() -> String? {
        let id = pendingSessionID
        pendingSessionID = nil
        pendingRequestedAt = nil
        return id
    }
}
