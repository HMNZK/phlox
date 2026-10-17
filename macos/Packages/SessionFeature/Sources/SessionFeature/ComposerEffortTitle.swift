import Foundation
import DesignSystem

public func composerEffortTitle(_ value: String, languageCode: String, bundle: Bundle = .main) -> String {
    let key: String
    switch value {
    case "low": key = "低"
    case "medium": key = "中"
    case "high": key = "高"
    case "xhigh": key = "非常に高"
    case "max": key = "最大"
    default: return value
    }
    return AppLocalizedString.string(key, locale: Locale(identifier: languageCode), bundle: bundle)
}
