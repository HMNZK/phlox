import Foundation
import Testing
@testable import DashboardFeature

@MainActor
struct SimulatorXPCTransportTests {
    @Test func 実XPCの接続エラーをMainActorへ届け本体をクラッシュさせない() async throws {
        let connection = NSXPCConnection(machServiceName: "com.phlox.tests.missing." + UUID().uuidString)
        let transport = SimulatorXPCTransport(connection: connection)
        var errors: [String] = []
        var replied = false
        transport.resume(surfaceChanged: { _ in Issue.record("存在しないサービスから画面が届いた") },
                         failed: { errors.append($0) })
        defer { transport.invalidate() }
        transport.probe { _ in replied = true }
        let deadline = ContinuousClock.now + .seconds(5)
        while errors.isEmpty && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!errors.isEmpty)
        #expect(errors.allSatisfy { !$0.isEmpty })
        #expect(!replied)
    }
}
