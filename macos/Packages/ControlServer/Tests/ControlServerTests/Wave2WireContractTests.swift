import AgentDomain
import Testing
@testable import ControlServer

/// AgentModelCatalog はプロセス共有状態を持つため、触る suite を同じ親で直列化する。
@Suite("モデルカタログ共有状態", .serialized)
struct ModelCatalogTestIsolation {}

extension ModelCatalogTestIsolation {
@Suite("既定モデル規則")
struct DefaultModelRuleTests {
    @Test("Claude の既定は先頭ではなく opus を優先する")
    func claudeDefaultPrefersOpusOverFirstEntry() async {
        await refreshCatalog(using: DefaultModelRuleProvider(models: [
            .claudeCode: [option("sonnet"), option("opus"), option("haiku")],
        ]))

        #expect(AgentModelCatalog.defaultModel(for: .claudeCode) == "opus")
    }

    @Test("Claude は opus がなければ先頭へフォールバックする")
    func claudeDefaultFallsBackToFirstWhenOpusAbsent() async {
        await refreshCatalog(using: DefaultModelRuleProvider(models: [
            .claudeCode: [option("sonnet"), option("haiku")],
        ]))

        #expect(AgentModelCatalog.defaultModel(for: .claudeCode) == "sonnet")
    }

    @Test("Cursor の既定は composer-2.5 を優先し API と UI の正本を共有する")
    func cursorDefaultPrefersComposerOverFirstEntry() async {
        await refreshCatalog(using: DefaultModelRuleProvider(models: [
            .cursor: [option("auto"), option("composer-2.5")],
        ]))

        #expect(AgentModelCatalog.defaultModel(for: .cursor) == "composer-2.5")
    }

    @Test("Cursor は composer-2.5 がなければ先頭へフォールバックする")
    func cursorDefaultFallsBackToFirstWhenComposerAbsent() async {
        await refreshCatalog(using: DefaultModelRuleProvider(models: [
            .cursor: [option("auto"), option("gpt-5.3-codex-low")],
        ]))

        #expect(AgentModelCatalog.defaultModel(for: .cursor) == "auto")
    }

    @Test("内蔵 fallback は現行 CLI のモデルを保持する")
    func builtinModelsRemainCurrent() {
        #expect(AgentModelCatalog.builtinModels(for: .claudeCode).map(\.id) == ["opus", "sonnet", "fable", "haiku"])
        #expect(AgentModelCatalog.builtinModels(for: .claudeCode).map(\.displayName) == [
            "Opus 5", "Sonnet 5", "Fable 5", "Haiku 4.5",
        ])
        #expect(AgentModelCatalog.builtinModels(for: .codex).map(\.id) == [
            "gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna",
        ])
        #expect(AgentModelCatalog.builtinModels(for: .cursor).map(\.id) == [
            "composer-2.5", "gpt-5.6-sol-medium", "claude-fable-5-1-high",
        ])
    }

    private func refreshCatalog(using provider: any AgentModelListProviding) async {
        AgentModelCatalog.configure(provider: provider)
        defer { AgentModelCatalog.configure(provider: nil) }
        await AgentModelCatalog.refresh()
    }

    private func option(_ id: String) -> ControlModelOption {
        ControlModelOption(id: id, displayName: id)
    }
}
}

/// task-1 受け入れテスト（PM 著・実装役は編集禁止）。
/// spawn 前のモデル選択に使うエージェント別モデルカタログの契約を凍結する。
/// `GET /agents/{kind}/models` はこの AgentModelCatalog を配信する。
/// spawn+model / 一覧project / usage のワイヤ形状は wire-contract.md を正本とし、
/// 実装役の白箱テスト（Wave2ServerWireWhiteboxTests）と Phase4 E2E で担保する。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
extension ModelCatalogTestIsolation {
@Suite struct Wave2WireContractTests {

    @Test("claudeCode は非空のモデルカタログと既定モデルを持つ")
    func claudeCatalogNonEmptyWithDefault() {
        #expect(!AgentModelCatalog.models(for: .claudeCode).isEmpty)
        #expect(AgentModelCatalog.defaultModel(for: .claudeCode) != nil)
    }

    @Test("live provider の3 kind 一覧と既定値をワイヤ用スナップショットへ配信する")
    func liveCatalogServesAllKindsWithWireDefaults() async {
        AgentModelCatalog.configure(provider: WireContractProvider())
        defer { AgentModelCatalog.configure(provider: nil) }

        await AgentModelCatalog.refresh()

        #expect(AgentModelCatalog.models(for: .claudeCode).map(\.id) == ["sonnet", "best"])
        #expect(AgentModelCatalog.defaultModel(for: .claudeCode) == "sonnet")
        #expect(AgentModelCatalog.models(for: .codex).map(\.id) == ["gpt-5.3-codex"])
        #expect(AgentModelCatalog.defaultModel(for: .codex) == "gpt-5.3-codex")
        #expect(AgentModelCatalog.models(for: .cursor).map(\.id) == ["composer-2.5"])
        #expect(AgentModelCatalog.defaultModel(for: .cursor) == "composer-2.5")
    }
}
}

private struct WireContractProvider: AgentModelListProviding {
    func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption] {
        switch kind {
        case .claudeCode: [ControlModelOption(id: "sonnet", displayName: "Sonnet") , ControlModelOption(id: "best", displayName: "Best")]
        case .codex: [ControlModelOption(id: "gpt-5.3-codex", displayName: "GPT-5.3 Codex")]
        case .cursor: [ControlModelOption(id: "composer-2.5", displayName: "Composer 2.5")]
        }
    }
}

private struct DefaultModelRuleProvider: AgentModelListProviding {
    let models: [AgentKind: [ControlModelOption]]

    func fetchModels(for kind: AgentKind) async throws -> [ControlModelOption] {
        models[kind] ?? [ControlModelOption(id: "fallback-\(kind.rawValue)", displayName: "fallback")]
    }
}
