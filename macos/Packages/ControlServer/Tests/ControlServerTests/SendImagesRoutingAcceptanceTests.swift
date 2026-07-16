import AgentDomain
import Foundation
import Network
import Testing
@testable import ControlServer

// task-2 受け入れテスト（PM 著・凍結）。契約: docs/specs/mobile-api-extensions-contract.md 5。
// アサーションの変更は禁止。ハーネス欠陥を発見した場合は PM に報告し、承認を得たうえで
// ハーネス部分に限り修理してよい。

private actor SendImagesHandlerStub {
    private(set) var lastRequest: ControlRequest?
    private(set) var callCount = 0

    func handle(_ request: ControlRequest) -> ControlResponse {
        lastRequest = request
        callCount += 1
        return .status(200)
    }
}

@Suite struct SendImagesRoutingAcceptanceTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    private static let mib = 1024 * 1024

    // MARK: - 正常系（デコードと配線）

    @Test func singleImageDecodesAndRoutesToSendText() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let body = """
        {"to":"agent-alpha","text":"この画面を見て","images":[{"mediaType":"image/png","dataBase64":"\(pngBytes.base64EncodedString())"}]}
        """
        let (status, _) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .sendText(let to, let text, let submit, let inReplyTo, let images)? = last?.action else {
            Issue.record("expected sendText, got \(String(describing: last?.action))")
            return
        }
        #expect(to == .name("agent-alpha"))
        #expect(text == "この画面を見て")
        #expect(submit == true)
        #expect(inReplyTo == nil)
        #expect(images.count == 1)
        #expect(images.first?.mediaType == "image/png")
        #expect(images.first?.data == pngBytes)
    }

    @Test func omittedImagesYieldsEmptyImages() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let body = """
        {"to":"agent-alpha","text":"hello","submit":false}
        """
        let (status, _) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .sendText(_, _, let submit, _, let images)? = last?.action else {
            Issue.record("expected sendText")
            return
        }
        #expect(submit == false)
        #expect(images.isEmpty)
    }

    @Test func emptyImagesArrayBehavesAsOmitted() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let body = """
        {"to":"agent-alpha","text":"hello","images":[]}
        """
        let (status, _) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .sendText(_, _, _, _, let images)? = last?.action else {
            Issue.record("expected sendText")
            return
        }
        #expect(images.isEmpty)
    }

    @Test func jpegMediaTypePassesThrough() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let body = """
        {"to":"agent-alpha","text":"x","images":[{"mediaType":"image/jpeg","dataBase64":"\(bytes.base64EncodedString())"}]}
        """
        let (status, _) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .sendText(_, _, _, _, let images)? = last?.action else {
            Issue.record("expected sendText")
            return
        }
        #expect(images.first?.mediaType == "image/jpeg")
    }

    // MARK: - 不正入力

    @Test func invalidBase64Returns400WithoutCallingHandler() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let body = """
        {"to":"agent-alpha","text":"x","images":[{"mediaType":"image/png","dataBase64":"@@not-base64@@"}]}
        """
        let (status, _) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 400)
        #expect(await stub.callCount == 0)
    }

    // MARK: - 上限（デスクトップ ComposerAttachments と同一: 4枚 / 1枚 4MiB / 合計 8MiB）

    @Test func fiveImagesReturn413AttachmentTooLarge() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let tiny = Data([0x01]).base64EncodedString()
        let entries = Array(repeating: "{\"mediaType\":\"image/png\",\"dataBase64\":\"\(tiny)\"}", count: 5)
            .joined(separator: ",")
        let body = """
        {"to":"agent-alpha","text":"x","images":[\(entries)]}
        """
        let (status, data) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 413)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["error"] as? String == "attachment too large")
        #expect(await stub.callCount == 0)
    }

    @Test func imageOverFourMiBDecodedReturns413() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let oversize = Data(repeating: 0xAB, count: 4 * Self.mib + 1).base64EncodedString()
        let body = """
        {"to":"agent-alpha","text":"x","images":[{"mediaType":"image/png","dataBase64":"\(oversize)"}]}
        """
        let (status, data) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 413)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["error"] as? String == "attachment too large")
        #expect(await stub.callCount == 0)
    }

    @Test func imageExactlyFourMiBPasses() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        let exact = Data(repeating: 0xCD, count: 4 * Self.mib)
        let body = """
        {"to":"agent-alpha","text":"x","images":[{"mediaType":"image/png","dataBase64":"\(exact.base64EncodedString())"}]}
        """
        let (status, _) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .sendText(_, _, _, _, let images)? = last?.action else {
            Issue.record("expected sendText")
            return
        }
        #expect(images.first?.data.count == 4 * Self.mib)
    }

    @Test func totalOverEightMiBReturns413() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        // 1枚あたりは 4MiB 以内だが合計が 8MiB を超える（4MiB + 4MiB + 1KiB）
        let four = Data(repeating: 0x11, count: 4 * Self.mib).base64EncodedString()
        let small = Data(repeating: 0x22, count: 1024).base64EncodedString()
        let body = """
        {"to":"agent-alpha","text":"x","images":[{"mediaType":"image/png","dataBase64":"\(four)"},{"mediaType":"image/png","dataBase64":"\(four)"},{"mediaType":"image/png","dataBase64":"\(small)"}]}
        """
        let (status, data) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 413)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["error"] as? String == "attachment too large")
        #expect(await stub.callCount == 0)
    }

    @Test func totalExactlyEightMiBPasses() async throws {
        let stub = SendImagesHandlerStub()
        let (port, server) = try await startServer(stub: stub)
        _ = server
        // 合計ちょうど 8MiB（4MiB × 2）。base64 で約 10.7MB の body が transport を通ることも同時に検証する
        let four = Data(repeating: 0x33, count: 4 * Self.mib).base64EncodedString()
        let body = """
        {"to":"agent-alpha","text":"x","images":[{"mediaType":"image/png","dataBase64":"\(four)"},{"mediaType":"image/jpeg","dataBase64":"\(four)"}]}
        """
        let (status, _) = try await request(port: port, method: "POST", path: "/send", bearer: token, body: body)
        #expect(status == 200)

        let last = await stub.lastRequest
        guard case .sendText(_, _, _, _, let images)? = last?.action else {
            Issue.record("expected sendText")
            return
        }
        #expect(images.count == 2)
        #expect(images.reduce(0) { $0 + $1.data.count } == 8 * Self.mib)
    }

    // MARK: - Helpers（自己完結）

    private func startServer(stub: SendImagesHandlerStub) async throws -> (port: Int, server: ControlServer) {
        let store = SessionTokenStore()
        await store.register(token, for: sessionID)
        let server = ControlServer(tokenStore: store, agentCatalog: .builtins) { request in
            await stub.handle(request)
        }
        let port = try await server.start()
        return (port, server)
    }

    private func request(
        port: Int,
        method: String,
        path: String,
        bearer: String? = nil,
        body: String? = nil
    ) async throws -> (Int, Data) {
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        urlRequest.httpMethod = method
        if let bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = Data(body.utf8)
        }
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        return ((response as? HTTPURLResponse)?.statusCode ?? -1, data)
    }
}
