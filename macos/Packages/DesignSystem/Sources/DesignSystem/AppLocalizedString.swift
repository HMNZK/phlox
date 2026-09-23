import Foundation

/// `Text` に渡せない（`String` が要る）文言を、アプリ内の表示言語で App/Localizable.xcstrings から引く。
/// `String(localized:)` は OS の言語に従うため、表示言語の設定と食い違う。
public enum AppLocalizedString {
    /// キー（日本語）に対する表示言語の訳。訳が無ければキーをそのまま返す（日本語表示）。
    public static func string(_ key: String, locale: Locale, bundle: Bundle = .main) -> String {
        guard let code = locale.language.languageCode?.identifier, code != "ja",
              let path = bundle.path(forResource: code, ofType: "lproj"),
              let localized = Bundle(path: path)
        else { return key }
        return localized.localizedString(forKey: key, value: key, table: nil)
    }
}
