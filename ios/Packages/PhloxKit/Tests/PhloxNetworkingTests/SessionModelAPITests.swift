import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

/// セッションのモデル選択 API: ワイヤ定数（macOS 側 ControlModelWireContract と一字一句一致）、
/// 凍結ワイヤキーどおりの JSON の DTO decode、API クライアント配線。
@Suite("Session model API", .serialized) struct SessionModelAPITests {
    private let config = ConnectionConfig(host: "100.64.0.1", port: 8765)

    private func makeClient(maxRetries: Int = 1) -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [NetStubURLProtocol.self]
        return PhloxAPIClient(
            config: config,
            tokenStore: InMemoryTokenStore(token: "tok"),
            session: URLSession(configuration: configuration),
            maxRetries: maxRetries,
            retryBaseDelayNanos: 1
        )
    }

    /// ワイヤ形状の凍結（変更は macOS 側とのシーム契約違反）。
    @Test func wireContractShapeFrozen() {
        #expect(PhloxModelWireContract.settingsPathSuffix == "settings")
        #expect(PhloxModelWireContract.modelPathSuffix == "model")
        #expect(PhloxModelWireContract.selectedModelKey == "selectedModel")
        #expect(PhloxModelWireContract.availableModelsKey == "availableModels")
        #expect(PhloxModelWireContract.modelIDKey == "id")
        #expect(PhloxModelWireContract.modelDisplayNameKey == "displayName")
        #expect(PhloxModelWireContract.modelKey == "model")
    }

    @Test func sessionModelSettingsDTODecodesFrozenWireShape() throws {
        NetStubURLProtocol.reset()
        let json = """
        {
          "\(PhloxModelWireContract.selectedModelKey)": "claude-sonnet-4",
          "\(PhloxModelWireContract.availableModelsKey)": [
            {"\(PhloxModelWireContract.modelIDKey)": "claude-sonnet-4", "\(PhloxModelWireContract.modelDisplayNameKey)": "Sonnet 4"},
            {"\(PhloxModelWireContract.modelIDKey)": "claude-opus-4", "\(PhloxModelWireContract.modelDisplayNameKey)": "Opus 4"}
          ]
        }
        """
        let dto = try JSONDecoder().decode(SessionModelSettingsDTO.self, from: Data(json.utf8))
        let settings = dto.toDomain()

        #expect(settings.selectedModel == "claude-sonnet-4")
        #expect(settings.availableModels.count == 2)
        #expect(settings.availableModels[0].id == "claude-sonnet-4")
        #expect(settings.availableModels[0].displayName == "Sonnet 4")
    }

    @Test func sessionSettingsUsesFrozenSettingsPathSuffix() async throws {
        NetStubURLProtocol.reset()
        NetStubURLProtocol.outcomes = [
            .status(
                200,
                Data("""
                {"selectedModel":"m1","availableModels":[{"id":"m1","displayName":"Model 1"}]}
                """.utf8),
                [:]
            ),
        ]

        _ = try await makeClient().sessionSettings(sessionID: "sess-1")

        let path = URLComponents(
            url: try #require(NetStubURLProtocol.lastRequest?.url),
            resolvingAgainstBaseURL: false
        )?.percentEncodedPath
        #expect(path == "/sessions/sess-1/\(PhloxModelWireContract.settingsPathSuffix)")
        #expect(NetStubURLProtocol.lastRequest?.httpMethod == "GET")
    }

    @Test func setModelPostsFrozenModelKeyWithoutRetry() async throws {
        NetStubURLProtocol.reset()
        NetStubURLProtocol.outcomes = [.status(200, Data(), [:])]

        try await makeClient(maxRetries: 3).setModel(sessionID: "sess-2", model: "claude-opus-4")

        #expect(NetStubURLProtocol.requestCount == 1, "破壊的操作は自動再試行しない")
        #expect(NetStubURLProtocol.lastRequest?.httpMethod == "POST")
        let path = URLComponents(
            url: try #require(NetStubURLProtocol.lastRequest?.url),
            resolvingAgainstBaseURL: false
        )?.percentEncodedPath
        #expect(path == "/sessions/sess-2/\(PhloxModelWireContract.modelPathSuffix)")
        let body = try #require(NetStubURLProtocol.lastRequestBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(object?[PhloxModelWireContract.modelKey] == "claude-opus-4")
    }
}
