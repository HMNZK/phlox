import Foundation
import Testing
@testable import MobileProxy

@Suite struct MobileProxyRecoveryTests {
    @Test func refreshPromotesLoopbackToTailscaleAndPublishesUsablePort() async throws {
        let response = Data("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok".utf8)
        let stub = try StubHTTPServer(rawResponse: response)
        let stubPort = try await stub.start()
        defer { stub.stop() }

        let resolver = ScriptedResolver([
            CommandResult(exitCode: 1, standardOutput: ""),
            CommandResult(exitCode: 0, standardOutput: "100.64.1.2\n"),
        ])
        let proxy = MobileProxy(
            listenPort: 0,
            targetPort: stubPort,
            resolver: TailscaleIPResolver(runner: resolver.run)
        )
        _ = try await proxy.start()
        defer { Task { await proxy.stop() } }

        #expect(await proxy.bindMode == .loopbackOnly)

        let refreshedMode = await proxy.refresh()
        let refreshedPort = try #require(await proxy.boundPort)

        #expect(refreshedMode == .tailscale("100.64.1.2"))
        #expect(await proxy.bindMode == .tailscale("100.64.1.2"))
        #expect(refreshedPort > 0)

        let received = try await RawHTTPClient.send(
            Data("GET /health HTTP/1.1\r\nHost: x\r\n\r\n".utf8),
            toPort: refreshedPort,
            host: "127.0.0.1"
        )
        #expect(received == response)
    }

    @Test func refreshIsNoOpWhenAlreadyOnTailscale() async throws {
        let resolver = ScriptedResolver([
            CommandResult(exitCode: 0, standardOutput: "100.64.1.2\n"),
            CommandResult(exitCode: 0, standardOutput: "100.64.9.9\n"),
        ])
        let proxy = MobileProxy(
            listenPort: 0,
            targetPort: 1,
            resolver: TailscaleIPResolver(runner: resolver.run)
        )
        let initialPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let refreshedMode = await proxy.refresh()

        #expect(refreshedMode == .tailscale("100.64.1.2"))
        #expect(await proxy.boundPort == initialPort)
        #expect(resolver.callCount == 1)
    }

    @Test func refreshDoesNotOverrideExplicitHost() async throws {
        let resolver = ScriptedResolver([
            CommandResult(exitCode: 0, standardOutput: "100.64.1.2\n"),
        ])
        let proxy = MobileProxy(
            listenHost: "127.0.0.1",
            listenPort: 0,
            targetPort: 1,
            resolver: TailscaleIPResolver(runner: resolver.run)
        )
        let initialPort = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let refreshedMode = await proxy.refresh()

        #expect(refreshedMode == .explicitHost("127.0.0.1"))
        #expect(await proxy.boundPort == initialPort)
        #expect(resolver.callCount == 0)
    }

    @Test func recoveryStopsEarlyWhenTailscaleBecomesReachable() async throws {
        let resolver = ScriptedResolver([
            CommandResult(exitCode: 1, standardOutput: ""),
            CommandResult(exitCode: 1, standardOutput: ""),
            CommandResult(exitCode: 0, standardOutput: "100.64.1.2\n"),
            CommandResult(exitCode: 0, standardOutput: "100.64.9.9\n"),
        ])
        let sleeps = CallCounter()
        let proxy = MobileProxy(
            listenPort: 0,
            targetPort: 1,
            resolver: TailscaleIPResolver(runner: resolver.run)
        )
        _ = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let mode = await proxy.recoverUntilReachable(
            maxAttempts: 5,
            delay: .seconds(30),
            sleep: { _ in sleeps.increment() }
        )

        #expect(mode == .tailscale("100.64.1.2"))
        #expect(resolver.callCount == 3)
        #expect(sleeps.value == 1)
    }

    @Test func recoveryWithNonPositiveAttemptLimitDoesNothing() async throws {
        let resolver = ScriptedResolver([
            CommandResult(exitCode: 1, standardOutput: ""),
            CommandResult(exitCode: 0, standardOutput: "100.64.1.2\n"),
        ])
        let sleeps = CallCounter()
        let proxy = MobileProxy(
            listenPort: 0,
            targetPort: 1,
            resolver: TailscaleIPResolver(runner: resolver.run)
        )
        _ = try await proxy.start()
        defer { Task { await proxy.stop() } }

        let mode = await proxy.recoverUntilReachable(
            maxAttempts: 0,
            delay: .zero,
            sleep: { _ in sleeps.increment() }
        )

        #expect(mode == .loopbackOnly)
        #expect(resolver.callCount == 1)
        #expect(sleeps.value == 0)
    }
}

private final class ScriptedResolver: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [CommandResult]
    private var calls = 0

    init(_ results: [CommandResult]) {
        self.results = results
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    func run(_ arguments: [String]) -> CommandResult {
        lock.withLock {
            calls += 1
            if results.count > 1 {
                return results.removeFirst()
            }
            return results[0]
        }
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
