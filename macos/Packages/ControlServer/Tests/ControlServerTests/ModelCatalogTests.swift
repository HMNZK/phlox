import AgentDomain
import Foundation
import Testing
@testable import ControlServer

/// AgentModelCatalog はプロセス共有状態を持つため、触る suite を同じ親で直列化する。
@Suite("モデルカタログ共有状態", .serialized)
struct ModelCatalogTestIsolation {}

extension ModelCatalogTestIsolation {
@Suite("既定モデル規則")
struct DefaultModelRuleTests {
    @Test("Claude の既定は対話型と同じ default を優先する")
    func claudeDefaultPrefersDefaultOverFirstEntry() async {
        await refreshCatalog(using: DefaultModelRuleProvider(models: [
            .claudeCode: [option("sonnet"), option("default"), option("haiku")],
        ]))

        #expect(AgentModelCatalog.defaultModel(for: .claudeCode) == "default")
    }

    @Test("Claude は default がなければ先頭へフォールバックする")
    func claudeDefaultFallsBackToFirstWhenDefaultAbsent() async {
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
        #expect(AgentModelCatalog.builtinModels(for: .claudeCode).map(\.id) == ["default", "opus[1m]", "fable", "sonnet", "haiku"])
        #expect(AgentModelCatalog.builtinModels(for: .claudeCode).map(\.displayName) == [
            "Default", "Opus (1M context)",
            "Fable 5.1", "Sonnet 5", "Haiku 4.5",
        ])
        #expect(AgentModelCatalog.builtinModels(for: .codex).map(\.id) == [
            "gpt-6.1-sol", "gpt-6-astra", "gpt-6-sol", "gpt-6-luna", "gpt-5.6-sol",
            "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5",
        ])
        let cursorModels = AgentModelCatalog.builtinModels(for: .cursor)
        #expect(cursorModels.map(\.id) == [
            "auto", "grok-4.7", "grok-4.6", "grok-4.5", "composer-2.5", "claude-opus-5-5",
            "claude-opus-5", "claude-opus-4-8",
            "gpt-5.6-sol", "gpt-5.5", "claude-fable-5-1", "claude-fable-5", "muse-spark-1.3",
            "gemini-3.8-flash", "gemini-3.7-flash", "gpt-5.6-terra", "claude-sonnet-5",
            "claude-sonnet-4-6", "gpt-5.3-codex", "claude-opus-4-7", "gpt-5.4",
            "claude-opus-4-6", "claude-opus-4-5", "gpt-5.2", "gpt-5.6-luna",
            "gemini-3.6-flash", "gemini-3.1-pro", "gpt-5.4-mini", "gpt-5.4-nano",
            "claude-sonnet-4-5", "gpt-5.1", "gemini-3-flash",
            "gemini-3.5-flash", "claude-sonnet-4", "gpt-5-mini", "kimi-k3",
            "kimi-k2.7-code", "glm-5.2",
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

/// spawn 前のモデル選択に使うエージェント別モデルカタログ（AgentModelCatalog）の配信。
/// `GET /agents/{kind}/models` はこの AgentModelCatalog を配信する。
extension ModelCatalogTestIsolation {
@Suite struct ModelCatalogServingTests {
    private let token = "model-catalog-token"
    private let requester = SessionID()


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

    @Test("agent models は既知 kind を配送し未知 kind を 404 にする")
    func agentModelsRoutingAndUnknownKind() async throws {
        let store = SessionTokenStore()
        await store.register(token, for: requester)
        let server = ControlServer(tokenStore: store) { request in
            guard case let .agentModels(kind) = request.action else {
                return .status(500)
            }
            return .json(200, ControlAgentModelsResponse(
                models: AgentModelCatalog.models(for: kind),
                defaultModel: AgentModelCatalog.defaultModel(for: kind)
            ))
        }
        let port = try await server.start()
        _ = server

        let known = try await get(port: port, path: "/agents/claudeCode/models")
        let unknown = try await get(port: port, path: "/agents/unknown/models")

        #expect(known.status == 200)
        let knownObject = try #require(
            JSONSerialization.jsonObject(with: known.body) as? [String: Any]
        )
        #expect((knownObject["models"] as? [[String: Any]])?.isEmpty == false)
        #expect(knownObject["defaultModel"] is String)
        #expect(unknown.status == 404)
    }

    private func get(port: Int, path: String) async throws -> (status: Int, body: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
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
