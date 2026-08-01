import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
@testable import DashboardFeature

/// task-3 受け入れテスト（PM が著す不変の契約。実装役は編集不可）。
/// 設定「フルアクセス（bypass）」の ON/OFF が app-server スレッドの承認ポリシー・
/// サンドボックスへ反映されることを固定する。
@Suite("Acceptance: フルアクセス設定の app-server 反映（task-3）")
struct AcceptanceFullAccessPolicyTests {
    /// テスト専用の UserDefaults suite を作り、Codex の bypass キーを明示的に設定する。
    private func defaults(fullAccess: Bool?, function: String = #function) -> UserDefaults {
        let name = "phlox.tests.fullaccess.\(abs(function.hashValue))"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        if let fullAccess {
            defaults.set(fullAccess, forKey: BypassSettings.codexKey)
        }
        return defaults
    }

    @Test("ON: interactive は never / danger-full-access で開始する")
    func interactiveWithFullAccess() {
        let defaults = defaults(fullAccess: true)
        #expect(
            SessionSpawnService.appServerApprovalPolicy(for: .interactive, defaults: defaults)
                == .named("never")
        )
        #expect(
            SessionSpawnService.appServerSandboxPolicy(for: .interactive, defaults: defaults)
                == .named("danger-full-access")
        )
    }

    @Test("OFF: interactive は従来どおり on-request / workspace-write")
    func interactiveWithoutFullAccess() {
        let defaults = defaults(fullAccess: false)
        #expect(
            SessionSpawnService.appServerApprovalPolicy(for: .interactive, defaults: defaults)
                == .named("on-request")
        )
        #expect(
            SessionSpawnService.appServerSandboxPolicy(for: .interactive, defaults: defaults)
                == .named("workspace-write")
        )
    }

    @Test("ON: remoteUser も interactive と同じ扱い")
    func remoteUserFollowsInteractive() {
        let on = defaults(fullAccess: true)
        #expect(
            SessionSpawnService.appServerApprovalPolicy(for: .remoteUser, defaults: on)
                == SessionSpawnService.appServerApprovalPolicy(for: .interactive, defaults: on)
        )
        #expect(
            SessionSpawnService.appServerSandboxPolicy(for: .remoteUser, defaults: on)
                == SessionSpawnService.appServerSandboxPolicy(for: .interactive, defaults: on)
        )
    }

    @Test("orchestration は設定に依らず never / danger-full-access（非回帰）")
    func orchestrationIsUnaffected() {
        for value in [true, false] {
            let defaults = defaults(fullAccess: value, function: "orchestration\(value)")
            #expect(
                SessionSpawnService.appServerApprovalPolicy(for: .orchestration, defaults: defaults)
                    == .named("never")
            )
            #expect(
                SessionSpawnService.appServerSandboxPolicy(for: .orchestration, defaults: defaults)
                    == .named("danger-full-access")
            )
        }
    }

    @Test("設定未保存（初回起動）は BypassSettings の既定 true に従い full access になる")
    func unsetDefaultsFollowBypassDefault() {
        // ゲート①の決定 D2: 既存ユーザーの ON（既定 true）もそのまま適用する。
        let defaults = defaults(fullAccess: nil)
        #expect(BypassSettings.isEnabled(for: .codex, defaults: defaults))
        #expect(
            SessionSpawnService.appServerApprovalPolicy(for: .interactive, defaults: defaults)
                == .named("never")
        )
        #expect(
            SessionSpawnService.appServerSandboxPolicy(for: .interactive, defaults: defaults)
                == .named("danger-full-access")
        )
    }
}
