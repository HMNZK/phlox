import Foundation
import Testing
@testable import DashboardFeature

/// task-17（T2）白箱テスト。動作に影響する設定（Usage・hooks）が、指定 suite の
/// `UserDefaults` を経由したとき別の suite から隔離されることを検証する
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

    @Test func usageSettings_autoRefresh_readsFromSuite_isolatedFromOtherSuite() {
        let (suite, name) = makeSuite()
        defer { suite.removePersistentDomain(forName: name) }
        let (otherSuite, otherName) = makeSuite()
        defer { otherSuite.removePersistentDomain(forName: otherName) }
        let key = UsageSettings.autoRefreshKey
        let standardBefore = UserDefaults.standard.object(forKey: key) as? NSObject

        suite.set(false, forKey: key)
        #expect(UsageSettings.isAutoRefreshEnabled(defaults: suite) == false)
        // 別の suite は未設定＝既定 true のまま（汚染されていない）
        #expect(UsageSettings.isAutoRefreshEnabled(defaults: otherSuite) == true)
        #expect((UserDefaults.standard.object(forKey: key) as? NSObject) == standardBefore)
    }

    @Test func codexUserHooks_setEnabled_writesToSuite_isolatedFromOtherSuite() {
        let (suite, name) = makeSuite()
        defer { suite.removePersistentDomain(forName: name) }
        let (otherSuite, otherName) = makeSuite()
        defer { otherSuite.removePersistentDomain(forName: otherName) }
        let key = CodexUserHooksSettings.enabledKey
        let standardBefore = UserDefaults.standard.object(forKey: key) as? NSObject

        // 標準側が既にtrueでも、両方へ書く回帰をfalseへの切替で検出する。
        for enabled in [true, false] {
            CodexUserHooksSettings.setEnabled(enabled, defaults: suite)
            #expect(CodexUserHooksSettings.isEnabled(defaults: suite) == enabled)
            #expect(otherSuite.object(forKey: key) == nil)
            #expect((UserDefaults.standard.object(forKey: key) as? NSObject) == standardBefore)
        }
    }
}
