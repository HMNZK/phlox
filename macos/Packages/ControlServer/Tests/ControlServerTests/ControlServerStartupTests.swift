import AgentDomain
import Foundation
import Network
import os
import Testing
@testable import ControlServer

/// 初回の生成だけ占有済みポートへ束縛し、リスナーを起動失敗(.failed)させるファクトリ。
/// 2 回目以降は渡されたパラメータのまま実生成する。
private final class FailFirstListenerFactory: Sendable {
    private let occupiedPort: UInt16
    private let didFail = OSAllocatedUnfairLock(initialState: false)

    init(occupiedPort: UInt16) {
        self.occupiedPort = occupiedPort
    }

    func make(_ parameters: NWParameters) throws -> NWListener {
        let isFirst = didFail.withLock { failed in
            if failed {
                return false
            }
            failed = true
            return true
        }
        if isFirst {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host("127.0.0.1"),
                port: NWEndpoint.Port(rawValue: occupiedPort)!
            )
        }
        return try NWListener(using: parameters)
    }
}

@Suite struct ControlServerStartupTests {
    private let sessionID = SessionID()
    private let token = "test-bearer-token"

    @Test func preferredPortFallsBackToRandomPortWhenOccupied() async throws {
        let (occupiedPort, serverA) = try await startServer()
        _ = serverA

        let serverB = makeServer(tokenStore: await makeTokenStore())
        let portB = try await serverB.start(preferredPort: UInt16(occupiedPort))

        #expect(portB != occupiedPort)
        let status = try await request(port: portB, method: "GET", path: "/sessions", bearer: token)
        #expect(status == 200)
    }

    @Test func secondStartThrowsAlreadyStarted() async throws {
        let (_, server) = try await startServer()

        do {
            _ = try await server.start()
            Issue.record("expected alreadyStarted")
        } catch let error as ControlServerError {
            guard case .alreadyStarted = error else {
                Issue.record("expected alreadyStarted, got \(error)")
                return
            }
        }
    }

    @Test func startWithPreferredPortZeroBehavesLikeStart() async throws {
        let server = makeServer(tokenStore: await makeTokenStore())
        let port = try await server.start(preferredPort: 0)

        #expect((1...65_535).contains(port))
        let status = try await request(port: port, method: "GET", path: "/sessions", bearer: token)
        #expect(status == 200)
    }

    @Test func startSucceedsAfterPreviousStartFailure() async throws {
        // 占有ポートを用意して初回起動を確実に失敗させる
        let (occupiedPort, serverA) = try await startServer()
        _ = serverA

        let factory = FailFirstListenerFactory(occupiedPort: UInt16(occupiedPort))
        let server = ControlServer(
            tokenStore: await makeTokenStore(),
            handler: { _ in .status(200) },
            makeListener: { try factory.make($0) }
        )

        await #expect(throws: ControlServerError.self) {
            _ = try await server.start()
        }

        // 失敗後にもう一度 start できる(残留 listener があると alreadyStarted で恒久失敗する)
        let port = try await server.start()
        let status = try await request(port: port, method: "GET", path: "/sessions", bearer: token)
        #expect(status == 200)
    }

    // MARK: - Helpers

    private func makeTokenStore() async -> SessionTokenStore {
        let store = SessionTokenStore()
        await store.register(token, for: sessionID)
        return store
    }

    private func makeServer(tokenStore: SessionTokenStore) -> ControlServer {
        ControlServer(tokenStore: tokenStore) { _ in .status(200) }
    }

    private func startServer() async throws -> (port: Int, server: ControlServer) {
        let server = makeServer(tokenStore: await makeTokenStore())
        let port = try await server.start()
        return (port, server)
    }

    private func request(
        port: Int,
        method: String,
        path: String,
        bearer: String? = nil
    ) async throws -> Int {
        var urlRequest = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        urlRequest.httpMethod = method
        if let bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        return (response as? HTTPURLResponse)?.statusCode ?? -1
    }
}
