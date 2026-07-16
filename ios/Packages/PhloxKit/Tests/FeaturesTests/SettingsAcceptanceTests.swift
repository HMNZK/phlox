import Testing
import SwiftUI
import PhloxCore
@testable import Features

/// task-5 設定画面の凍結受け入れテスト（PM 著・実装役は編集禁止）。
/// 4機能（外観ライブ切替・設定永続化・Face ID 本配線・通知ゲート）の純ロジック契約を検証する。
/// View 配線（preferredColorScheme 適用・onChange 再ロック・AppDelegate ゲート・セクション UI）は
/// iOS シミュレータビルド＋二段レビュー＋フェーズ4統合で確認する（ここでは純コアのみ）。
@Suite("task-5 設定画面 受け入れ")
@MainActor
struct SettingsAcceptanceTests {

    // MARK: - 外観（ハザード核心）

    @Test("外観プリファレンスは preferredColorScheme を決める（system は OS 追従で nil）")
    func appearanceMapsToPreferredColorScheme() {
        #expect(AppearancePreference.system.preferredColorScheme == nil)
        #expect(AppearancePreference.light.preferredColorScheme == .light)
        #expect(AppearancePreference.dark.preferredColorScheme == .dark)
    }

    @Test("外観プリファレンスは DSColor 用テーマ id を決める（system は OS colorScheme から light/dark）")
    func appearanceMapsToThemeID() {
        // light/dark は OS colorScheme に依らず固定
        #expect(AppearancePreference.light.themeID(systemColorScheme: .dark) == "phlox-light")
        #expect(AppearancePreference.light.themeID(systemColorScheme: .light) == "phlox-light")
        #expect(AppearancePreference.dark.themeID(systemColorScheme: .light) == "phlox")
        #expect(AppearancePreference.dark.themeID(systemColorScheme: .dark) == "phlox")
        // system は OS colorScheme を追従
        #expect(AppearancePreference.system.themeID(systemColorScheme: .light) == "phlox-light")
        #expect(AppearancePreference.system.themeID(systemColorScheme: .dark) == "phlox")
    }

    @Test("外観プリファレンスは3択を過不足なく列挙する")
    func appearanceEnumeratesAllChoices() {
        #expect(AppearancePreference.allCases == [.system, .light, .dark])
    }

    // MARK: - 設定の永続化

    @Test("設定ストアは未設定時に既定（faceID=OFF/通知=ON/外観=system）を返す")
    func settingsStoreReturnsDefaultsWhenUnset() {
        // wave-7: 顔認証は既定オフ（新規インストール時にロックしない）。
        let suite = "task5-accept-defaults-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UserDefaultsAppSettingsStore(defaults: defaults)

        #expect(store.faceIDEnabled == false)
        #expect(store.notificationsEnabled == true)
        #expect(store.appearance == .system)
    }

    @Test("設定ストアは faceID/通知/外観を永続化し別インスタンスで復元する")
    func settingsStorePersistsAllValues() {
        let suite = "task5-accept-persist-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = UserDefaultsAppSettingsStore(defaults: defaults)
        store.faceIDEnabled = false
        store.notificationsEnabled = false
        store.appearance = .light

        let reopened = UserDefaultsAppSettingsStore(defaults: defaults)
        #expect(reopened.faceIDEnabled == false)
        #expect(reopened.notificationsEnabled == false)
        #expect(reopened.appearance == .light)
    }

    @Test("AppSettings の変更はストアへ書き戻され、同一ストアからの再構築で復元する")
    func appSettingsWritesThroughToStore() {
        let store = InMemoryAppSettingsStore()
        let settings = AppSettings(store: store)

        settings.faceIDEnabled = false
        settings.appearance = .dark

        #expect(store.faceIDEnabled == false)
        #expect(store.appearance == .dark)

        let rebuilt = AppSettings(store: store)
        #expect(rebuilt.faceIDEnabled == false)
        #expect(rebuilt.appearance == .dark)
    }

    // MARK: - Face ID 本配線（状態機械）

    @Test("Face ID 有効なら起動時 locked、無効なら unlocked")
    func faceIDGatesInitialAuthState() {
        #expect(AppModel.initialAuthState(faceIDEnabled: true) == .locked)
        #expect(AppModel.initialAuthState(faceIDEnabled: false) == .unlocked)
    }

    @Test("背景移行時、Face ID 有効なら再ロックし、無効・前面では再ロックしない")
    func faceIDRelocksOnBackgroundOnly() {
        #expect(AppModel.shouldRelock(scenePhase: .background, faceIDEnabled: true) == true)
        #expect(AppModel.shouldRelock(scenePhase: .background, faceIDEnabled: false) == false)
        #expect(AppModel.shouldRelock(scenePhase: .active, faceIDEnabled: true) == false)
        #expect(AppModel.shouldRelock(scenePhase: .inactive, faceIDEnabled: true) == false)
    }

    // MARK: - 通知ゲート

    @Test("通知トグルが APNs 登録可否を決める")
    func notificationToggleGatesRegistration() {
        #expect(NotificationRegistrationPolicy.shouldRegister(notificationsEnabled: true) == true)
        #expect(NotificationRegistrationPolicy.shouldRegister(notificationsEnabled: false) == false)
    }
}
