import AgentDomain
import Foundation
import Network
import Testing
@testable import ControlServer

private extension ControlServer {
    // このactorを保持して、受付Taskのhandleが始まる前に停止を実行する。
    func acceptThenDrain(_ connection: NWConnection) async -> Bool {
        acceptConnection(connection)
        return await stopAcceptingAndDrain(timeout: .zero)
    }
}

@Suite struct HandoverRequestDrainTests {
    @Test func acceptedConnectionIsCountedBeforeActorTaskStarts() async throws {
        let server = ControlServer(tokenStore: SessionTokenStore()) { _ in .status(200) }
        _ = try await server.start()
        let connection = NWConnection(host: "127.0.0.1", port: 1, using: .tcp)
        defer { connection.cancel() }

        #expect(!(await server.acceptThenDrain(connection)))
        let deadline = ContinuousClock.now + .seconds(1)
        while case .setup = connection.state {
            guard ContinuousClock.now < deadline else {
                Issue.record("accepted connection task did not start")
                return
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        connection.cancel()
        #expect(await server.stopAcceptingAndDrain(timeout: .seconds(2)))

        // 停止後に遅れて届いたcallbackは新しい処理を登録しない。
        let late = NWConnection(host: "127.0.0.1", port: 1, using: .tcp)
        defer { late.cancel() }
        #expect(await server.acceptThenDrain(late))
    }
}
