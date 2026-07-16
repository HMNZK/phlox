import Foundation
import Testing
@testable import MobileProxy

/// 実ループバック(127.0.0.1)越しの結合テスト。
/// スタブ HTTP サーバを 127.0.0.1:N に立て、プロキシを listenHost=127.0.0.1 で起動し、
/// プロキシ経由でリクエストを投げて「無改変中継」を実ネットワークで検証する。
@Suite struct MobileProxyIntegrationTests {

    /// 生レスポンスを組み立てる小ヘルパ。
    private func rawResponse(status: String, headers: [String: String], body: String) -> Data {
        var text = "HTTP/1.1 \(status)\r\n"
        var allHeaders = headers
        if allHeaders["Content-Length"] == nil {
            allHeaders["Content-Length"] = String(body.utf8.count)
        }
        for (key, value) in allHeaders.sorted(by: { $0.key < $1.key }) {
            text += "\(key): \(value)\r\n"
        }
        text += "\r\n"
        var data = Data(text.utf8)
        data.append(Data(body.utf8))
        return data
    }

    /// スタブとプロキシを起動して 1 リクエストを通すヘルパ。
    private func roundTrip(
        request: Data,
        response: Data
    ) async throws -> (response: Data, capturedRequest: Data) {
        let stub = try StubHTTPServer(rawResponse: response)
        let stubPort = try await stub.start()
        defer { stub.stop() }

        let proxy = MobileProxy(
            listenHost: "127.0.0.1",
            listenPort: 0,
            targetPort: stubPort
        )
        let listenPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let received = try await RawHTTPClient.send(request, toPort: listenPort)

        // スタブが記録するまで僅かに待つ(send 完了後に記録 closure が走るため)。
        var captured = stub.lastRequest
        var attempts = 0
        while captured == nil && attempts < 100 {
            try await Task.sleep(nanoseconds: 5_000_000)
            captured = stub.lastRequest
            attempts += 1
        }

        return (received, captured ?? Data())
    }

    // 基準 1: GET /sessions の応答(status・body)がそのまま返る。
    @Test func getSessionsRelaysStatusAndBodyVerbatim() async throws {
        let body = #"{"sessions":[]}"#
        let response = rawResponse(
            status: "200 OK",
            headers: ["Content-Type": "application/json"],
            body: body
        )
        let request = Data("GET /sessions HTTP/1.1\r\nHost: example\r\n\r\n".utf8)

        let result = try await roundTrip(request: request, response: response)

        // プロキシは生レスポンスをバイト等価で返す。
        #expect(result.response == response)
        let text = String(data: result.response, encoding: .utf8) ?? ""
        #expect(text.contains("200 OK"))
        #expect(text.contains(body))
    }

    // 基準 2: Authorization: Bearer xxx がスタブへ透過する。
    @Test func authorizationHeaderPassesThroughToUpstream() async throws {
        let response = rawResponse(status: "200 OK", headers: [:], body: "ok")
        let token = "Bearer secret-token-123"
        let request = Data(
            "GET /sessions HTTP/1.1\r\nHost: example\r\nAuthorization: \(token)\r\n\r\n".utf8
        )

        let result = try await roundTrip(request: request, response: response)

        let capturedText = String(data: result.capturedRequest, encoding: .utf8) ?? ""
        #expect(capturedText.contains("Authorization: \(token)"))
        // 応答も透過。
        #expect(result.response == response)
    }

    // 基準 3: POST(body あり)が method・body 共に透過する。
    @Test func postBodyPassesThroughVerbatim() async throws {
        let response = rawResponse(status: "200 OK", headers: [:], body: "accepted")
        let payload = #"{"to":"main","text":"hello"}"#
        var request = Data(
            "POST /send HTTP/1.1\r\nHost: example\r\nContent-Type: application/json\r\nContent-Length: \(payload.utf8.count)\r\n\r\n".utf8
        )
        request.append(Data(payload.utf8))

        let result = try await roundTrip(request: request, response: response)

        let capturedText = String(data: result.capturedRequest, encoding: .utf8) ?? ""
        #expect(capturedText.hasPrefix("POST /send HTTP/1.1"))
        #expect(capturedText.contains(payload))
        // スタブが受け取った生バイトはクライアントが送った生バイトと完全一致。
        #expect(result.capturedRequest == request)
        #expect(result.response == response)
    }

    // 基準 4: 404/401 等の非 2xx 応答もそのまま透過する。
    @Test func nonSuccessStatusPassesThroughVerbatim() async throws {
        let response404 = rawResponse(status: "404 Not Found", headers: [:], body: "not found")
        let request = Data("GET /missing HTTP/1.1\r\nHost: example\r\n\r\n".utf8)
        let result404 = try await roundTrip(request: request, response: response404)
        #expect(result404.response == response404)
        #expect((String(data: result404.response, encoding: .utf8) ?? "").contains("404 Not Found"))

        let response401 = rawResponse(status: "401 Unauthorized", headers: [:], body: "")
        let result401 = try await roundTrip(request: request, response: response401)
        #expect(result401.response == response401)
        #expect((String(data: result401.response, encoding: .utf8) ?? "").contains("401 Unauthorized"))
    }

    // ヘッダの順序・大文字小文字・未知ヘッダが保存される(パーサ無しの生中継であること)。
    @Test func arbitraryHeadersAndCasingPreservedBothWays() async throws {
        let response = rawResponse(
            status: "200 OK",
            headers: ["X-Custom-Header": "Value", "Set-Cookie": "a=b"],
            body: "x"
        )
        let request = Data(
            "GET /sessions HTTP/1.1\r\nHost: example\r\nX-Weird-CASE: KeepMe\r\nAuthorization: Bearer t\r\n\r\n".utf8
        )

        let result = try await roundTrip(request: request, response: response)

        // リクエスト側: 未知ヘッダと大文字小文字がそのまま上流に届く。
        #expect(result.capturedRequest == request)
        // 応答側: 任意ヘッダがそのままクライアントへ返る。
        #expect(result.response == response)
    }
}
