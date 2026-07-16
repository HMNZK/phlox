import Foundation
import Testing
@testable import DesignSystem

// DSColor.chat* が固定 RGB でなく現在の AppTheme（ThemeStore.active）へ委譲し、テーマ切替に追従することを検証する。
// ThemeStore.active は UserDefaults.standard 固定依存のため、テーマ切替の検証には standard を一時的に書き換える必要がある。
// 並列実行で他テストの ThemeStore.active 読み取りと干渉するのを避けるため、本スイートのみ .serialized とする（恒久措置ではなく本依存構造ゆえの一時措置）。
@Suite(.serialized)
struct ChatTokenThemeTests {
    @Test @MainActor
    func chatTokensFollowActiveThemeSelection() {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: ThemeStore.themeKey)
        defer {
            if let previous {
                defaults.set(previous, forKey: ThemeStore.themeKey)
            } else {
                defaults.removeObject(forKey: ThemeStore.themeKey)
            }
        }

        defaults.set(AppTheme.phlox.id, forKey: ThemeStore.themeKey)
        #expect(DSColor.chatBackground == AppTheme.phlox.background.color)
        #expect(DSColor.chatTextPrimary == AppTheme.phlox.textPrimary.color)
        #expect(DSColor.chatAccent == AppTheme.phlox.accent.color)

        defaults.set(AppTheme.nord.id, forKey: ThemeStore.themeKey)
        #expect(DSColor.chatBackground == AppTheme.nord.background.color)
        #expect(DSColor.chatTextPrimary == AppTheme.nord.textPrimary.color)
        #expect(DSColor.chatAccent == AppTheme.nord.accent.color)

        // phlox と nord で色が実際に異なる（＝固定でなくテーマ追従している）ことを確認
        #expect(AppTheme.phlox.background.color != AppTheme.nord.background.color)
    }
}
