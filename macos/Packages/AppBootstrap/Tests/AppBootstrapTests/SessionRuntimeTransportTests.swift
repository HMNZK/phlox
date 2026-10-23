import Foundation
import Darwin
import AgentDomain
import DashboardFeature
import Testing
@testable import AppBootstrap

@Suite struct SessionRuntimeTransportTests {
    @Test func fullNormalPendingByteBudgetPreservesUrgentExecutionAndDeduplication() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation, maximumBytes: 32 * 1024)
        let blocked = RuntimeHeldCommands()
        let firstOperation = SessionRuntimeOperation(generation: generation, payload: Data(repeating: 1, count: 14 * 1024))
        let secondOperation = SessionRuntimeOperation(generation: generation, payload: Data(repeating: 2, count: 14 * 1024))
        let first = Task {
            do { return try await ledger.perform(firstOperation, maximumResultBytes: 0) { await blocked.wait() } }
            catch { blocked.entered.continuation.finish(); throw error }
        }
        let second = Task {
            do { return try await ledger.perform(secondOperation, maximumResultBytes: 0) { await blocked.wait() } }
            catch { blocked.entered.continuation.finish(); throw error }
        }
        var entered = blocked.entered.stream.makeAsyncIterator()
        _ = await entered.next()
        _ = await entered.next()
        do {
            await #expect(throws: SessionRuntimeConnectionError.self) {
                _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 0) { Data() }
            }
            let urgent = SessionRuntimeOperation(generation: generation, payload: Data())
            let counter = RuntimeCommandCounter()
            let value = try await ledger.perform(urgent, maximumResultBytes: 1024, urgent: true) { await counter.increment() }
            let replay = try await ledger.perform(urgent, maximumResultBytes: 1024, urgent: true) { await counter.increment() }
            #expect(value == replay)
            #expect(await counter.value == 1)
        } catch {
            await blocked.release()
            _ = try await first.value
            _ = try await second.value
            throw error
        }
        await blocked.release()
        _ = try await first.value
        _ = try await second.value
    }

    @Test func fullNormalRetainedByteBudgetPreservesUrgentExecution() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation, maximumBytes: 32 * 1024)
        _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 29 * 1024) {
            Data(repeating: 1, count: 29 * 1024)
        }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 0) { Data() }
        }
        let result = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 1024, urgent: true) { Data([7]) }
        #expect(result == Data([7]))
    }

    @Test func fullNormalEntryBudgetPreservesUrgentEntryAndDeduplication() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation, maximumOperations: 32)
        for _ in 0..<30 {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 0) { Data() }
        }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data()), maximumResultBytes: 0) { Data() }
        }
        let operation = SessionRuntimeOperation(generation: generation, payload: Data())
        let counter = RuntimeCommandCounter()
        _ = try await ledger.perform(operation, maximumResultBytes: 1024, urgent: true) { await counter.increment() }
        _ = try await ledger.perform(operation, maximumResultBytes: 1024, urgent: true) { await counter.increment() }
        #expect(await counter.value == 1)
    }

    @Test func snapshotLeaseStartsAtFetchAndExpiresAfterThirtyFiveSeconds() {
        let start = ContinuousClock.now
        let value = SessionRuntimeReceivedSnapshot(
            envelope: .init(sequence: 1, snapshot: .init(projects: [], sessions: [], availableAgentKinds: [])),
            startedAt: start
        )
        #expect(value.isFresh(at: start + .seconds(35)))
        #expect(!value.isFresh(at: start + .seconds(35) + .nanoseconds(1)))
    }

    @Test func twoMinutesOfTwentyKeysPerSecondAreDeliveredAndRemainDeduplicated() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation)
        let start = Date()
        let recorder = RuntimeKeyRecorder()
        var operations: [SessionRuntimeOperation] = []
        var expected = Data()
        for index in 0..<2400 {
            let key = Data([UInt8(index % 26 + 97)])
            expected.append(key)
            let instant = start.addingTimeInterval(Double(index) / 20)
            let operation = SessionRuntimeOperation(generation: generation, issuedAt: instant, payload: key)
            operations.append(operation)
            _ = try await ledger.perform(operation, now: instant) { await recorder.append(key) }
        }
        for operation in [operations[0], operations[2399]] {
            _ = try await ledger.perform(operation, now: start.addingTimeInterval(119.99)) {
                await recorder.append(operation.payload)
            }
        }
        #expect(await recorder.input == expected)
    }

    @Test @MainActor func pendingCommandAllowsSameClientReadsAndInterruptAndOtherClientHandshake() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let probe = RuntimePendingTurn()
        let transport = try SessionRuntimeTransport(
            generation: generation, storeURL: fixture.url,
            snapshot: {
                probe.snapshotsWhilePending += probe.completed ? 0 : 1
                return .init(projects: [], sessions: [], availableAgentKinds: [])
            },
            command: { command in
                switch command {
                case .session(_, _, .send): await probe.start()
                case .session(_, _, .interrupt): probe.interrupt()
                default: break
                }
                return .none
            }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation, token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let client = SessionRuntimeClient(endpoint: endpoint)
        let sessionID = SessionID()
        let executionID = UUID()
        let sending = Task { try await client.command(.session(sessionID, executionID, .send(text: "run", submit: true, attachments: [], skill: nil))) }
        var entered = probe.entered.stream.makeAsyncIterator()
        _ = await entered.next()
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            probe.release()
        }
        defer { watchdog.cancel(); probe.release() }
        try await SessionRuntimeClient(endpoint: endpoint).handshake()
        _ = try await client.snapshot()
        _ = try await client.command(.session(sessionID, executionID, .interrupt))
        _ = try await sending.value
        #expect(probe.starts == 1)
        #expect(probe.snapshotsWhilePending > 0)
        #expect(probe.interruptedWhilePending)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func retriedPendingHTTPCommandExecutesOnceWhileControlsRemainAvailable() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let probe = RuntimePendingTurn()
        let transport = try SessionRuntimeTransport(
            generation: generation, storeURL: fixture.url,
            snapshot: {
                probe.snapshotsWhilePending += probe.completed ? 0 : 1
                return .init(projects: [], sessions: [], availableAgentKinds: [])
            },
            command: { command in
                switch command {
                case .session(_, _, .send): await probe.start()
                case .session(_, _, .interrupt): probe.interrupt()
                default: break
                }
                return .none
            }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation, token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let sessionID = SessionID()
        let executionID = UUID()
        let command = DashboardRuntimeCommand.session(sessionID, executionID, .send(text: "run", submit: true, attachments: [], skill: nil))
        let operation = SessionRuntimeOperation(generation: generation, payload: try JSONEncoder().encode(command))
        let first = Task { try await runtimeHTTPCommand(operation, endpoint: endpoint) }
        var entered = probe.entered.stream.makeAsyncIterator()
        _ = await entered.next()
        let duplicate = Task { try await runtimeHTTPCommand(operation, endpoint: endpoint) }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(2)) }
            catch { return }
            probe.release()
        }
        defer { watchdog.cancel(); probe.release() }
        let reattached = SessionRuntimeClient(endpoint: endpoint)
        try await reattached.handshake()
        _ = try await reattached.snapshot()
        _ = try await reattached.command(.session(sessionID, executionID, .interrupt))
        let firstReply = try await first.value
        let duplicateReply = try await duplicate.value
        #expect(firstReply == duplicateReply)
        #expect(probe.starts == 1)
        #expect(probe.snapshotsWhilePending > 0)
        #expect(probe.interruptedWhilePending)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }
    @Test func imageDraftLimitsAccountForNestedBase64WithoutChangingSnapshotLimit() {
        let rawBytes = ImageAttachmentLimits.maxTotalInputBytes
        let innerJSONBytes = ((rawBytes + 2) / 3) * 4
        let outerJSONBytes = ((innerJSONBytes + 2) / 3) * 4
        #expect(SessionRuntimeTransport.maximumRequestBytes > outerJSONBytes)
        #expect(SessionRuntimeTransport.maximumCommandReplyBytes > innerJSONBytes)
        #expect(SessionRuntimeTransport.maximumSnapshotBytes == 64 * 1024 * 1024)
        #expect(SessionRuntimeTransport.maximumRequestBytes == 160 * 1024 * 1024)
        #expect(SessionRuntimeTransport.maximumCommandReplyBytes == 128 * 1024 * 1024)
    }

    @Test @MainActor func largeCommandAndReplyUseTheirOwnLimits() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let response = Data(repeating: 7, count: 66 * 1024 * 1024)
        let transport = try SessionRuntimeTransport(
            generation: generation,
            storeURL: fixture.url,
            snapshot: { throw SessionRuntimeConnectionError.rejected("このテストでは利用しません。") },
            command: { _ in throw SessionRuntimeConnectionError.rejected("このテストでは利用しません。") },
            applicationCommand: { payload in
                #expect(payload.count == 25 * 1024 * 1024)
                return response
            }
        )
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let token = try SessionRuntimeCredentialStore.load(storeURL: fixture.url)
        let client = SessionRuntimeClient(endpoint: try SessionRuntimeEndpoint(url: url, generation: generation, token: token))
        let received = try await client.applicationCommand(Data(repeating: 3, count: 25 * 1024 * 1024))
        #expect(received == response)
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test func duplicateConcurrentCommandRunsOnce() async throws {
        let ledger = SessionRuntimeCommandLedger(generation: UUID())
        let request = SessionRuntimeOperation(generation: ledger.generation, payload: Data("first".utf8))
        let counter = RuntimeCommandCounter()
        async let first = ledger.perform(request) { await counter.increment() }
        async let second = ledger.perform(request) { await counter.increment() }
        let results = try await [first, second]
        #expect(results[0] == results[1])
        #expect(await counter.value == 1)
    }

    @Test func sameIdentifierWithDifferentCommandIsRejected() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation)
        let request = SessionRuntimeOperation(generation: generation, payload: Data([1]))
        _ = try await ledger.perform(request) { Data([4]) }
        let changed = SessionRuntimeOperation(id: request.id, generation: generation, issuedAt: request.issuedAt, payload: Data([2]))
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(changed) { Data([5]) }
        }
    }

    @Test func expiredOperationCannotExecuteAgainAfterCachePruning() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation)
        let now = Date()
        let request = SessionRuntimeOperation(generation: generation, issuedAt: now, payload: Data([1]))
        _ = try await ledger.perform(request, now: now) { Data([4]) }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(request, now: now.addingTimeInterval(121)) { Data([5]) }
        }
    }

    @Test func fullLedgerRejectsNewCommandWithoutEvictingLiveResult() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation, maximumOperations: 1)
        let request = SessionRuntimeOperation(generation: generation, payload: Data([1]))
        _ = try await ledger.perform(request) { Data([4]) }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, payload: Data([2]))) { Data([5]) }
        }
        let replay = try await ledger.perform(request) { Data([6]) }
        #expect(replay == Data([4]))
    }

    @Test func wrongGenerationNeverExecutes() async throws {
        let ledger = SessionRuntimeCommandLedger(generation: UUID())
        let counter = RuntimeCommandCounter()
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(SessionRuntimeOperation(generation: UUID(), payload: Data())) {
                await counter.increment()
            }
        }
        #expect(await counter.value == 0)
    }

    @Test func backwardsClockCannotReviveExpiredOperation() async throws {
        let generation = UUID()
        let ledger = SessionRuntimeCommandLedger(generation: generation)
        let start = Date()
        let first = SessionRuntimeOperation(generation: generation, issuedAt: start, payload: Data([1]))
        _ = try await ledger.perform(first, now: start) { Data([2]) }
        let later = start.addingTimeInterval(121)
        _ = try await ledger.perform(SessionRuntimeOperation(generation: generation, issuedAt: later, payload: Data([3])), now: later) { Data([4]) }
        await #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try await ledger.perform(first, now: start) { Data([5]) }
        }
    }

    @Test func desktopAuthenticationDoesNotAcceptChildCredential() {
        let authorization = SessionRuntimeAuthorization(token: "desktop-secret")
        #expect(authorization.accepts("Bearer desktop-secret"))
        #expect(!authorization.accepts("Bearer child-secret"))
        #expect(!authorization.accepts(nil))
        #expect(!authorization.accepts("desktop-secret"))
    }

    @Test func endpointRejectsNonLoopbackAndCredentialsInURL() {
        #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try SessionRuntimeEndpoint(url: URL(string: "http://localhost:8000")!, generation: UUID(), token: "secret")
        }
        #expect(throws: SessionRuntimeConnectionError.self) {
            _ = try SessionRuntimeEndpoint(url: URL(string: "http://user@127.0.0.1:8000")!, generation: UUID(), token: "secret")
        }
    }

    @Test @MainActor func liveHostWithoutDiscoveryNeverLaunchesDuplicate() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        var launches = 0
        let launcher = SessionRuntimeLauncher(runtimeBundleURL: fixture.url, storeURL: fixture.url, readinessTimeout: .milliseconds(1)) {
            launches += 1
            return getpid()
        }
        await #expect(throws: SessionRuntimeConnectionError.self) { _ = try await launcher.connect() }
        #expect(launches == 0)
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func readinessFailureDoesNotSpawnAgainOnNextConnectionAttempt() async throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        var launches = 0
        let launcher = SessionRuntimeLauncher(runtimeBundleURL: fixture.url, storeURL: fixture.url, readinessTimeout: .milliseconds(1)) {
            launches += 1
            return getpid()
        }
        await #expect(throws: SessionRuntimeConnectionError.self) { _ = try await launcher.connect() }
        let next = SessionRuntimeLauncher(runtimeBundleURL: fixture.url, storeURL: fixture.url, readinessTimeout: .milliseconds(1)) {
            launches += 1
            return getpid()
        }
        await #expect(throws: SessionRuntimeConnectionError.self) { _ = try await next.connect() }
        #expect(launches == 1)
    }

    @Test func credentialIsPrivateAndRejectsSymlink() throws {
        let fixture = try RuntimeTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let token = try SessionRuntimeCredentialStore.loadOrCreate(storeURL: fixture.url)
        #expect(token.count == 64)
        #expect(try SessionRuntimeCredentialStore.load(storeURL: fixture.url) == token)
        let tokenURL = lease.directoryURL.appendingPathComponent("master-token")
        let attributes = try FileManager.default.attributesOfItem(atPath: tokenURL.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try FileManager.default.removeItem(at: tokenURL)
        let target = fixture.url.appendingPathComponent("foreign-token")
        try Data(token.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: tokenURL, withDestinationURL: target)
        #expect(throws: (any Error).self) { _ = try SessionRuntimeCredentialStore.load(storeURL: fixture.url) }
    }
}

private actor RuntimeCommandCounter {
    var value = 0
    func increment() async -> Data {
        value += 1
        await Task.yield()
        return Data([UInt8(value)])
    }
}

private func runtimeHTTPCommand(_ operation: SessionRuntimeOperation, endpoint: SessionRuntimeEndpoint) async throws -> Data {
    var request = URLRequest(url: endpoint.url.appendingPathComponent("command"), timeoutInterval: 5)
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(operation)
    request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
    request.setValue(String(SessionRuntimeEndpoint.protocolVersion), forHTTPHeaderField: "X-Phlox-Runtime-Protocol")
    request.setValue(endpoint.generation.uuidString, forHTTPHeaderField: "X-Phlox-Runtime-Generation")
    let deadline = ContinuousClock.now + .seconds(5)
    while true {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode
        if status == 503, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)); continue }
        #expect(status == 200)
        return data
    }
}

private actor RuntimeKeyRecorder {
    var input = Data()
    func append(_ data: Data) -> Data { input.append(data); return Data() }
}

private actor RuntimeHeldCommands {
    nonisolated let entered = AsyncStream<Void>.makeStream()
    private var waiters: [CheckedContinuation<Data, Never>] = []
    private var released = false
    func wait() async -> Data {
        guard !released else { return Data() }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            entered.continuation.yield(())
        }
    }
    func release() {
        released = true
        for waiter in waiters { waiter.resume(returning: Data()) }
        waiters.removeAll()
    }
}

@MainActor private final class RuntimePendingTurn {
    let entered = AsyncStream<Void>.makeStream()
    var continuation: CheckedContinuation<Void, Never>?
    var starts = 0
    var snapshotsWhilePending = 0
    var completed = false
    var interruptedWhilePending = false
    func start() async {
        starts += 1
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.continuation.yield(())
        }
        completed = true
    }
    func interrupt() {
        interruptedWhilePending = !completed
        release()
    }
    func release() { continuation?.resume(); continuation = nil }
}

private struct RuntimeTransportFixture {
    let url: URL
    init() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        url = root.appendingPathComponent(".verification/runtime-desktop-transport/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("SessionRuntimeTransportTests専用。今回のテストで生成。終了時に削除。\n".utf8).write(to: url.appendingPathComponent("ownership.txt"))
    }
    func remove() {
        do { try FileManager.default.removeItem(at: url) }
        catch { Issue.record("専用fixtureの片付けに失敗しました。\(error)") }
    }
}
