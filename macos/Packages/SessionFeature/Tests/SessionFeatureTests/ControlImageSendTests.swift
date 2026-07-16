import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private let tinyPNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

private final class RecordingStructuredClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var lastTurnStartInput: [ChatInput]?
    var turnStartError: (any Error)?

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        lastTurnStartInput = input
        if let turnStartError {
            throw turnStartError
        }
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

@MainActor
private func makeClaudeViewModel(client: RecordingStructuredClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@MainActor
private func makeCodexViewModel(client: RecordingStructuredClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.codex),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
}

@Suite @MainActor
struct ControlImageSendTests {
    @Test
    func sendTextWithControlImages_includesImageInTurnStartInput() async throws {
        let client = RecordingStructuredClient()
        let vm = makeClaudeViewModel(client: client)

        try await vm.sendTextWithControlImages(
            "この画面を見て",
            submit: true,
            images: [(mediaType: "image/png", data: tinyPNG)]
        )

        let input = try #require(client.lastTurnStartInput)
        #expect(input == [
            .text("この画面を見て"),
            .image(data: tinyPNG, mediaType: "image/png"),
        ])
        #expect(vm.attachmentStore.attachments.isEmpty)
    }

    @Test
    func sendTextWithControlImages_clearsImagesWhenTurnStartThrows() async throws {
        let client = RecordingStructuredClient()
        client.turnStartError = NSError(domain: "test", code: 1)
        let vm = makeClaudeViewModel(client: client)

        await #expect(throws: (any Error).self) {
            try await vm.sendTextWithControlImages(
                "retry me",
                submit: true,
                images: [(mediaType: "image/png", data: tinyPNG)]
            )
        }

        #expect(vm.attachmentStore.attachments.isEmpty)

        client.turnStartError = nil
        try await vm.sendTextWithControlImages(
            "second try",
            submit: true,
            images: [(mediaType: "image/png", data: tinyPNG)]
        )

        let input = try #require(client.lastTurnStartInput)
        #expect(input.contains(.image(data: tinyPNG, mediaType: "image/png")))
        #expect(input.contains(.text("second try")))
    }

    @Test
    func sendTextWithControlImages_unsupportedAgentThrowsWithoutStaging() async throws {
        let client = RecordingStructuredClient()
        let vm = makeCodexViewModel(client: client)

        await #expect(throws: ChatSessionViewModel.ControlImageSendError.imagesUnsupported) {
            try await vm.sendTextWithControlImages(
                "image please",
                submit: true,
                images: [(mediaType: "image/png", data: tinyPNG)]
            )
        }

        #expect(client.lastTurnStartInput == nil)
        #expect(vm.attachmentStore.attachments.isEmpty)
    }
}
