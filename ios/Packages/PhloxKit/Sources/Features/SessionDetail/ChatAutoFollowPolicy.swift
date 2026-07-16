import Foundation

/// チャットの自動追従スクロール判定（Phlox 本体 ChatAutoFollow の閾値仕様の移植）。
/// 「最下部付近にいる時だけ新着で追従する」の純粋な判定部。View 側（task-8）がスクロール
/// オフセットから distanceFromBottom を計測してこれに委譲する。
/// 契約は Tests/FeaturesTests/ChatSurfaceAcceptanceTests.swift。
public enum ChatAutoFollowPolicy {
    /// 追従を維持する最下部からの距離の閾値（pt）。本体 ChatAutoFollow と同じ 80pt。
    public static let followThreshold: CGFloat = 80

    /// 最下部からの距離が閾値以内なら true（新着で最下部へ追従する）。
    public static func shouldFollowBottom(distanceFromBottom: CGFloat) -> Bool {
        distanceFromBottom <= followThreshold
    }
}
