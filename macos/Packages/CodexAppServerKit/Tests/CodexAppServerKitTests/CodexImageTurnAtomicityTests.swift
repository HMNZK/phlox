import Foundation
import Testing
import StructuredChatKit
@testable import CodexAppServerKit

@Test(.timeLimit(.minutes(1)))
func imageTurnRejectsModelChangeUntilTurnStartReturns() async throws {
    let transport = ImageTurnBarrierTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    let turnTask = Task {
        try await adapter.turnStart([
            .text("describe"),
            .image(data: Data([1, 2, 3]), mediaType: "image/png"),
        ])
    }
    func cleanup() async {
        await transport.close()
        turnTask.cancel()
        _ = await turnTask.result
        await adapter.close()
    }

    do {
        let requestSent = await waitUntil(events: transport.sent.changes) {
            await transport.sent.first { $0["method"]?.stringValue == "turn/start" } != nil
        }
        guard requestSent else {
            Issue.record("turn/start request が timeout した")
            await cleanup()
            return
        }

        await #expect(throws: CodexStructuredClientError.imageTurnInProgress) {
            try await adapter.updateThreadSettings(ThreadSettingsUpdateParams(
                threadId: "thread-image",
                model: "text-only-model"
            ))
        }
        #expect(await transport.sent.first { $0["method"]?.stringValue == "thread/settings/update" } == nil)

        await transport.releaseTurnStart()
        try await turnTask.value

        guard let turn = await transport.sent.first(where: { $0["method"]?.stringValue == "turn/start" }) else {
            Issue.record("turn/start request がない")
            await cleanup()
            return
        }
        guard case .array(let input) = turn["params"]?["input"] else {
            Issue.record("turn/start input が配列でない")
            await cleanup()
            return
        }
        #expect(input.contains { $0["type"] == .string("localImage") })
    } catch {
        await cleanup()
        throw error
    }

    await cleanup()
}

@Test(.timeLimit(.minutes(1)))
func nativeImageTurnRejectsModelChangeUntilTurnStartReturns() async throws {
    let transport = ImageTurnBarrierTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    let turnTask = Task {
        try await adapter.turnStartNative([
            .text("describe"),
            .localImage(path: "/tmp/image.png", detail: "high"),
        ])
    }
    func cleanup() async {
        await transport.close()
        turnTask.cancel()
        _ = await turnTask.result
        await adapter.close()
    }

    do {
        let requestSent = await waitUntil(events: transport.sent.changes) {
            await transport.sent.first { $0["method"]?.stringValue == "turn/start" } != nil
        }
        guard requestSent else {
            Issue.record("native turn/start request が timeout した")
            await cleanup()
            return
        }

        await #expect(throws: CodexStructuredClientError.imageTurnInProgress) {
            try await adapter.updateThreadSettings(ThreadSettingsUpdateParams(
                threadId: "thread-image",
                model: "text-only-model"
            ))
        }
        #expect(await transport.sent.first { $0["method"]?.stringValue == "thread/settings/update" } == nil)

        await transport.releaseTurnStart()
        try await turnTask.value

        guard let turn = await transport.sent.first(where: { $0["method"]?.stringValue == "turn/start" }) else {
            Issue.record("native turn/start request がない")
            await cleanup()
            return
        }
        guard case .array(let input) = turn["params"]?["input"] else {
            Issue.record("native turn/start input が配列でない")
            await cleanup()
            return
        }
        #expect(input.contains { $0["type"] == .string("localImage") })
    } catch {
        await cleanup()
        throw error
    }

    await cleanup()
}

@Test(.timeLimit(.minutes(1)))
func modelChangeRejectsImageTurnsUntilSettingsUpdateReturns() async throws {
    let transport = ImageTurnBarrierTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    let settingsTask = Task {
        try await adapter.updateThreadSettings(ThreadSettingsUpdateParams(
            threadId: "thread-image",
            model: "text-only-model"
        ))
    }
    func cleanup() async {
        await transport.close()
        settingsTask.cancel()
        _ = await settingsTask.result
        await adapter.close()
    }

    do {
        let requestSent = await waitUntil(events: transport.sent.changes) {
            await transport.sent.first { $0["method"]?.stringValue == "thread/settings/update" } != nil
        }
        guard requestSent else {
            Issue.record("thread/settings/update request が timeout した")
            await cleanup()
            return
        }

        await #expect(throws: CodexStructuredClientError.imageTurnInProgress) {
            try await adapter.turnStart([
                .text("describe"),
                .image(data: Data([1, 2, 3]), mediaType: "image/png"),
            ])
        }
        await #expect(throws: CodexStructuredClientError.imageTurnInProgress) {
            try await adapter.turnStartNative([
                .text("describe"),
                .localImage(path: "/tmp/image.png", detail: nil),
            ])
        }
        #expect(await transport.sent.first { $0["method"]?.stringValue == "turn/start" } == nil)

        await transport.releaseSettingsUpdate()
        _ = try await settingsTask.value
    } catch {
        await cleanup()
        throw error
    }

    await cleanup()
}

private actor ImageTurnBarrier {
    nonisolated let requests: AsyncStream<Void>
    private let requestContinuation: AsyncStream<Void>.Continuation
    private nonisolated let releases: AsyncStream<Void>
    private let releaseContinuation: AsyncStream<Void>.Continuation

    init() {
        var requestContinuation: AsyncStream<Void>.Continuation?
        requests = AsyncStream(bufferingPolicy: .unbounded) { requestContinuation = $0 }
        self.requestContinuation = requestContinuation!

        var releaseContinuation: AsyncStream<Void>.Continuation?
        releases = AsyncStream(bufferingPolicy: .unbounded) { releaseContinuation = $0 }
        self.releaseContinuation = releaseContinuation!
    }

    func markRequest() {
        requestContinuation.yield(())
    }

    func waitForRelease(timeout: Duration = .seconds(2)) async throws {
        let releases = releases
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var iterator = releases.makeAsyncIterator()
                guard await iterator.next() != nil else {
                    throw ImageTurnBarrierError.closed
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                throw ImageTurnBarrierError.timedOut
            }
            do {
                guard try await group.next() != nil else {
                    throw ImageTurnBarrierError.closed
                }
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    func release() {
        releaseContinuation.yield(())
    }

    func close() {
        requestContinuation.finish()
        releaseContinuation.finish()
    }
}

private enum ImageTurnBarrierError: Error {
    case closed
    case timedOut
}

private final class ImageTurnBarrierTransport: AppServerTransport, @unchecked Sendable {
    let sent = SentMessages()
    let receivedLines: AsyncStream<Data>
    let turnStartRequests: AsyncStream<Void>
    let settingsUpdateRequests: AsyncStream<Void>
    private let continuation: AsyncStream<Data>.Continuation
    private let turnStartBarrier = ImageTurnBarrier()
    private let settingsUpdateBarrier = ImageTurnBarrier()

    init() {
        var received: AsyncStream<Data>.Continuation?
        receivedLines = AsyncStream { received = $0 }
        continuation = received!
        turnStartRequests = turnStartBarrier.requests
        settingsUpdateRequests = settingsUpdateBarrier.requests
    }

    func send(_ data: Data) async throws {
        try await sent.append(data)
        let request = try JSONDecoder.appServer.decode(JSONValue.self, from: data)
        guard let id = request["id"] else { return }
        if request["method"]?.stringValue == "turn/start" {
            await turnStartBarrier.markRequest()
            try await turnStartBarrier.waitForRelease()
        }
        if request["method"]?.stringValue == "thread/settings/update" {
            await settingsUpdateBarrier.markRequest()
            try await settingsUpdateBarrier.waitForRelease()
        }

        let result: JSONValue
        if request["method"]?.stringValue == "thread/start" {
            result = .object([
                "thread": .object([
                    "id": .string("thread-image"),
                    "status": .object(["type": .string("idle")]),
                ]),
            ])
        } else {
            result = .object([:])
        }
        let response = JSONValue.object([
            "jsonrpc": .string("2.0"),
            "id": id,
            "result": result,
        ])
        continuation.yield(try JSONEncoder.appServer.encode(response))
    }

    func releaseTurnStart() async {
        await turnStartBarrier.release()
    }

    func releaseSettingsUpdate() async {
        await settingsUpdateBarrier.release()
    }

    func close() async {
        await turnStartBarrier.close()
        await settingsUpdateBarrier.close()
        continuation.finish()
    }
}
