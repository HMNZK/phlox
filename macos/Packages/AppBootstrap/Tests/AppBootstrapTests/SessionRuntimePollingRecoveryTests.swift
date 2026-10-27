import DashboardFeature
import Foundation
import LocalHTTPServer
import Network
import Testing
@testable import AppBootstrap

@Suite struct SessionRuntimePollingRecoveryTests {
    @Test @MainActor func readTimeoutAutomaticallyDisplaysLaterSnapshotWithoutSendingACommand() async throws {
        let server = try PollingHTTPFixture(firstResponseDelay: 31)
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var displayed = 0
        var failures: [Error] = []
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            displayed += 1
        }, onFailure: { failures.append($0) })

        await pollingWait(until: { displayed > 0 }, timeout: .seconds(40))

        #expect(displayed > 0)
        #expect(failures.contains { ($0 as? URLError)?.code == .timedOut })
        #expect(server.paths.filter { $0 == "/snapshot" }.count >= 2)
        #expect(server.paths.allSatisfy { $0 == "/snapshot" })
    }

    @Test @MainActor func timeoutWhileApplyingSnapshotAutomaticallyRetries() async throws {
        let server = try PollingHTTPFixture()
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var attempts = 0
        var displayed = false
        var failures: [Error] = []
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            attempts += 1
            if attempts == 1 { throw URLError(.timedOut) }
            displayed = true
        }, onFailure: { failures.append($0) })

        await pollingWait(until: { displayed })

        #expect(displayed)
        #expect(failures.count == 1)
        #expect((failures.first as? URLError)?.code == .timedOut)
        #expect(server.paths.allSatisfy { $0 == "/snapshot" })
    }

    @Test(arguments: [401, 409, 413]) @MainActor
    func fatalReadStatusStopsPolling(status: Int) async throws {
        let server = try PollingHTTPFixture(status: status)
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var displayed = 0
        var failures: [Error] = []
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            displayed += 1
        }, onFailure: { failures.append($0) })
        await pollingWait(until: { !failures.isEmpty })
        let requestsAtFailure = server.paths.count
        try await Task.sleep(for: .milliseconds(1200))

        #expect(displayed == 0)
        #expect(failures.count == 1)
        let connectionError = failures.first as? SessionRuntimeConnectionError
        switch status {
        case 401: #expect(connectionError == .unauthorized)
        case 413: #expect(connectionError == .responseTooLarge)
        default:
            if case .rejected(_)? = connectionError {} else { Issue.record("HTTP409 must remain rejected") }
        }
        #expect(requestsAtFailure == 1)
        #expect(server.paths.count == requestsAtFailure)
    }

    @Test @MainActor func malformedSnapshotStopsPolling() async throws {
        let server = try PollingHTTPFixture(malformedResponse: true)
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var displayed = 0
        var failures: [Error] = []
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            displayed += 1
        }, onFailure: { failures.append($0) })
        await pollingWait(until: { !failures.isEmpty })
        try await Task.sleep(for: .milliseconds(1200))

        #expect(displayed == 0)
        #expect(failures.count == 1)
        #expect(failures.first is DecodingError)
        #expect(server.paths.count == 1)
    }

    @Test @MainActor func incompatibleSnapshotApplicationStopsPolling() async throws {
        let server = try PollingHTTPFixture()
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var attempts = 0
        var failures: [Error] = []
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            attempts += 1
            throw SessionRuntimeConnectionError.incompatibleProtocol
        }, onFailure: { failures.append($0) })
        await pollingWait(until: { !failures.isEmpty })
        try await Task.sleep(for: .milliseconds(1200))

        #expect(attempts == 1)
        #expect(failures.count == 1)
        #expect(failures.first as? SessionRuntimeConnectionError == .incompatibleProtocol)
        #expect(server.paths.count == 1)
    }

    @Test @MainActor func successfulRecoveryResetsRetryDelay() async throws {
        let server = try PollingHTTPFixture()
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var attempts = 0
        var failedAt = ContinuousClock.now
        var recoveries: [Duration] = []
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            attempts += 1
            if attempts == 1 || attempts == 3 {
                failedAt = .now
                throw URLError(.timedOut)
            }
            recoveries.append(failedAt.duration(to: .now))
            if recoveries.count == 2 { client.disconnect() }
        }, onFailure: { _ in })
        await pollingWait(until: { recoveries.count == 2 })

        #expect(recoveries.count == 2)
        if recoveries.count == 2 {
            #expect(recoveries[1] < .milliseconds(1750))
        }
    }

    @Test @MainActor func disconnectCancelsPendingReadWithoutFailureOrSnapshot() async throws {
        let server = try PollingHTTPFixture(firstResponseDelay: 1)
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var displayed = 0
        var failures = 0
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            displayed += 1
        }, onFailure: { _ in failures += 1 })
        await pollingWait(until: { !server.paths.isEmpty })
        client.disconnect()
        try await Task.sleep(for: .milliseconds(1200))

        #expect(server.paths.count == 1)
        #expect(displayed == 0)
        #expect(failures == 0)
    }

    @Test @MainActor func disconnectDuringRecoveryCancelsRetry() async throws {
        let server = try PollingHTTPFixture()
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var attempts = 0
        var failures = 0
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            attempts += 1
            throw URLError(.timedOut)
        }, onFailure: { _ in failures += 1 })
        await pollingWait(until: { failures > 0 })
        client.disconnect()
        try await Task.sleep(for: .milliseconds(1200))

        #expect(attempts == 1)
        #expect(failures == 1)
        #expect(server.paths.count == 1)
    }

    @Test @MainActor func restartingPollingCancelsOldRecoveryAndKeepsOneObserver() async throws {
        let server = try PollingHTTPFixture()
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var oldAttempts = 0
        var oldFailures = 0
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            oldAttempts += 1
            throw URLError(.timedOut)
        }, onFailure: { _ in oldFailures += 1 })
        await pollingWait(until: { oldFailures > 0 })
        var newAttempts = 0
        var newFailures = 0
        client.startPolling(interval: .milliseconds(20), onSnapshot: { _ in
            newAttempts += 1
        }, onFailure: { _ in newFailures += 1 })
        await pollingWait(until: { newAttempts >= 2 })
        client.disconnect()
        let requestsAfterDisconnect = server.paths.count
        try await Task.sleep(for: .milliseconds(1200))

        #expect(oldAttempts == 1)
        #expect(oldFailures == 1)
        #expect(newAttempts >= 2)
        #expect(newFailures == 0)
        #expect(server.paths.count == requestsAfterDisconnect)
        #expect(server.paths.allSatisfy { $0 == "/snapshot" })
    }

    @Test @MainActor func repeatedTransientFailuresWaitAndStopAfterDisconnect() async throws {
        let server = try PollingHTTPFixture()
        defer { server.stop() }
        let client = try await server.client()
        defer { client.disconnect() }
        var failures: [ContinuousClock.Instant] = []
        client.startPolling(interval: .milliseconds(1), onSnapshot: { _ in
            throw URLError(.timedOut)
        }, onFailure: { _ in failures.append(.now) })
        await pollingWait(until: { failures.count >= 3 }, timeout: .seconds(12))
        client.disconnect()
        let requestsAfterDisconnect = server.paths.count
        let failuresAfterDisconnect = failures.count
        try await Task.sleep(for: .milliseconds(1200))

        #expect(failures.count >= 3)
        if failures.count >= 3 {
            #expect(failures[0].duration(to: failures[1]) >= .milliseconds(900))
            #expect(failures[1].duration(to: failures[2]) >= .milliseconds(1800))
        }
        #expect(server.paths.count == requestsAfterDisconnect)
        #expect(failures.count == failuresAfterDisconnect)
        #expect(server.paths.allSatisfy { $0 == "/snapshot" })
    }
}

@MainActor
private func pollingWait(until predicate: () -> Bool, timeout: Duration = .seconds(8)) async {
    let deadline = ContinuousClock.now + timeout
    while !predicate(), ContinuousClock.now < deadline {
        do { try await Task.sleep(for: .milliseconds(10)) }
        catch { Issue.record("polling wait was cancelled: \(error)"); return }
    }
}

private final class PollingHTTPFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "Phlox.polling-recovery-test")
    private let lock = NSLock()
    private var connections: [NWConnection] = []
    private var receivedPaths: [String] = []
    private var stopped = false
    private let firstResponseDelay: TimeInterval
    private let status: Int
    private let malformedResponse: Bool

    var paths: [String] { lock.withLock { receivedPaths } }

    init(firstResponseDelay: TimeInterval = 0, status: Int = 200, malformedResponse: Bool = false) throws {
        listener = try LocalHTTPListener.makeListener(port: 0)
        self.firstResponseDelay = firstResponseDelay
        self.status = status
        self.malformedResponse = malformedResponse
    }

    @MainActor func client() async throws -> SessionRuntimeClient {
        let port = try await LocalHTTPListener.startAndWaitUntilReady(listener, queue: queue) { [weak self] connection in
            self?.receive(connection)
        }
        return SessionRuntimeClient(endpoint: try .init(
            url: URL(string: "http://127.0.0.1:\(port)")!, generation: UUID(), token: "polling-test"
        ))
    }

    func stop() {
        listener.cancel()
        lock.withLock {
            stopped = true
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func receive(_ connection: NWConnection) {
        lock.withLock { connections.append(connection) }
        Task { [self] in
            do {
                try await LocalHTTPConnection.startAndWaitUntilReady(connection, queue: queue)
                let request = try await LocalHTTPConnection.receiveRequest(from: connection)
                let count = lock.withLock { receivedPaths.append(request.path); return receivedPaths.count }
                let envelope = SessionRuntimeSnapshotEnvelope(sequence: UInt64(count), snapshot: .init(projects: [], sessions: [], availableAgentKinds: []))
                let body = malformedResponse ? Data("{".utf8) : try JSONEncoder().encode(envelope)
                let header = Data("HTTP/1.1 \(status) Test\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
                let delay = count == 1 ? firstResponseDelay : 0
                try await Task.sleep(for: .seconds(delay))
                await LocalHTTPConnection.sendAndClose(header + body, over: connection)
            } catch {
                if !lock.withLock({ stopped }) { Issue.record("polling fixture failed: \(error)") }
                connection.cancel()
            }
        }
    }
}
