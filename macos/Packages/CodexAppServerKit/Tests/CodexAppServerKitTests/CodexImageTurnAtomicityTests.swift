import Foundation
import Testing
import StructuredChatKit
@testable import CodexAppServerKit

@Test func imageTurnRejectsModelChangeUntilTurnStartReturns() async throws {
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
    var started = transport.turnStartRequests.makeAsyncIterator()
    _ = await started.next()

    await #expect(throws: CodexStructuredClientError.imageTurnInProgress) {
        try await adapter.updateThreadSettings(ThreadSettingsUpdateParams(
            threadId: "thread-image",
            model: "text-only-model"
        ))
    }
    #expect(await transport.sent.first { $0["method"]?.stringValue == "thread/settings/update" } == nil)

    await transport.releaseTurnStart()
    try await turnTask.value

    let turn = try #require(await transport.sent.first { $0["method"]?.stringValue == "turn/start" })
    guard case .array(let input) = turn["params"]?["input"] else {
        Issue.record("turn/start input が配列でない")
        await adapter.close()
        return
    }
    #expect(input.contains { $0["type"] == .string("localImage") })

    await adapter.close()
}

@Test func nativeImageTurnRejectsModelChangeUntilTurnStartReturns() async throws {
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
    var started = transport.turnStartRequests.makeAsyncIterator()
    _ = await started.next()

    await #expect(throws: CodexStructuredClientError.imageTurnInProgress) {
        try await adapter.updateThreadSettings(ThreadSettingsUpdateParams(
            threadId: "thread-image",
            model: "text-only-model"
        ))
    }
    #expect(await transport.sent.first { $0["method"]?.stringValue == "thread/settings/update" } == nil)

    await transport.releaseTurnStart()
    try await turnTask.value

    let turn = try #require(await transport.sent.first { $0["method"]?.stringValue == "turn/start" })
    guard case .array(let input) = turn["params"]?["input"] else {
        Issue.record("native turn/start input が配列でない")
        await adapter.close()
        return
    }
    #expect(input.contains { $0["type"] == .string("localImage") })

    await adapter.close()
}

@Test func modelChangeRejectsImageTurnsUntilSettingsUpdateReturns() async throws {
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
    var settingsStarted = transport.settingsUpdateRequests.makeAsyncIterator()
    _ = await settingsStarted.next()

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
    await adapter.close()
}

private actor ImageTurnBarrier {
    nonisolated let requests: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var releaseRequested = false

    init() {
        var captured: AsyncStream<Void>.Continuation?
        requests = AsyncStream(bufferingPolicy: .unbounded) { captured = $0 }
        continuation = captured!
    }

    func markRequest() {
        continuation.yield(())
    }

    func waitForRelease() async {
        if releaseRequested {
            releaseRequested = false
            return
        }
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func release() {
        if let releaseContinuation {
            releaseContinuation.resume()
            self.releaseContinuation = nil
        } else {
            releaseRequested = true
        }
    }
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
            await turnStartBarrier.waitForRelease()
        }
        if request["method"]?.stringValue == "thread/settings/update" {
            await settingsUpdateBarrier.markRequest()
            await settingsUpdateBarrier.waitForRelease()
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
        continuation.finish()
    }
}
