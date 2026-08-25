import Foundation
import StructuredChatKit
import Testing
@testable import CodexAppServerKit

@Test(.timeLimit(.minutes(1)))
func imagePathsSurviveTurnCompletedUntilClose() async throws {
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
    #expect(FileManager.default.fileExists(atPath: imagePath))

    await adapter.close()
    #expect(await waitUntil { !FileManager.default.fileExists(atPath: imagePath) })
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
func imagePathsSurviveOldThreadTerminalEventAfterResetUntilClose() async throws {
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
    #expect(FileManager.default.fileExists(atPath: imagePath))

    await adapter.close()
    #expect(await waitUntil { !FileManager.default.fileExists(atPath: imagePath) })
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

@Test(.timeLimit(.minutes(1)))
func imagePathsFromMultipleTurnsSurviveUntilClose() async throws {
    let transport = RespondingTransport()
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    try await adapter.turnStart([
        .text("first"),
        .image(data: Data([1]), mediaType: "image/png"),
    ])
    try await adapter.turnStart([
        .text("second"),
        .image(data: Data([2]), mediaType: "image/png"),
    ])

    let imagePaths = extractLocalImagePaths(from: await transport.sent.all())
    #expect(imagePaths.count == 2)
    for path in imagePaths {
        #expect(FileManager.default.fileExists(atPath: path))
    }

    await adapter.close()
    for path in imagePaths {
        #expect(await waitUntil { !FileManager.default.fileExists(atPath: path) })
    }
    await transport.close()
}

@Test(.timeLimit(.minutes(1)))
func imagePathsFromFailedTurnStartAreDeletedWhileSuccessfulTurnPathsRemain() async throws {
    let transport = RespondingTransport(failTurnStartOnAttempt: 2)
    let adapter = CodexStructuredAgentClient(
        client: CodexAppServerClient(transport: transport)
    )
    await adapter.start()
    _ = try await adapter.threadStart(ThreadStartParams(cwd: "/tmp/work"))
    await adapter.setNativeImageInputEnabled(true)

    try await adapter.turnStart([
        .text("first"),
        .image(data: Data([1]), mediaType: "image/png"),
    ])
    let successfulPath = try #require(extractLocalImagePath(from: await transport.sent.all()))
    #expect(FileManager.default.fileExists(atPath: successfulPath))

    await #expect(throws: (any Error).self) {
        try await adapter.turnStart([
            .text("second"),
            .image(data: Data([2]), mediaType: "image/png"),
        ])
    }

    let imagePaths = extractLocalImagePaths(from: await transport.sent.all())
    #expect(imagePaths.count == 2)
    let failedPath = try #require(imagePaths.last)
    #expect(failedPath != successfulPath)
    #expect(FileManager.default.fileExists(atPath: successfulPath))
    #expect(await waitUntil { !FileManager.default.fileExists(atPath: failedPath) })

    await adapter.close()
    #expect(await waitUntil { !FileManager.default.fileExists(atPath: successfulPath) })
    await transport.close()
}

private func extractLocalImagePath(from messages: [JSONValue]) throws -> String? {
    extractLocalImagePaths(from: messages).first
}

private func extractLocalImagePaths(from messages: [JSONValue]) -> [String] {
    var paths: [String] = []
    for message in messages {
        guard message["method"]?.stringValue == "turn/start",
              case .array(let inputs) = message["params"]?["input"] else {
            continue
        }
        for input in inputs {
            guard input["type"] == .string("localImage"),
                  case .string(let path) = input["path"] else { continue }
            paths.append(path)
        }
    }
    return paths
}
