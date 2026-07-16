import Foundation

/// Mac への到達性。物理ネットワーク有無（一層目）と Phlox 応答可否（二層目）を区別する。
/// 「圏外」（`offlineNetwork`）と「Mac スリープ等で応答なし」（`unreachableHost`）を分けることで、
/// カンプ⑩⑪ の状態（E4-4）が適切な回復導線を出せる。
public enum Reachability: Sendable, Equatable {
    /// 判定前。
    case unknown
    /// ネットワークあり + Phlox 応答あり。
    case online
    /// 物理ネットワークなし（圏外 / 機内モード）。
    case offlineNetwork
    /// ネットワークはあるが Phlox が応答しない（Mac スリープ / プロキシ停止）。
    case unreachableHost
}

/// 到達性監視（DI シーム）。実体は `NWPathMonitor` + `/sessions` ヘルスチェック（PhloxReachability / E3-4）。
public protocol ReachabilityMonitoring: Sendable {
    /// 現在の到達性。
    var current: Reachability { get async }
    /// 現在のネットワーク状態で到達性を再判定する。
    func refresh() async
    /// 到達性の変化を配信するストリーム（購読開始時に現在値を 1 回流す）。
    func stream() -> AsyncStream<Reachability>
}
