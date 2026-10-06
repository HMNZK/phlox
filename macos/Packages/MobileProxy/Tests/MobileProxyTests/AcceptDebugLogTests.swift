import Foundation
import Testing
@testable import MobileProxy

/// accept の debug ログは DEBUG ビルドだけがファイルへ書く。
@Suite struct AcceptDebugLogTests {

    @Test func acceptDebugLogWritePolicyMatchesBuildConfiguration() {
        #if DEBUG
        #expect(AcceptDebugLogPolicy.writesToFile)
        #else
        #expect(!AcceptDebugLogPolicy.writesToFile)
        #endif
    }

    #if DEBUG
    @Test func appendAcceptDebugLogWritesLineWhenDebugEnabled() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("mobileproxy-accept-test-\(UUID().uuidString).log")
            .path
        defer { try? FileManager.default.removeItem(atPath: path) }

        POSIXSocketListener.appendAcceptDebugLogForTesting(
            remoteIP: "127.0.0.1",
            accepted: true,
            to: path
        )

        let content = try String(contentsOfFile: path, encoding: .utf8)
        #expect(content.contains("remoteIP=127.0.0.1"))
        #expect(content.contains("decision=accept"))
    }
    #endif
}
