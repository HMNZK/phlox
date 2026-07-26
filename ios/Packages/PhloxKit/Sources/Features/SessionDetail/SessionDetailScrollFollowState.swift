import Foundation

/// セッション詳細の「開いたら最下部（最新）／以降は最下部付近だけ追従」を決める状態。
///
/// 公開面は PM が凍結した契約面（task-1 の入出力契約）。振る舞いの実装は task-1 が行う。
/// 契約の正本: Tests/FeaturesTests/AcceptanceSessionViewUXTests.swift
public struct SessionDetailScrollFollowState {
    public init() {}

    /// 本文（構造化メッセージ or ターミナル出力）が更新されたときに最下部へ寄せるか。
    ///
    /// - Parameters:
    ///   - hasContent: 描画対象の本文が1件以上あるか（空の通知では初回判定を消費しない）。
    ///   - distanceFromBottom: 末尾アンカーとビューポート下端の距離（pt）。
    /// - Returns: 最下部へスクロールすべきなら true。
    public mutating func onContentChanged(hasContent: Bool, distanceFromBottom: CGFloat) -> Bool {
        guard hasContent else { return false }
        // TODO(task-1): 本文が届いた最初の1回は距離判定を無視して必ず最下部へ寄せる。
        return ChatAutoFollowPolicy.shouldFollowBottom(distanceFromBottom: distanceFromBottom)
    }

    /// セッション切替。次に本文が届いたときを再び「初回」として扱う。
    public mutating func reset() {
        // TODO(task-1)
    }
}
