import Foundation

/// セッション完了通知に関する設定（バナー通知・完了サウンド）の単一の真実源。
/// App 層の @AppStorage と DashboardFeature 内の通知発火の双方が同じキーを参照する。
/// 未設定キーは true 扱い（既定で現行挙動＝通知/音あり を維持）。
public enum NotificationSettings {
    public static let bannerKey = "phlox.notify.banner"
    public static let soundKey = "phlox.notify.sound"
    /// Dock バッジに出す数（10 Settings「バッジに出す数」、C-61）。
    public static let dockBadgeKey = "phlox.notify.dockBadge"
    /// スマホ（APNs・Live Activity）へ送るか（10 Settings L3「プッシュ通知」、C-55）。
    public static let pushKey = "phlox.notify.push"

    /// Dock バッジに出す数。既定は対応待ち（承認待ち・質問待ち・エラー・無応答）の数。
    public enum DockBadgeCount: String, CaseIterable, Sendable {
        case attention
        case unseenCompletions
    }

    /// 起動時に UserDefaults.register(defaults:) へ渡す既定値。
    public static var defaultsDictionary: [String: Any] {
        [
            bannerKey: true,
            soundKey: true,
            dockBadgeKey: DockBadgeCount.attention.rawValue,
            pushKey: true,
        ]
    }

    public static func isBannerEnabled(defaults: UserDefaults = .phloxDefaults()) -> Bool {
        enabled(forKey: bannerKey, defaults: defaults)
    }

    public static func isSoundEnabled(defaults: UserDefaults = .phloxDefaults()) -> Bool {
        enabled(forKey: soundKey, defaults: defaults)
    }

    public static func dockBadgeCount(defaults: UserDefaults = .phloxDefaults()) -> DockBadgeCount {
        DockBadgeCount(rawValue: defaults.string(forKey: dockBadgeKey) ?? "") ?? .attention
    }

    public static func isPushEnabled(defaults: UserDefaults = .phloxDefaults()) -> Bool {
        enabled(forKey: pushKey, defaults: defaults)
    }

    private static func enabled(forKey key: String, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }
}
