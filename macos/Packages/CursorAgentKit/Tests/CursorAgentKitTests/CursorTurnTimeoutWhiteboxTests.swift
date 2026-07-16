import Foundation
import StructuredChatKit
import Testing
@testable import CursorAgentKit

private struct CursorTimeoutProbeError: LocalizedError {
    var errorDescription: String? {
        "process timed out after 300 seconds"
    }
}

private func timeoutEventsDuringTurn(
    client: CursorChatClient,
    input: [ChatInput]
) async throws -> [NormalizedChatEvent] {
    try await client.turnStart(input)
    var events: [NormalizedChatEvent] = []
    for await event in client.events {
        events.append(event)
        if case .turnCompleted = event {
            break
        }
        if case .error = event {
            break
        }
    }
    return events
}

@Test func cursorChatClientSurfacesRunnerTimeoutFailureAsErrorEvent() async throws {
    let runner = MockOneShotProcessRunner()
    runner.enqueueFailure(CursorTimeoutProbeError())

    let client = CursorChatClient(command: "cursor-agent", runner: runner)
    await client.start()
    let events = try await timeoutEventsDuringTurn(client: client, input: [.text("hang")])

    #expect(events.contains(.turnStarted))
    #expect(events.contains(.error(message: "cursor-agent failed: process timed out after 300 seconds")))

    await client.close()
}
