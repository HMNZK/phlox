import AgentDomain
import Foundation
import Testing
@testable import HookServer

/// リクエストボディのサイズ上限(ControlServer と同等の 256 KiB)を検証する。
@Suite struct HookServerBodyLimitTests {
    @Test func oversizedBodyReturns413() async throws {
        let server = HookServer()
        let port = try await server.start()

        // 上限 256 KiB を超える 300 KiB のボディ
        let body = String(repeating: "x", count: 300 * 1024)
        let statusCode = try await HookServerIntegrationTests.postHookStatic(port: port, body: body)

        #expect(statusCode == 413)
    }

    @Test func bodyAtLimitIsAcceptedAndParsed() async throws {
        // 上限ちょうどのボディは 413 にならず通常処理される(不正 JSON なので 400)
        let server = HookServer()
        let port = try await server.start()

        let body = String(repeating: "x", count: 256 * 1024)
        let statusCode = try await HookServerIntegrationTests.postHookStatic(port: port, body: body)

        #expect(statusCode == 400)
    }
}
