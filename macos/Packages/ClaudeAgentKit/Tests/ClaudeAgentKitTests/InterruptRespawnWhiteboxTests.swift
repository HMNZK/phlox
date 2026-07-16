import Foundation
import StructuredChatKit
import Testing
@testable import ClaudeAgentKit

@Test func turnStartRespawnsWithResumeAfterInterruptEndsTransportStream() async throws {
    let recorder = InterruptRespawnRecorder()
    let sessionID = "a1a1a1a1-1111-4111-8111-111111111111"
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": sessionID],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var events = client.events.makeAsyncIterator()

    try await client.turnStart([.text("establish conversation")])
    #expect(await events.next() == .turnStarted)
    recorder.transports[0].receive(
        #"{"type":"result","subtype":"success","session_id":"\#(sessionID)","is_error":false}"#
    )
    #expect(await events.next() == .turnCompleted(nativeSessionId: sessionID))

    try await client.turnStart([.text("interrupted turn")])
    #expect(await events.next() == .turnStarted)
    try await client.interrupt()
    #expect(await events.next() == .turnInterrupted(nativeSessionId: sessionID))

    try await waitUntilInterruptRespawn {
        await client.transport == nil
    }
    #expect(recorder.transports[0].didInterrupt)

    await client.updateSettings(model: "sonnet", permissionMode: nil)
    try await client.turnStart([.text("turn after interrupt")])
    #expect(await events.next() == .turnStarted)
    #expect(recorder.starts.count == 2)
    #expect(recorder.starts[1].contains("--resume"))
    #expect(recorder.starts[1].contains(sessionID))
    #expect(!recorder.starts[1].contains("--session-id"))
    #expect(recorder.starts[1].contains("sonnet"))
    #expect(recorder.transports[1].sentStrings().count == 1)
    #expect(recorder.transports[1].sentStrings()[0].contains("turn after interrupt"))

    await client.close()
}

@Test func failedInterruptRespawnEmitsErrorAndThrowsNotStarted() async throws {
    let recorder = InterruptRespawnRecorder(failSecondStart: true)
    let client = ClaudeChatClient(
        environment: ["PHLOX_SESSION_ID": "b2b2b2b2-2222-4222-8222-222222222222"],
        transportFactory: recorder.makeTransport
    )
    await client.start()
    var events = client.events.makeAsyncIterator()

    try await client.turnStart([.text("interrupted turn")])
    #expect(await events.next() == .turnStarted)
    try await client.interrupt()
    #expect(await events.next() == .turnInterrupted(nativeSessionId: "b2b2b2b2-2222-4222-8222-222222222222"))
    try await waitUntilInterruptRespawn {
        await client.transport == nil
    }

    await #expect(throws: ClaudeChatClientError.notStarted) {
        try await client.turnStart([.text("turn after failed respawn")])
    }
    let errorEvent = await events.next()
    if case .error(let message) = errorEvent {
        #expect(message.contains("Failed to restart Claude transport"))
        #expect(message.contains("failedToStart"))
    } else {
        Issue.record("Expected failed respawn error event, got \(String(describing: errorEvent))")
    }

    await client.close()
}

private enum InterruptRespawnTestError: Error {
    case failedToStart
}

private final class InterruptRespawnRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let failSecondStart: Bool
    private var recordedStarts: [[String]] = []
    private var recordedTransports: [InterruptFinishingTransport] = []

    init(failSecondStart: Bool = false) {
        self.failSecondStart = failSecondStart
    }

    var starts: [[String]] {
        lock.withLock { recordedStarts }
    }

    var transports: [InterruptFinishingTransport] {
        lock.withLock { recordedTransports }
    }

    func makeTransport(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL?
    ) -> any LineDelimitedTransport {
        let shouldFailStart = lock.withLock {
            failSecondStart && recordedTransports.count == 1
        }
        let transport = InterruptFinishingTransport(shouldFailStart: shouldFailStart)
        lock.withLock {
            recordedStarts.append(arguments)
            recordedTransports.append(transport)
        }
        return transport
    }
}

private final class InterruptFinishingTransport: LineDelimitedTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: AsyncStream<Data>.Continuation?
    private var sent: [Data] = []
    private var interrupted = false
    private let shouldFailStart: Bool

    let receivedLines: AsyncStream<Data>

    init(shouldFailStart: Bool = false) {
        self.shouldFailStart = shouldFailStart
        var capturedContinuation: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { continuation in
            capturedContinuation = continuation
        }
        continuation = capturedContinuation
    }

    var didInterrupt: Bool {
        lock.withLock { interrupted }
    }

    func start() throws {
        if shouldFailStart {
            throw InterruptRespawnTestError.failedToStart
        }
    }

    func send(_ data: Data) async throws {
        lock.withLock {
            sent.append(data)
        }
    }

    func interrupt() async {
        lock.withLock {
            interrupted = true
        }
        continuation?.finish()
    }

    func close() async {
        continuation?.finish()
    }

    func stderrTail() async -> String? {
        nil
    }

    func receive(_ line: String) {
        continuation?.yield(Data(line.utf8))
    }

    func sentStrings() -> [String] {
        lock.withLock {
            sent.map { String(data: $0, encoding: .utf8) ?? "" }
        }
    }
}

private func waitUntilInterruptRespawn(
    timeout: Duration = .seconds(5),
    _ condition: @escaping @Sendable () async -> Bool
) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while clock.now < deadline {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(await condition(), "waitUntilInterruptRespawn timed out")
}
