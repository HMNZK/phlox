import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

/// task-2 受け入れテスト（PM 著・凍結。アサーションの変更は禁止。ハーネス欠陥を
/// 発見した場合は PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
///
/// バグ: iOS でプロジェクトを選んで作成したセッションが macOS の「その他」に落ちる。
/// 原因の片方は、選んだプロジェクトが `POST /sessions` の body に一切載っていないこと。
///
/// 契約（tasks/wire-contract.md §1・§3）:
///  - `SpawnRequest.projectID` が非 nil なら body に `projectId` を載せる
///  - nil なら **キーごと省略**する（従来の body 形を維持＝後方互換）
///  - `workspace`（表示名）は従来どおり body に載せない
@Suite(.serialized)
struct AcceptanceSpawnProjectIdBodyTests {
    private let config = ConnectionConfig(host: "100.64.0.1", port: 8765)

    private func makeClient() -> PhloxAPIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpawnBodyCaptureURLProtocol.self]
        return PhloxAPIClient(
            config: config,
            tokenStore: InMemoryTokenStore(token: "tok"),
            session: URLSession(configuration: configuration),
            maxRetries: 1,
            retryBaseDelayNanos: 1
        )
    }

    @Test("projectID 指定時は spawn body に projectId を載せる")
    func spawnIncludesProjectId() async throws {
        SpawnBodyCaptureURLProtocol.reset()

        _ = try await makeClient().spawn(
            SpawnRequest(
                agent: .codex,
                workspace: "Gardenia",
                projectID: "6C2F0E2A-1111-4222-8333-444455556666",
                model: "gpt-5.6"
            )
        )

        let body = try #require(SpawnBodyCaptureURLProtocol.lastRequestBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object == [
            "kind": "codex",
            "backend": "appServer",
            "model": "gpt-5.6",
            "projectId": "6C2F0E2A-1111-4222-8333-444455556666"
        ])
    }

    @Test("projectID 省略時は projectId キーごと省略する（従来の body 形を維持）")
    func spawnOmitsNilProjectId() async throws {
        SpawnBodyCaptureURLProtocol.reset()

        _ = try await makeClient().spawn(
            SpawnRequest(agent: .cursor, workspace: "その他")
        )

        let body = try #require(SpawnBodyCaptureURLProtocol.lastRequestBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object == ["kind": "cursor", "backend": "appServer"])
    }

    @Test("projectID だけ指定し model 省略でも body は projectId を含む")
    func spawnIncludesProjectIdWithoutModel() async throws {
        SpawnBodyCaptureURLProtocol.reset()

        _ = try await makeClient().spawn(
            SpawnRequest(
                agent: .claudeCode,
                workspace: "Gardenia",
                projectID: "6C2F0E2A-1111-4222-8333-444455556666"
            )
        )

        let body = try #require(SpawnBodyCaptureURLProtocol.lastRequestBody)
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: String])
        #expect(object == [
            "kind": "claudeCode",
            "backend": "appServer",
            "projectId": "6C2F0E2A-1111-4222-8333-444455556666"
        ])
    }
}

/// 送信 body だけを捕まえて 201 を返す最小スタブ（Wave2ClientWhiteboxTests の同型が
/// file-private のため、この受け入れテスト専用に自己完結で持つ）。
private final class SpawnBodyCaptureURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequestBody: Data?

    static func reset() {
        lastRequestBody = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequestBody = request.readBodyForTesting()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 201,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"id":"s1"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
