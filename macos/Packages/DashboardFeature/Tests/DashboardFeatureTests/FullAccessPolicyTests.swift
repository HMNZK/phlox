import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
@testable import DashboardFeature

/// 設定「フルアクセス（bypass）」の ON/OFF が app-server スレッドの承認ポリシー・サンドボックスへ反映される。
/// ON: never / danger-full-access、OFF: on-request / workspace-write。
@Suite("SessionSpawnService full-access policy")
struct FullAccessPolicyTests {
    /// テスト専用の UserDefaults suite を作り、Codex の bypass キーを設定する（nil なら未保存）。
    private func defaults(fullAccess: Bool?, function: String = #function) -> UserDefaults {
        let name = "phlox.tests.full-access-policy.\(abs(function.hashValue))"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        if let fullAccess {
            defaults.set(fullAccess, forKey: BypassSettings.codexKey)
        }
        return defaults
    }

    @Test("すべての起動元が Codex の bypass 設定を読む")
    func allContextsFollowBypassSetting() {
        for fullAccess in [true, false] {
            let defaults = defaults(fullAccess: fullAccess, function: "allContexts\(fullAccess)")
            let expectedApproval: ApprovalPolicy = .named(fullAccess ? "never" : "on-request")
            let expectedSandbox: SandboxPolicy = .named(fullAccess ? "danger-full-access" : "workspace-write")

            for context: SessionLaunchContext in [.interactive, .orchestration, .remoteUser] {
                #expect(SessionSpawnService.appServerApprovalPolicy(for: context, defaults: defaults) == expectedApproval)
                #expect(SessionSpawnService.appServerSandboxPolicy(for: context, defaults: defaults) == expectedSandbox)
            }
        }
    }

    @Test("設定未保存（初回起動）は BypassSettings の既定 true に従い full access になる")
    func unsetDefaultsFollowBypassDefault() {
        // 既存ユーザーの ON（既定 true）もそのまま適用する。
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
