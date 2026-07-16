import Foundation
import Testing
import AgentDomain
@testable import DashboardFeature

/// task-17（Layer B 前提改修 T2）契約の凍結受け入れテスト。
/// `PHLOX_DEFAULTS_SUITE` 指定時に、動作に影響する設定（Bypass・通知・Usage）が
/// 専用 suite の `UserDefaults` を使い、未指定時は `.standard` にフォールバックすることを、
/// 注入した environment 辞書で検証する（実 env に依存しない=決定的）。
/// 実装者はこのファイルを編集しない。
@Suite struct DefaultsSuiteOverrideTests {
    @Test func phloxDefaults_emptyEnv_returnsStandard() {
        let defaults = UserDefaults.phloxDefaults(environment: [:])
        #expect(defaults === UserDefaults.standard)
    }

    @Test func phloxDefaults_blankSuite_returnsStandard() {
        let defaults = UserDefaults.phloxDefaults(environment: ["PHLOX_DEFAULTS_SUITE": ""])
        #expect(defaults === UserDefaults.standard)
    }

    @Test func phloxDefaults_honorsSuiteEnv_isIsolatedFromStandard() {
        let suite = "phlox.e2e.suite.override.test"
        UserDefaults().removePersistentDomain(forName: suite)
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let defaults = UserDefaults.phloxDefaults(environment: ["PHLOX_DEFAULTS_SUITE": suite])
        #expect(defaults !== UserDefaults.standard)

        // suite に書いた値は .standard を汚染しない（隔離の証明）
        let key = "phlox.e2e.isolation.probe"
        UserDefaults.standard.removeObject(forKey: key)
        defaults.set(true, forKey: key)
        #expect(defaults.bool(forKey: key) == true)
        #expect(UserDefaults.standard.object(forKey: key) == nil)
    }
}
