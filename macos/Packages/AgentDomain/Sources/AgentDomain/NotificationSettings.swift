import Foundation

/// セッション完了通知に関する設定（バナー通知・完了サウンド）の単一の真実源。
/// App 層の @AppStorage と DashboardFeature 内の通知発火の双方が同じキーを参照する。
/// 未設定キーは true 扱い（既定で現行挙動＝通知/音あり を維持）。
public enum NotificationSettings {
    public static let bannerKey = "phlox.notify.banner"
    public static let soundKey = "phlox.notify.sound"

    /// 起動時に UserDefaults.register(defaults:) へ渡す既定値。
    public static var defaultsDictionary: [String: Any] {
        [
            bannerKey: true,
            soundKey: true,
        ]
    }

    public static func isBannerEnabled(defaults: UserDefaults = .phloxDefaults()) -> Bool {
        enabled(forKey: bannerKey, defaults: defaults)
    }

    public static func isSoundEnabled(defaults: UserDefaults = .phloxDefaults()) -> Bool {
        enabled(forKey: soundKey, defaults: defaults)
    }

    private static func enabled(forKey key: String, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }
}
