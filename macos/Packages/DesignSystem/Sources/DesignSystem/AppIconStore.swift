import Foundation

/// 選択肢として提示するアプリアイコンの 1 種。
/// - `assetName` は App ターゲットの `Assets.xcassets`（`Bundle.main`）にある imageset 名。
///   画像の読み込み（`NSImage(named:)`）や Dock への適用（`NSApp.applicationIconImage`）は
///   App ターゲット側で行い、このストア自体は id ↔ アセット名の解決だけを担う純ロジックにする。
public struct AppIconOption: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let assetName: String

    public init(id: String, name: String, assetName: String) {
        self.id = id
        self.name = name
        self.assetName = assetName
    }
}

/// 選択中アプリアイコンを解決するストア。`ThemeStore` と同型。
/// 変更は `NSApp.applicationIconImage` へ即時適用し、選択値は UserDefaults に永続、起動時に再適用する。
public enum AppIconStore {
    public static let iconKey = "phlox.appIcon"

    /// 選択肢の全て。先頭が既定（ホワイト背景。`AppIcon.appiconset` と同一デザイン）。
    public static let all: [AppIconOption] = [
        AppIconOption(id: "white", name: "ホワイト", assetName: "AppIconVariantWhite"),
        AppIconOption(id: "dark-grad", name: "ダーク＋グラデ", assetName: "AppIconVariantDarkGrad"),
        AppIconOption(id: "dark", name: "ダーク", assetName: "AppIconVariantDark"),
        AppIconOption(id: "gradient", name: "グラデーション", assetName: "AppIconVariantGradient"),
        AppIconOption(id: "light", name: "ライト", assetName: "AppIconVariantLight"),
    ]

    /// 既定アイコン（`AppIcon.appiconset` と同じデザイン）。
    public static var defaultOption: AppIconOption { all[0] }

    /// 起動時 `register(defaults:)` 用。
    public static var defaultsDictionary: [String: Any] { [iconKey: defaultOption.id] }

    /// id に対応する選択肢。未知の id・nil はいずれも既定へフォールバックする。
    public static func option(forID id: String?) -> AppIconOption {
        all.first { $0.id == id } ?? defaultOption
    }

    /// 選択中の選択肢。未設定・未知の id はいずれも既定へフォールバックする。
    public static func selected(in defaults: UserDefaults) -> AppIconOption {
        option(forID: defaults.string(forKey: iconKey))
    }
}
