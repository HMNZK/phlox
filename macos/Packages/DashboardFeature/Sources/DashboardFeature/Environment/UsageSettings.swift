import Foundation
import AgentDomain

/// CLI 使用量モニタに関する設定の単一の真実源。
/// App 層の @AppStorage と UsageMonitor の双方が同じキーを参照する。
/// 未設定キーは true 扱い（既定で自動更新・Claude スクレイプ有効）。
public enum UsageSettings {
    public static let autoRefreshKey = "phlox.usage.autoRefresh"
    public static let claudeScrapeKey = "phlox.usage.claudeScrape"
    public static let showUnavailableKey = "phlox.usage.showUnavailable"

    public static var defaultsDictionary: [String: Any] {
        [
            autoRefreshKey: true,
            claudeScrapeKey: true,
            showUnavailableKey: false,
        ]
    }

    public static func isAutoRefreshEnabled(defaults: UserDefaults = .phloxDefaults()) -> Bool {
        enabled(forKey: autoRefreshKey, defaults: defaults)
    }

    public static func isClaudeScrapeEnabled(defaults: UserDefaults = .phloxDefaults()) -> Bool {
        enabled(forKey: claudeScrapeKey, defaults: defaults)
    }

    private static func enabled(forKey key: String, defaults: UserDefaults) -> Bool {
        guard defaults.object(forKey: key) != nil else { return true }
        return defaults.bool(forKey: key)
    }
}
