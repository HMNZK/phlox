import AgentDomain
import Testing
@testable import ControlServer

/// task-1 受け入れテスト（PM 著・実装役は編集禁止）。
/// spawn 前のモデル選択に使う「エージェント別・静的モデルカタログ」の契約を凍結する。
/// `GET /agents/{kind}/models` はこの AgentModelCatalog を配信する。
/// spawn+model / 一覧project / usage のワイヤ形状は wire-contract.md を正本とし、
/// 実装役の白箱テスト（Wave2ServerWireWhiteboxTests）と Phase4 E2E で担保する。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
struct Wave2WireContractTests {

    @Test("claudeCode は非空のモデルカタログと既定モデルを持つ")
    func claudeCatalogNonEmptyWithDefault() {
        #expect(!AgentModelCatalog.models(for: .claudeCode).isEmpty)
        #expect(AgentModelCatalog.defaultModel(for: .claudeCode) != nil)
    }

    @Test("codex はモデル選択非対応（空カタログ）")
    func codexCatalogEmpty() {
        #expect(AgentModelCatalog.models(for: .codex).isEmpty)
    }
}
