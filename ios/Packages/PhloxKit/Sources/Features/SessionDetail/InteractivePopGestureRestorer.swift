import Foundation

/// ナビゲーションバーを隠した画面（セッション詳細）で、iOS 標準の端スワイプ pop を復活させる
/// ための判定層。UIKit へ依存しないので macOS ホストの `swift test` で検証できる。
///
/// 公開面は PM が凍結した契約面（task-1 の入出力契約）。振る舞いの実装と UIKit への接続は task-1 が行う。
/// 契約の正本: Tests/FeaturesTests/AcceptanceSessionViewUXTests.swift
public protocol InteractivePopGestureHost: AnyObject {
    /// ナビゲーションスタックに積まれている画面数（1 は根の画面＝戻れない）。
    var navigationStackDepth: Int { get }
    /// 端スワイプ pop ジェスチャが有効か。
    var isInteractivePopGestureEnabled: Bool { get set }
}

public enum InteractivePopGestureRestorer {
    /// 端スワイプ pop を有効に戻す。
    ///
    /// - Returns: 有効化した（または既に有効だった）なら true。根の画面では触らず false。
    @discardableResult
    public static func restore(on host: some InteractivePopGestureHost) -> Bool {
        // TODO(task-1): 深さ2以上なら isInteractivePopGestureEnabled を true にして true を返す。
        _ = host.navigationStackDepth
        return false
    }
}
