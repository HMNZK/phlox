import Foundation
import Testing
@testable import MobileProxy

/// keep-alive(送信後も接続を開いたまま応答を待つ curl/URLSession 相当)経路の回帰ガード。
/// 実機ではここが通らず response が返らなかった。read-then-respond 型の上流スタブ
/// (ControlServer 相当)と素の POSIX keep-alive クライアントで、応答が返ることを実ループバックで固定する。
@Suite struct MobileProxyKeepAliveTests {

    private func okResponse(body: String) -> Data {
        let text = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        return Data(text.utf8)
    }

    // ★keep-alive クライアントで GET /sessions を叩くと応答がそのまま返る。
    @Test func keepAliveClientReceivesResponse() async throws {
        let body = #"{"sessions":[]}"#
        let response = okResponse(body: body)
        let stub = try StubHTTPServer(rawResponse: response)
        let stubPort = try await stub.start()
        defer { stub.stop() }

        let proxy = MobileProxy(listenHost: "127.0.0.1", listenPort: 0, targetPort: stubPort)
        let listenPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        // POSIX keep-alive: リクエスト送信後に送信方向を閉じず応答を待つ。
        let received = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            DispatchQueue.global().async {
                do {
                    let r = try RawHTTPClient.sendKeepAlivePOSIX(
                        Data("GET /sessions HTTP/1.1\r\nHost: x\r\n\r\n".utf8),
                        toPort: listenPort,
                        host: "127.0.0.1"
                    )
                    c.resume(returning: r)
                } catch {
                    c.resume(throwing: error)
                }
            }
        }

        #expect(received == response)
        #expect((String(data: received, encoding: .utf8) ?? "").contains(body))
    }

    // keep-alive で POST(body あり)も method・body・応答が透過する。
    @Test func keepAlivePostBodyRelaysVerbatim() async throws {
        let response = okResponse(body: "accepted")
        let stub = try StubHTTPServer(rawResponse: response)
        let stubPort = try await stub.start()
        defer { stub.stop() }

        let proxy = MobileProxy(listenHost: "127.0.0.1", listenPort: 0, targetPort: stubPort)
        let listenPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let payload = #"{"to":"main","text":"hello"}"#
        let header = Data(
            "POST /send HTTP/1.1\r\nHost: x\r\nContent-Type: application/json\r\nContent-Length: \(payload.utf8.count)\r\n\r\n".utf8
        )
        let request = header + Data(payload.utf8)

        let received = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            DispatchQueue.global().async {
                do {
                    let r = try RawHTTPClient.sendKeepAlivePOSIX(request, toPort: listenPort, host: "127.0.0.1")
                    c.resume(returning: r)
                } catch {
                    c.resume(throwing: error)
                }
            }
        }

        #expect(received == response)
        // 上流スタブが受け取った生リクエストが method・body 共にバイト一致(透過)。
        let captured = stub.lastRequest ?? Data()
        #expect(captured == request)
    }

    // keep-alive で 404 等の非 2xx もそのまま透過する。
    @Test func keepAliveNonSuccessRelaysVerbatim() async throws {
        let response = Data("HTTP/1.1 404 Not Found\r\nContent-Length: 9\r\n\r\nnot found".utf8)
        let stub = try StubHTTPServer(rawResponse: response)
        let stubPort = try await stub.start()
        defer { stub.stop() }

        let proxy = MobileProxy(listenHost: "127.0.0.1", listenPort: 0, targetPort: stubPort)
        let listenPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let received = try await withCheckedThrowingContinuation { (c: CheckedContinuation<Data, Error>) in
            DispatchQueue.global().async {
                do {
                    let r = try RawHTTPClient.sendKeepAlivePOSIX(
                        Data("GET /missing HTTP/1.1\r\nHost: x\r\n\r\n".utf8),
                        toPort: listenPort,
                        host: "127.0.0.1"
                    )
                    c.resume(returning: r)
                } catch {
                    c.resume(throwing: error)
                }
            }
        }

        #expect(received == response)
        #expect((String(data: received, encoding: .utf8) ?? "").contains("404 Not Found"))
    }
}
