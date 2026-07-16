import AgentDomain
import Foundation
import Network
import Testing
@testable import HookServer

/// start(preferredPort:) の起動経路(本番 CompositionRoot が使う唯一の経路)を検証する。
@Suite struct HookServerStartTests {
    private let sessionID = SessionID()

    @Test func startBindsToPreferredPortWhenFree() async throws {
        let freePort = try await Self.findFreePort()
        let server = HookServer()

        let port = try await server.start(preferredPort: freePort)

        #expect(port == Int(freePort))
        let body = """
        {"sessionId":"\(sessionID.rawValue.uuidString)","kind":"sessionStart"}
        """
        let statusCode = try await HookServerIntegrationTests.postHookStatic(port: port, body: body)
        #expect(statusCode == 200)
    }

    @Test func startFallsBackToRandomPortWhenPreferredPortIsOccupied() async throws {
        let occupier = HookServer()
        let occupiedPort = try await occupier.start()
        let server = HookServer()

        let port = try await server.start(preferredPort: UInt16(occupiedPort))

        #expect(port != occupiedPort)
        let body = """
        {"sessionId":"\(sessionID.rawValue.uuidString)","kind":"sessionStart"}
        """
        let statusCode = try await HookServerIntegrationTests.postHookStatic(port: port, body: body)
        #expect(statusCode == 200)
    }

    @Test func secondStartAfterSuccessThrowsAlreadyStarted() async throws {
        let server = HookServer()
        _ = try await server.start(preferredPort: 0)

        do {
            _ = try await server.start(preferredPort: 0)
            Issue.record("二重 start が alreadyStarted を投げずに成功した")
        } catch HookServerError.alreadyStarted {
            // 期待どおり
        }
    }

    // MARK: - Helpers

    /// カーネルに空きポートを割り当てさせてから閉じ、そのポート番号を返す。
    /// 閉じた直後に再 bind するため、.cancelled まで待ってから返す。
    private static func findFreePort() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.acceptLocalOnly = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 0)!
        )
        let listener = try NWListener(using: parameters)
        let queue = DispatchQueue(label: "HookServerStartTests.findFreePort")

        let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
            // newConnectionHandler 未設定だと NWListener は EINVAL で失敗する
            listener.newConnectionHandler = { connection in
                connection.cancel()
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { state in
                if case .cancelled = state {
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                }
            }
            listener.cancel()
        }

        return port
    }
}
