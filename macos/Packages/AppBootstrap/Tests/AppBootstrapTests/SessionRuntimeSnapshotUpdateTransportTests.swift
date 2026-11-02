import AgentDomain
import DashboardFeature
import Foundation
import SessionFeature
import Testing
@testable import AppBootstrap

@Suite struct SessionRuntimeSnapshotUpdateTransportTests {
    @Test @MainActor func delayedAndCancelledUpdatesKeepTheRequestBaseline() async throws {
        let fixture = try SnapshotUpdateTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        let id = SessionID()
        let executionID = UUID()
        var captures = 0
        var commands = 0
        let transport = try SessionRuntimeTransport(generation: generation, storeURL: fixture.url,
            snapshot: {
                captures += 1
                var chat = SessionRuntimeChatSnapshot(id: id, startedAt: .distantPast, agentRef: .builtin(.codex), workingDirectory: nil)
                chat.executionID = executionID
                chat.transcript = [.agentMessage(id: "output", text: String(captures), timestamp: .distantPast)]
                chat.transcriptRevision = captures
                return .init(projects: [], sessions: [.chat(chat)], availableAgentKinds: [.codex])
            }, command: { _ in commands += 1; return .none })
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation,
            token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let gate = SnapshotUpdateDecodeGate()
        defer { gate.release() }
        let watchdog = Task.detached {
            try await Task.sleep(for: .seconds(5))
            gate.release()
        }
        defer { watchdog.cancel() }
        let client = SessionRuntimeClient(endpoint: endpoint,
            snapshotDecoder: { try JSONDecoder().decode(SessionRuntimeSnapshotEnvelope.self, from: $0) },
            snapshotUpdateDecoder: gate.decode)
        try await client.handshake()
        _ = try await client.snapshot()
        var events = gate.started.stream.makeAsyncIterator()
        #expect(await events.next() == 1)
        let delayed = Task { try await client.snapshot() }
        #expect(await events.next() == 2)
        #expect(try output(await client.snapshot()) == "3")
        #expect(await events.next() == 3)
        _ = try await client.command(.session(id, executionID, .interrupt))
        #expect(commands == 1)
        gate.second.signal()
        #expect(try output(await delayed.value) == "4")
        #expect(await events.next() == 4)
        let cancelled = Task { try await client.snapshot() }
        #expect(await events.next() == 5)
        cancelled.cancel()
        gate.fifth.signal()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        #expect(try output(await client.snapshot()) == "6")

        let legacy = SessionRuntimeHandshake(protocolVersion: 1, generation: generation)
        try client.acceptHandshake(legacy)
        #expect(try output(await client.snapshot()) == "7")
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    @Test @MainActor func independentClientsRecoverAfterServerBaseEviction() async throws {
        let fixture = try SnapshotUpdateTransportFixture()
        defer { fixture.remove() }
        let lease = try SessionRuntimeLease(storeURL: fixture.url)
        let generation = UUID()
        var count = 0
        let id = SessionID()
        let executionID = UUID()
        let transport = try SessionRuntimeTransport(generation: generation, storeURL: fixture.url,
            snapshot: {
                count += 1
                var chat = SessionRuntimeChatSnapshot(id: id, startedAt: .distantPast, agentRef: .builtin(.codex), workingDirectory: nil)
                chat.executionID = executionID
                chat.transcript = [.agentMessage(id: "output", text: String(count), timestamp: .distantPast)]
                return .init(projects: [], sessions: [.chat(chat)], availableAgentKinds: [.codex])
            }, command: { _ in .none })
        let url = try await transport.start()
        defer { Task { await transport.stop() } }
        let endpoint = try SessionRuntimeEndpoint(url: url, generation: generation,
            token: SessionRuntimeCredentialStore.load(storeURL: fixture.url))
        let first = SessionRuntimeClient(endpoint: endpoint)
        let second = SessionRuntimeClient(endpoint: endpoint)
        try await first.handshake()
        try await second.handshake()
        #expect(try output(await first.snapshot()) == "1")
        #expect(try output(await second.snapshot()) == "2")
        #expect(try output(await second.snapshot()) == "3")
        #expect(try output(await first.snapshot()) == "4")
        await transport.stop()
        withExtendedLifetime(lease) {}
    }

    private func output(_ snapshot: DashboardRuntimeSnapshot) throws -> String {
        let entry = try #require(snapshot.sessions.first)
        guard case .chat(let chat) = entry,
              case .agentMessage(_, let text, _)? = chat.transcript.first else {
            throw SessionRuntimeConnectionError.invalidEndpoint
        }
        return text
    }
}

private final class SnapshotUpdateDecodeGate: @unchecked Sendable {
    let started = AsyncStream<Int>.makeStream()
    let second = DispatchSemaphore(value: 0)
    let fifth = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var calls = 0

    func decode(_ data: Data) throws -> SessionRuntimeSnapshotUpdate {
        let call = lock.withLock { calls += 1; return calls }
        started.continuation.yield(call)
        if call == 2 { second.wait() }
        if call == 5 { fifth.wait() }
        return try JSONDecoder().decode(SessionRuntimeSnapshotUpdate.self, from: data)
    }

    func release() {
        second.signal()
        fifth.signal()
        started.continuation.finish()
    }
}

private struct SnapshotUpdateTransportFixture {
    let url: URL

    init() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { root.deleteLastPathComponent() }
        url = root.appendingPathComponent(".verification/runtime-snapshot-update/\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("SessionRuntimeSnapshotUpdateTransportTests専用。PID \(ProcessInfo.processInfo.processIdentifier)\n".utf8)
            .write(to: url.appendingPathComponent("ownership.txt"))
    }

    func remove() {
        do { try FileManager.default.removeItem(at: url) }
        catch { Issue.record("差分検証fixtureの削除に失敗しました。\(error)") }
    }
}
