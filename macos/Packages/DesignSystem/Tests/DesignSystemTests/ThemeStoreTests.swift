import Foundation
import Observation
import Testing
@testable import DesignSystem

/// suiteName 付き UserDefaults で分離し、共有の UserDefaults.standard を汚さない。
private func withIsolatedDefaults<T>(_ body: (UserDefaults) throws -> T) throws -> T {
    let suiteName = "design-system-theme-store-tests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    return try body(defaults)
}

@Suite struct ThemeStoreResolutionTests {
    @Test func knownIDResolvesToThatTheme() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("tokyo-night", forKey: ThemeStore.themeKey)
            #expect(ThemeStore.active(in: defaults).id == "tokyo-night")
        }
    }

    @Test func unknownIDFallsBackToPhlox() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("no-such-theme", forKey: ThemeStore.themeKey)
            #expect(ThemeStore.active(in: defaults).id == AppTheme.phlox.id)
        }
    }

    @Test func missingValueFallsBackToPhlox() throws {
        try withIsolatedDefaults { defaults in
            #expect(ThemeStore.active(in: defaults).id == AppTheme.phlox.id)
        }
    }

    @Test func allThemeIDsAreUnique() {
        let ids = ThemeStore.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// テーマ変更（選択 id の書き換え）が次のアクセスへ即時反映される。
    /// P7 のキャッシュ導入後も、この「変更時のみ無効化」の振る舞いが保たれることを固定する。
    @Test func changingSelectionIsReflectedOnNextAccess() throws {
        try withIsolatedDefaults { defaults in
            defaults.set("dracula", forKey: ThemeStore.themeKey)
            #expect(ThemeStore.active(in: defaults).id == "dracula")
            defaults.set("nord", forKey: ThemeStore.themeKey)
            #expect(ThemeStore.active(in: defaults).id == "nord")
        }
    }
}

/// テーマを読んだ View がテーマ変更で必ず描き直されること（テーマ切替で前の色が残る不具合の再発防止）。
@Suite @MainActor struct ThemeChangeSignalTests {
    @Test func changingThemeNotifiesObservers() async throws {
        let suiteName = "design-system-theme-signal-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set("dracula", forKey: ThemeStore.themeKey)
        let signal = ThemeChangeSignal(defaults: defaults)

        let fired = Box()
        withObservationTracking { signal.track() } onChange: { fired.value = true }
        defaults.set("phlox-light", forKey: ThemeStore.themeKey)
        for _ in 0 ..< 50 where !fired.value { try await Task.sleep(for: .milliseconds(20)) }
        #expect(fired.value)
    }

    @Test func unrelatedDefaultsChangeDoesNotNotify() async throws {
        let suiteName = "design-system-theme-signal-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let signal = ThemeChangeSignal(defaults: defaults)

        let fired = Box()
        withObservationTracking { signal.track() } onChange: { fired.value = true }
        defaults.set(true, forKey: "unrelated.key")
        try await Task.sleep(for: .milliseconds(200))
        #expect(!fired.value)
    }
}

private final class Box: @unchecked Sendable { var value = false }
