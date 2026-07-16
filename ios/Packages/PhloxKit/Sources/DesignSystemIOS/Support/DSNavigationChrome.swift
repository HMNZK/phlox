import SwiftUI
import DesignSystem
import Foundation
#if canImport(UIKit)
import UIKit
#endif

private final class DSNavigationChromeAppearanceInstaller: @unchecked Sendable {
    private let lock = NSLock()
    private var themeID: String?
    private var installationCount = 0

    var state: DSNavigationChrome.AppearanceInstallationState {
        lock.lock()
        defer { lock.unlock() }
        return .init(themeID: themeID, installationCount: installationCount)
    }

    func installIfNeeded(for themeID: String, install: () -> Void) {
        lock.lock()
        defer { lock.unlock() }

        guard self.themeID != themeID else { return }
        install()
        self.themeID = themeID
        installationCount += 1
    }
}

/// 現在テーマに追随するカンプ準拠のナビゲーションバー。
public enum DSNavigationChrome {
    public struct AppearanceInstallationState: Equatable, Sendable {
        public let themeID: String?
        public let installationCount: Int
    }

    private static let appearanceInstaller = DSNavigationChromeAppearanceInstaller()

    /// UIKit appearance の最終適用状態。再入時に再適用していないことを回帰テストで検証するため公開する。
    public static var appearanceInstallationState: AppearanceInstallationState {
        appearanceInstaller.state
    }

    public static var barBackground: Color { DSColor.surface }
    public static var accentTint: Color { DSColor.campAccentBright }

    /// 既存呼び出しとの互換用。固定値ではなく現在テーマから都度決定する。
    public static var barColorScheme: ColorScheme {
        barColorScheme(for: ThemeStore.active.id)
    }

    /// ナビゲーションバーの配色をテーマ id から決定する。
    /// 未知のテーマは既定の Phlox と同じ dark にフォールバックする。
    public static func barColorScheme(for themeID: String) -> ColorScheme {
        switch themeID {
        case AppTheme.phloxLight.id:
            return .light
        case AppTheme.phlox.id:
            return .dark
        default:
            return .dark
        }
    }

    /// Large / Inline タイトル色を `textPrimary` に固定（`toolbarColorScheme` だけでは不足する場合の保険）。
    #if canImport(UIKit)
    @MainActor
    #endif
    public static func installUIKitAppearanceIfNeeded() {
        installUIKitAppearanceIfNeeded(for: ThemeStore.active.id)
    }

    /// AppRoot の再マウントでは同一テーマを無視し、実際のテーマ変更時だけ再適用する。
    #if canImport(UIKit)
    @MainActor
    #endif
    public static func installUIKitAppearanceIfNeeded(for themeID: String) {
        appearanceInstaller.installIfNeeded(for: themeID) {
            #if canImport(UIKit)
            let surface = UIColor(barBackground)
            let title = UIColor(DSColor.textPrimary)
            let accent = UIColor(accentTint)
            let colorScheme = barColorScheme(for: themeID)

            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = surface
            appearance.shadowColor = .clear
            appearance.largeTitleTextAttributes = [.foregroundColor: title]
            appearance.titleTextAttributes = [.foregroundColor: title]

            let navigationBar = UINavigationBar.appearance()
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
            navigationBar.compactScrollEdgeAppearance = appearance
            navigationBar.tintColor = accent
            navigationBar.barStyle = colorScheme == .light ? .default : .black
            #endif
        }
    }
}

private struct DSCampNavigationChromeModifier: ViewModifier {
    @AppStorage(ThemeStore.themeKey) private var themeID = AppTheme.phlox.id

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .toolbarBackground(DSNavigationChrome.barBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(
                DSNavigationChrome.barColorScheme(for: themeID),
                for: .navigationBar
            )
            .onAppear {
                DSNavigationChrome.installUIKitAppearanceIfNeeded(for: themeID)
            }
            .onChange(of: themeID) { _, newThemeID in
                DSNavigationChrome.installUIKitAppearanceIfNeeded(for: newThemeID)
            }
        #else
        content
        #endif
    }
}

public extension View {
    /// ナビゲーションバーを現在テーマの chrome に統一する。`NavigationStack` または各画面に適用。
    func dsCampNavigationChrome() -> some View {
        modifier(DSCampNavigationChromeModifier())
    }
}
