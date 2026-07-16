import Foundation
import Testing
@testable import Features

@Suite("アプリ設定ストア")
@MainActor
struct AppSettingsStoreTests {
    @Test("未設定の UserDefaults は安全な既定値を返す（wave-7: 顔認証は既定オフ）")
    func userDefaultsReturnsDefaultsWhenKeysAreAbsent() {
        withTemporaryDefaults { defaults in
            let store = UserDefaultsAppSettingsStore(defaults: defaults)

            #expect(!store.faceIDEnabled)
            #expect(store.notificationsEnabled)
            #expect(store.appearance == .system)
        }
    }

    @Test("false と外観を別インスタンスから復元する")
    func userDefaultsPersistsEverySetting() {
        withTemporaryDefaults { defaults in
            let store = UserDefaultsAppSettingsStore(defaults: defaults)
            store.faceIDEnabled = false
            store.notificationsEnabled = false
            store.appearance = .dark

            let reopened = UserDefaultsAppSettingsStore(defaults: defaults)
            #expect(reopened.faceIDEnabled == false)
            #expect(reopened.notificationsEnabled == false)
            #expect(reopened.appearance == .dark)
        }
    }

    @Test("未知の外観値は system にフォールバックする")
    func unknownAppearanceFallsBackToSystem() {
        withTemporaryDefaults { defaults in
            defaults.set("future-appearance", forKey: UserDefaultsAppSettingsStore.appearanceKey)

            #expect(UserDefaultsAppSettingsStore(defaults: defaults).appearance == .system)
        }
    }

    @Test("AppSettings の全変更を注入ストアへ即時反映する")
    func appSettingsWritesThroughEveryProperty() {
        let store = InMemoryAppSettingsStore()
        let settings = AppSettings(store: store)

        settings.faceIDEnabled = false
        settings.notificationsEnabled = false
        settings.appearance = .light

        #expect(store.faceIDEnabled == false)
        #expect(store.notificationsEnabled == false)
        #expect(store.appearance == .light)
    }

    private func withTemporaryDefaults(_ body: (UserDefaults) -> Void) {
        let suiteName = "app-settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        body(defaults)
    }
}
