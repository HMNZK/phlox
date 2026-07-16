import Foundation
import Testing
@testable import MobileProxy

/// task-2: B② debug ログの DEBUG ガード / B① 未同梱クライアント向け案内の非表示ポリシー。
@Suite struct Task2MaturityFixTests {

    // MARK: - B② Accept debug log

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

    // MARK: - B① Mobile connection guide visibility

    /// 表示可否は同梱フラグと常に一致。`isCompanionClientBundled` を true にすれば UI ゲートも表示へ切り替わる。
    @Test func settingsConnectionSectionVisibilityFollowsCompanionBundleFlag() {
        #expect(
            MobileConnectionGuidePolicy.showsSettingsConnectionSection
                == MobileConnectionGuidePolicy.isCompanionClientBundled
        )
    }
}
