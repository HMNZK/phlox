import SwiftUI

/// `NavigationStack` の `NavigationPath` とモーダル提示を一元管理する軽量 Router（E4-10）。
/// 遷移ロジックを View に直書きせず、すべて本 Router 経由にする。
@MainActor
@Observable
public final class NavigationRouter {
    /// スタック遷移のパス。`NavigationStack(path:)` にバインドする。
    public var path = NavigationPath()
    /// 現在提示中のモーダル（削除確認・Codex 4 択など）。
    public var presented: Route?

    public init() {}

    /// 現在のスタック深さ（テスト用の観測点）。
    public var depth: Int { path.count }

    public func push(_ route: Route) {
        path.append(route)
    }

    public func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    public func popToRoot() {
        path = NavigationPath()
    }

    public func present(_ route: Route) {
        presented = route
    }

    public func dismiss() {
        presented = nil
    }
}
