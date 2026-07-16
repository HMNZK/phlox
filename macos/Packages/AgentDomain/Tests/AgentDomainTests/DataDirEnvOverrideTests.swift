import Foundation
import Testing
@testable import AgentDomain

/// task-17（Layer B 前提改修 T1）契約の凍結受け入れテスト。
/// `PHLOX_DATA_DIR` / `PHLOX_AGENTS_JSON` による差し替えを、注入した environment 辞書で検証する
/// （実 env に依存しない=決定的）。実装者はこのファイルを編集しない。
@Suite struct DataDirEnvOverrideTests {
    // MARK: PHLOX_DATA_DIR（アプリサポートのルート差し替え・全 data-dir 経路のチョークポイント）

    @Test func appSupportRoot_honorsPhloxDataDir_throwingOverload() throws {
        let env = ["PHLOX_DATA_DIR": "/tmp/phlox-e2e-throwing"]
        let url = try AppSupportLocator.appSupportDirectoryURL(environment: env)
        #expect(url.path == "/tmp/phlox-e2e-throwing")
    }

    @Test func appSupportRoot_honorsPhloxDataDir_homeOverload() {
        let env = ["PHLOX_DATA_DIR": "/tmp/phlox-e2e-home"]
        let url = AppSupportLocator.appSupportDirectoryURL(
            home: URL(fileURLWithPath: "/Users/someone"),
            environment: env
        )
        #expect(url.path == "/tmp/phlox-e2e-home")
    }

    @Test func appSupportRoot_emptyDataDir_fallsBackToFlavorPath_homeOverload() {
        let url = AppSupportLocator.appSupportDirectoryURL(
            home: URL(fileURLWithPath: "/Users/someone"),
            environment: [:]
        )
        // 既存挙動保存: home 起点の flavor パスへフォールバック
        #expect(url.path.hasPrefix("/Users/someone/Library/Application Support/"))
    }

    @Test func appSupportRoot_blankDataDir_isIgnored() {
        // 空文字（設定はされているが値が空）は未設定と同じ扱い
        let url = AppSupportLocator.appSupportDirectoryURL(
            home: URL(fileURLWithPath: "/Users/someone"),
            environment: ["PHLOX_DATA_DIR": ""]
        )
        #expect(url.path.hasPrefix("/Users/someone/Library/Application Support/"))
    }

    // MARK: PHLOX_AGENTS_JSON（カスタムエージェント registry パス差し替え・~/.config/phlox 系）

    @Test func agentsRegistry_honorsPhloxAgentsJson() {
        let env = ["PHLOX_AGENTS_JSON": "/tmp/phlox-e2e-agents.json"]
        let url = CustomAgentRegistryLoader.defaultURL(environment: env)
        #expect(url.path == "/tmp/phlox-e2e-agents.json")
    }

    @Test func agentsRegistry_emptyEnv_fallsBackToConfigPath() {
        let url = CustomAgentRegistryLoader.defaultURL(environment: [:])
        #expect(url.path.hasSuffix(".config/phlox/agents.json"))
    }
}
