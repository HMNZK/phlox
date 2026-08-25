import Foundation
import StructuredChatKit
import Testing
@testable import CodexAppServerKit

@Test(.timeLimit(.minutes(1)))
func imagePathsSurviveTurnStartResponseUntilTurnCompletes() async throws {
    let transport = RespondingTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    var threadIterator = adapter.threadEvents.makeAsyncIterator()

    try await adapter.turnStart([
        .text("describe"),
        .image(data: Data([1, 2, 3]), mediaType: "image/png"),
    ])

    let imagePath = try #require(extractLocalImagePath(from: await transport.sent.all()))
    #expect(FileManager.default.fileExists(atPath: imagePath))

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-image-1","status":"inProgress","items":[]}}}
    """)
    guard case .turnStarted? = await threadIterator.next() else {
        Issue.record("turn/started が threadEvents に届かなかった")
        await adapter.close()
        await transport.close()
        return
    }
    #expect(FileManager.default.fileExists(atPath: imagePath))

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-image-1","status":"completed","items":[]}}}
    """)
    guard case .turnCompleted? = await threadIterator.next() else {
        Issue.record("turn/completed が threadEvents に届かなかった")
        await adapter.close()
        await transport.close()
        return
    }
    #expect(await waitUntil { !FileManager.default.fileExists(atPath: imagePath) })

    await adapter.close()
    await transport.close()
}

@Test(.timeLimit(.minutes(1)))
func imagePathsDeletedOnTurnStartFailure() async throws {
    let transport = RespondingTransport(failTurnStart: true)
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    await #expect(throws: (any Error).self) {
        try await adapter.turnStart([
            .text("describe"),
            .image(data: Data([1, 2, 3]), mediaType: "image/png"),
        ])
    }

    let imagePath = try #require(extractLocalImagePath(from: await transport.sent.all()))
    #expect(await waitUntil { !FileManager.default.fileExists(atPath: imagePath) })

    await adapter.close()
    await transport.close()
}

@Test(.timeLimit(.minutes(1)))
func imagePathsDeletedWhenOldThreadTerminalEventArrivesAfterReset() async throws {
    let transport = RespondingTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    var threadIterator = adapter.threadEvents.makeAsyncIterator()

    try await adapter.turnStart([
        .text("describe"),
        .image(data: Data([1, 2, 3]), mediaType: "image/png"),
    ])

    let imagePath = try #require(extractLocalImagePath(from: await transport.sent.all()))
    #expect(FileManager.default.fileExists(atPath: imagePath))

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"thread-1","turn":{"id":"turn-image-1","status":"inProgress","items":[]}}}
    """)
    guard case .turnStarted? = await threadIterator.next() else {
        Issue.record("turn/started が threadEvents に届かなかった")
        await adapter.close()
        await transport.close()
        return
    }
    #expect(FileManager.default.fileExists(atPath: imagePath))

    await adapter.resetConversation()

    transport.receive("""
    {"jsonrpc":"2.0","method":"turn/completed","params":{"threadId":"thread-1","turn":{"id":"turn-image-1","status":"completed","items":[]}}}
    """)

    // 旧 thread の terminal は UI ストリームから遮断されるため、ファイル削除はポーリングで確認する。
    #expect(await waitUntil {
        for _ in 0..<200 {
            if !FileManager.default.fileExists(atPath: imagePath) { return true }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return false
    })

    await adapter.close()
    await transport.close()
}

@Test(.timeLimit(.minutes(1)))
func imagePathsDeletedOnCloseBeforeTurnCompletes() async throws {
    let transport = RespondingTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    try await adapter.turnStart([
        .text("describe"),
        .image(data: Data([1, 2, 3]), mediaType: "image/png"),
    ])

    let imagePath = try #require(extractLocalImagePath(from: await transport.sent.all()))
    #expect(FileManager.default.fileExists(atPath: imagePath))

    await adapter.close()
    #expect(await waitUntil { !FileManager.default.fileExists(atPath: imagePath) })

    await transport.close()
}

private func extractLocalImagePath(from messages: [JSONValue]) throws -> String? {
    guard let request = messages.first(where: { $0["method"]?.stringValue == "turn/start" }),
          case .array(let inputs) = request["params"]?["input"] else {
        return nil
    }
    for input in inputs {
        guard input["type"] == .string("localImage"),
              case .string(let path) = input["path"] else { continue }
        return path
    }
    return nil
}
