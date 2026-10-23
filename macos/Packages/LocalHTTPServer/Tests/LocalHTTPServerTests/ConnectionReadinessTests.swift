import Foundation
import Network
import Testing
import os
@testable import LocalHTTPServer

private struct ReadinessDriver: Sendable {
    struct State {
        var value: NWConnection.State = .setup
        var observer: (@Sendable (NWConnection.State) -> Void)?
        var restored = false
        var queuedObserver: (@Sendable (NWConnection.State) -> Void)?
    }
    let lock = OSAllocatedUnfairLock(initialState: State())

    func install(_ observer: @escaping @Sendable (NWConnection.State) -> Void) {
        lock.withLock { $0.observer = observer }
    }

    func transition(_ value: NWConnection.State, notify: Bool = true) {
        let observer = lock.withLock { state in
            state.value = value
            return state.observer
        }
        if notify { observer?(value) }
    }

    func snapshot() -> NWConnection.State { lock.withLock { $0.value } }
    func restore() { lock.withLock { $0.restored = true } }

    func queueReadyForCurrentObserver() {
        lock.withLock { state in
            state.value = .preparing
            state.queuedObserver = state.observer
        }
    }

    func deliverQueuedReady() {
        let observer = lock.withLock { state in
            state.value = .ready
            let observer = state.queuedObserver
            state.queuedObserver = nil
            return observer
        }
        observer?(.ready)
    }
}

@Suite(.timeLimit(.minutes(1))) struct ConnectionReadinessTests {
    @Test func registrationPrecedesStartWhenReadyIsQueuedBeforePreparingSnapshotReturns() async throws {
        let driver = ReadinessDriver()
        let oldReadyNotifications = OSAllocatedUnfairLock(initialState: 0)
        let previous: @Sendable (NWConnection.State) -> Void = { state in
            if case .ready = state { oldReadyNotifications.withLock { $0 += 1 } }
        }
        driver.install(previous)
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            driver.transition(.failed(.posix(.ETIMEDOUT)))
        }
        defer { watchdog.cancel() }
        try await LocalHTTPConnection.waitUntilReady(
            state: {
                let preparing = driver.snapshot()
                driver.deliverQueuedReady()
                return preparing
            },
            previous: previous,
            install: { driver.install($0) }, restore: { driver.restore() },
            start: { driver.queueReadyForCurrentObserver() }
        )
        #expect(driver.lock.withLock { $0.restored })
        #expect(oldReadyNotifications.withLock { $0 } == 0)
    }

    @Test func startAndWaitRegistersBeforeStartingRealAcceptedConnection() async throws {
        let queue = DispatchQueue(label: "readiness.start-before-wait")
        let listener = try LocalHTTPListener.makeListener(port: 0)
        let accepted = OSAllocatedUnfairLock(initialState: [NWConnection]())
        let result = AsyncStream<Bool>.makeStream()
        defer {
            listener.cancel()
            accepted.withLock { $0 }.forEach { $0.cancel() }
        }
        let port = try await LocalHTTPListener.startAndWaitUntilReady(listener, queue: queue) { connection in
            accepted.withLock { $0.append(connection) }
            Task {
                do {
                    try await LocalHTTPConnection.startAndWaitUntilReady(connection, queue: queue)
                    result.continuation.yield(connection.state == .ready)
                } catch { result.continuation.yield(false) }
                result.continuation.finish()
            }
        }
        let client = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
        defer { client.cancel() }
        try await LocalHTTPConnection.startAndWaitUntilReady(client, queue: queue)
        var iterator = result.stream.makeAsyncIterator()
        #expect(await iterator.next() == true)
    }

    @Test func readinessImmediatelyBeforeObserverRegistrationIsNotLost() async throws {
        let driver = ReadinessDriver()
        try await LocalHTTPConnection.waitUntilReady(
            state: { driver.snapshot() }, previous: nil,
            install: { observer in
                // Network.frameworkは登録前にreadyへ遷移しても再通知しない。
                driver.transition(.ready, notify: false)
                driver.install(observer)
            }, restore: { driver.restore() }
        )
        #expect(driver.lock.withLock { $0.restored })
    }

    @Test func readinessImmediatelyAfterRegistrationCompletesOnlyOnce() async throws {
        let driver = ReadinessDriver()
        try await LocalHTTPConnection.waitUntilReady(
            state: { driver.snapshot() }, previous: nil,
            install: { observer in
                driver.install(observer)
                driver.transition(.ready)
            }, restore: { driver.restore() }
        )
        // callbackとsnapshotの両方がreadyでもcontinuationは一度だけ完了する。
        #expect(driver.lock.withLock { $0.restored })
    }

    @Test(arguments: [false, true])
    func terminalCallbackDuringReadyHandlerRestorationReleasesSlot(failed: Bool) async throws {
        let driver = ReadinessDriver()
        let limiter = ConnectionLimiter(maxConnections: 1)
        let release = OnceGate()
        #expect(limiter.tryAcquire())
        let terminal: NWConnection.State = failed ? .failed(.posix(.ECONNRESET)) : .cancelled
        try await LocalHTTPConnection.waitUntilReady(
            state: { driver.snapshot() },
            previous: { state in
                switch state {
                case .failed, .cancelled:
                    if release.tryEnter() { limiter.release() }
                default: break
                }
            },
            install: { observer in
                driver.install(observer)
                driver.transition(.ready, notify: false)
            },
            restore: {
                // readyがOnceGateを取得した後、復元前に配送済みの終端通知が到着。
                driver.transition(terminal)
                driver.restore()
            }
        )
        #expect(limiter.activeCount == 0)
        #expect(limiter.tryAcquire())
    }

    @Test(arguments: [false, true])
    func terminalSnapshotThrowsWithoutWaitingForAnotherUpdate(failed: Bool) async {
        let driver = ReadinessDriver()
        driver.transition(failed ? .failed(.posix(.ECONNREFUSED)) : .cancelled, notify: false)
        do {
            try await LocalHTTPConnection.waitUntilReady(
                state: { driver.snapshot() }, previous: nil,
                install: { driver.install($0) }, restore: { driver.restore() }
            )
            Issue.record("終端状態はエラーを返す必要がある")
        } catch {
            if failed {
                #expect((error as? NWError) == .posix(.ECONNREFUSED))
            } else {
                #expect(error is LocalHTTPConnectionError)
            }
        }
        #expect(driver.lock.withLock { $0.restored })
    }

    @Test func realConnectionReadyBeforeAndAfterWaiting() async throws {
        let queue = DispatchQueue(label: "readiness.real")
        let listener = try LocalHTTPListener.makeListener(port: 0)
        let accepted = OSAllocatedUnfairLock(initialState: [NWConnection]())
        defer {
            listener.cancel()
            accepted.withLock { $0 }.forEach { $0.cancel() }
        }
        let port = try await LocalHTTPListener.startAndWaitUntilReady(listener, queue: queue) { connection in
            accepted.withLock { $0.append(connection) }
            connection.start(queue: queue)
        }
        let client = NWConnection(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: .tcp)
        defer { client.cancel() }
        client.start(queue: queue)
        try await LocalHTTPConnection.waitUntilReady(client)
        #expect(client.state == .ready)
        // 実NWConnectionがready済みで、再通知がなくてもsnapshotで完了する。
        try await LocalHTTPConnection.waitUntilReady(client)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            client.stateUpdateHandler = { state in
                if case .cancelled = state {
                    client.stateUpdateHandler = nil
                    continuation.resume()
                }
            }
            client.cancel()
        }
        do {
            try await LocalHTTPConnection.waitUntilReady(client)
            Issue.record("cancelled済みの実接続はエラーを返す必要がある")
        } catch {
            #expect(error is LocalHTTPConnectionError)
        }
    }
}
