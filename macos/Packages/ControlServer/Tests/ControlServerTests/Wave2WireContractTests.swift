import AgentDomain
import Testing
@testable import ControlServer

@Suite("既定モデル規則", .serialized)
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

    @Test("Claude の内蔵 fallback はユーザー向けの既定一覧を保持する")
    func claudeBuiltinModelsRemainFrozen() {
        #expect(AgentModelCatalog.builtinModels(for: .claudeCode).map(\.id) == ["opus", "sonnet", "fable", "haiku"])
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

/// task-1 受け入れテスト（PM 著・実装役は編集禁止）。
/// spawn 前のモデル選択に使うエージェント別モデルカタログの契約を凍結する。
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
