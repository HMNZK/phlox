import Foundation
import Testing
@testable import DashboardFeature

/// task-17（T2）白箱テスト。動作に影響する設定（Usage・hooks）が、指定 suite の
/// `UserDefaults` を経由したとき `.standard` から隔離されることを検証する
/// （stage1 レビュー MEDIUM 指摘への対応: UsageSettings/UsageMonitor/CodexUserHooksSettings の隔離漏れを塞ぐ）。
@Suite struct BehaviorAffectingSettingsSuiteTests {
    private func makeSuite() -> (UserDefaults, String) {
        // suite 名はテストごとに一意にする。固定名だと並列実行時に他テストの
        // removePersistentDomain が set と read の間に割り込み、読み戻しが false になる（実測）。
        let name = "phlox.e2e.behavior-settings.test.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        suite.removePersistentDomain(forName: name)
        return (suite, name)
    }

    @Test func usageSettings_autoRefresh_readsFromSuite_isolatedFromStandard() {
        let (suite, name) = makeSuite()
        defer { suite.removePersistentDomain(forName: name) }
        let key = UsageSettings.autoRefreshKey
        UserDefaults.standard.removeObject(forKey: key)

        suite.set(false, forKey: key)
        #expect(UsageSettings.isAutoRefreshEnabled(defaults: suite) == false)
        // .standard は未設定＝既定 true のまま（汚染されていない）
        #expect(UsageSettings.isAutoRefreshEnabled(defaults: .standard) == true)
    }

    @Test func codexUserHooks_setEnabled_writesToSuite_isolatedFromStandard() {
        let (suite, name) = makeSuite()
        defer { suite.removePersistentDomain(forName: name) }
        let key = CodexUserHooksSettings.enabledKey
        UserDefaults.standard.removeObject(forKey: key)

        CodexUserHooksSettings.setEnabled(true, defaults: suite)
        #expect(CodexUserHooksSettings.isEnabled(defaults: suite) == true)
        // .standard は書き込まれていない
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }
}
