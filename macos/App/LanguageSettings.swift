import Foundation

/// アプリ内表示言語の選択肢。`@AppStorage` に rawValue を保存する。
enum AppLanguage: String {
    /// OS の言語設定に追従する。
    case system
    case ja
    case en

    /// SwiftUI の `\.locale` 環境値に注入する Locale。
    /// `.system` は OS 設定の変更に追従する autoupdatingCurrent を返す。
    var locale: Locale {
        switch self {
        case .system: Locale.autoupdatingCurrent
        case .ja: Locale(identifier: "ja")
        case .en: Locale(identifier: "en")
        }
    }
}

/// アプリ内表示言語の設定の単一の真実源。
/// App 層の @AppStorage（言語選択 Picker と環境注入）が同じキーを参照する。
/// 未設定キーは "system"（OS 追従）扱い。
enum LanguageSettings {
    static let languageKey = "phlox.appLanguage"

    /// 起動時に UserDefaults.register(defaults:) へ渡す既定値。
    static var defaultsDictionary: [String: Any] {
        [languageKey: AppLanguage.system.rawValue]
    }
}
