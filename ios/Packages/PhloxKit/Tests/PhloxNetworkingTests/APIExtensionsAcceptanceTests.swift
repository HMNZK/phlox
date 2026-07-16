import Foundation
import Testing
import PhloxCore
@testable import PhloxNetworking

/// task-7 受け入れテスト（PM 著・実装役は編集禁止）。
/// API 拡張契約 v1（docs/specs/mobile-api-extensions-contract.md）のクライアント側 wire 検証。
/// フィクスチャ JSON は契約書の例と同一（サーバー側 run と共有する凍結形状）。
/// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
/// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
// .serialized: ExtStubURLProtocol の static 状態（outcomes/requests）を共有するため並列不可
// （URLProtocol は URLSession 経由でインスタンス注入できず static が構造的に必要）。
@Suite(.serialized)
struct APIExtensionsAcceptanceTests {
    // MARK: - §1 interrupt

    @Test("interrupt は POST /sessions/{id}/interrupt へ送り 204 で成功する")
    func interruptPostsAndAccepts204() async throws {
        let harness = Harness(outcomes: [(204, Data())])
        try await harness.client.interrupt(sessionID: "s1")
        let request = try #require(harness.lastRequest)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/sessions/s1/interrupt")
    }

    @Test("interrupt の 409（非対応セッション）は server エラーとして投げる")
    func interruptUnsupportedThrows409() async throws {
        let harness = Harness(outcomes: [(409, Data(#"{"error":"interrupt unsupported"}"#.utf8))])
        await #expect(throws: PhloxError.self) {
            try await harness.client.interrupt(sessionID: "s1")
        }
    }

    // MARK: - §2 subagents 一覧

    @Test("subAgents は一覧 JSON をドメインへ写す")
    func subAgentsDecodesContract() async throws {
        let fixture = #"""
        {"sessionId":"s1","subAgents":[
          {"id":"sa-1","name":"explore-map","status":"running","messageCount":12,"markerMessageId":"msg-42"},
          {"id":"sa-2","name":"reviewer","status":"weird-future-status","messageCount":0}
        ]}
        """#
        let harness = Harness(outcomes: [(200, Data(fixture.utf8))])
        let list = try await harness.client.subAgents(sessionID: "s1")
        #expect(harness.lastRequest?.url?.path == "/sessions/s1/subagents")
        #expect(list == [
            SubAgentSummary(id: "sa-1", name: "explore-map", status: .running,
                            messageCount: 12, markerMessageID: "msg-42"),
            SubAgentSummary(id: "sa-2", name: "reviewer", status: .unknown,
                            messageCount: 0, markerMessageID: nil),
        ], "未知 status は unknown へ写す・markerMessageId 欠落は nil")
    }

    // MARK: - §3 subagent メッセージ

    @Test("subAgentMessages は既存 /messages と同じメッセージ形状を写す")
    func subAgentMessagesDecodesContract() async throws {
        let fixture = #"""
        {"sessionId":"s1","subAgentId":"sa-1","messages":[
          {"id":"m1","type":"agent","text":"探索中"},
          {"id":"m2","type":"command","command":"ls","output":"a.txt"}
        ]}
        """#
        let harness = Harness(outcomes: [(200, Data(fixture.utf8))])
        let messages = try await harness.client.subAgentMessages(sessionID: "s1", subAgentID: "sa-1")
        #expect(harness.lastRequest?.url?.path == "/sessions/s1/subagents/sa-1/messages")
        #expect(messages == [
            .agent(id: "m1", text: "探索中"),
            .command(id: "m2", command: "ls", output: "a.txt"),
        ])
    }

    // MARK: - §4 usage

    @Test("usage は turn の値をドメインへ写す")
    func usageDecodesTurn() async throws {
        let fixture = #"""
        {"sessionId":"s1","turn":{"costUSD":0.1234,"contextUsedTokens":45678,"contextWindowTokens":200000}}
        """#
        let harness = Harness(outcomes: [(200, Data(fixture.utf8))])
        let usage = try await harness.client.usage(sessionID: "s1")
        #expect(harness.lastRequest?.url?.path == "/sessions/s1/usage")
        #expect(usage == TurnUsage(costUSD: 0.1234, contextUsedTokens: 45678, contextWindowTokens: 200000))
    }

    @Test("usage の turn:null は nil を返す")
    func usageNullTurnIsNil() async throws {
        let harness = Harness(outcomes: [(200, Data(#"{"sessionId":"s1","turn":null}"#.utf8))])
        let usage = try await harness.client.usage(sessionID: "s1")
        #expect(usage == nil)
    }

    // MARK: - §6 差分取得

    @Test("messagesDelta（since なし）は全量スナップショットとして返る")
    func messagesDeltaInitialSnapshot() async throws {
        let fixture = #"""
        {"sessionId":"s1","messages":[{"id":"m1","type":"user","text":"hi"}],"cursor":"c-000042"}
        """#
        let harness = Harness(outcomes: [(200, Data(fixture.utf8))])
        let delta = try await harness.client.messagesDelta(sessionID: "s1", since: nil, wait: nil)
        let url = try #require(harness.lastRequest?.url)
        #expect(url.path == "/sessions/s1/messages")
        #expect(!(url.query ?? "").contains("since="), "since なしはクエリに付けない")
        #expect(delta == MessagesDelta(
            messages: [.user(id: "m1", text: "hi")], cursor: "c-000042", isSnapshot: true
        ))
    }

    @Test("messagesDelta（since あり）は since と wait をクエリに載せ差分として返る")
    func messagesDeltaWithSinceAndWait() async throws {
        let fixture = #"""
        {"sessionId":"s1","messages":[{"id":"m2","type":"agent","text":"reply"}],"cursor":"c-000043"}
        """#
        let harness = Harness(outcomes: [(200, Data(fixture.utf8))])
        let delta = try await harness.client.messagesDelta(sessionID: "s1", since: "c-000042", wait: 10)
        let url = try #require(harness.lastRequest?.url)
        let query = url.query ?? ""
        #expect(query.contains("since=c-000042"))
        #expect(query.contains("wait=10"))
        #expect(delta == MessagesDelta(
            messages: [.agent(id: "m2", text: "reply")], cursor: "c-000043", isSnapshot: false
        ))
    }

    @Test("messagesDelta の snapshot:true は全量フォールバックとして返る")
    func messagesDeltaSnapshotFallback() async throws {
        let fixture = #"""
        {"sessionId":"s1","messages":[{"id":"m1","type":"user","text":"hi"}],"cursor":"c-000050","snapshot":true}
        """#
        let harness = Harness(outcomes: [(200, Data(fixture.utf8))])
        let delta = try await harness.client.messagesDelta(sessionID: "s1", since: "c-000042", wait: nil)
        #expect(delta.isSnapshot, "snapshot:true は since 指定でも全量置換")
        #expect(delta.cursor == "c-000050")
    }

    // MARK: - §5 send 画像添付

    @Test("images 付き send は body に images[{mediaType,dataBase64}] を載せる")
    func sendEncodesImages() async throws {
        let harness = Harness(outcomes: [(200, Data(#"{"accepted":true}"#.utf8))])
        let pngHeader = Data([0x89, 0x50, 0x4E, 0x47])
        _ = try await harness.client.send(SendRequest(
            sessionID: "s1", text: "この画面を見て",
            images: [SendAttachment(mediaType: "image/png", data: pngHeader)]
        ))
        let body = try #require(harness.lastBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let images = try #require(object["images"] as? [[String: Any]])
        #expect(images.count == 1)
        #expect(images[0]["mediaType"] as? String == "image/png")
        #expect(images[0]["dataBase64"] as? String == pngHeader.base64EncodedString())
    }

    @Test("images なしの send は body に images キーを含めない（後方互換）")
    func sendWithoutImagesOmitsKey() async throws {
        let harness = Harness(outcomes: [(200, Data(#"{"accepted":true}"#.utf8))])
        _ = try await harness.client.send(SendRequest(sessionID: "s1", text: "hi"))
        let body = try #require(harness.lastBody)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["images"] == nil)
    }

    @Test("send の 413（サイズ超過）は server エラーとして投げる")
    func sendOversizeThrows413() async throws {
        let harness = Harness(outcomes: [(413, Data(#"{"error":"attachment too large"}"#.utf8))])
        await #expect(throws: PhloxError.self) {
            _ = try await harness.client.send(SendRequest(
                sessionID: "s1", text: "big",
                images: [SendAttachment(mediaType: "image/jpeg", data: Data(count: 8))]
            ))
        }
    }
}

// MARK: - ハーネス（本ファイル専用。NetStubURLProtocol とは独立）

private final class Harness: Sendable {
    let client: PhloxAPIClient

    init(outcomes: [(Int, Data)]) {
        ExtStubURLProtocol.reset()
        ExtStubURLProtocol.outcomes = outcomes
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ExtStubURLProtocol.self]
        client = PhloxAPIClient(
            config: ConnectionConfig(host: "100.64.0.1", port: 8765),
            tokenStore: ExtFixedTokenStore(token: "tok"),
            session: URLSession(configuration: configuration),
            maxRetries: 1,
            retryBaseDelayNanos: 1
        )
    }

    var lastRequest: URLRequest? { ExtStubURLProtocol.requests.last }
    var lastBody: Data? { ExtStubURLProtocol.bodies.last ?? nil }
}

final class ExtStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var outcomes: [(Int, Data)] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data?] = []

    static func reset() {
        outcomes = []
        requests = []
        bodies = []
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        Self.bodies.append(Self.readBody(of: request))
        let (status, data) = Self.outcomes.isEmpty ? (200, Data()) : Self.outcomes.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readBody(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private struct ExtFixedTokenStore: TokenStore {
    let token: String?
    func save(_ token: String) async throws {}
    func load() async throws -> String? { token }
    func delete() async throws {}
}
