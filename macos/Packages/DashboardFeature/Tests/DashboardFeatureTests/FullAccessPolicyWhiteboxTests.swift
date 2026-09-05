import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
@testable import DashboardFeature

@Suite("SessionSpawnService full-access policy")
struct FullAccessPolicyWhiteboxTests {
    private func defaults(fullAccess: Bool, function: String = #function) -> UserDefaults {
        let name = "phlox.tests.full-access-policy.\(abs(function.hashValue))"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(fullAccess, forKey: BypassSettings.codexKey)
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
}
