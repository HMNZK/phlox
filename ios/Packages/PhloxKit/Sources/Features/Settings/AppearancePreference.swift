import SwiftUI
import DesignSystemIOS

public enum AppearancePreference: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: "システム"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    public var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    public func themeID(systemColorScheme: ColorScheme) -> String {
        switch self {
        case .system:
            systemColorScheme == .light ? AppTheme.phloxLight.id : AppTheme.phlox.id
        case .light:
            AppTheme.phloxLight.id
        case .dark:
            AppTheme.phlox.id
        }
    }
}
