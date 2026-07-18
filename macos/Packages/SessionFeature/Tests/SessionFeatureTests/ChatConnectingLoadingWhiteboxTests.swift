import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private enum RestoreGateError: Error {
    case resumeFailed
}

private actor RestoreGate {
    private var entered = false
    private var enteredContinuation: CheckedContinuation<Void, Never>?
    private var resumeContinuation: CheckedContinuation<Void, any Error>?

    func suspendResume() async throws {
        try await withCheckedThrowingContinuation { continuation in
            resumeContinuation = continuation
            entered = true
            enteredContinuation?.resume()
            enteredContinuation = nil
        }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { continuation in
            enteredContinuation = continuation
        }
    }

    func succeed() {
        resumeContinuation?.resume()
        resumeContinuation = nil
    }

    func fail() {
        resumeContinuation?.resume(throwing: RestoreGateError.resumeFailed)
        resumeContinuation = nil
    }
}

private final class GatedRestoreClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    let gate = RestoreGate()

    init() {
        events = AsyncStream { continuation in
            continuation.finish()
        }
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {
        try await gate.suspendResume()
    }
    func interrupt() async throws {}
    func close() async {}
}

@MainActor
private func makeRestoreViewModel(client: GatedRestoreClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        transcriptStore: NoOpTranscriptStore()
    )
}

@Test @MainActor
func restoreState_isRestoringWhileResumeIsInFlight_thenRestoredOnSuccess() async {
    let client = GatedRestoreClient()
    let viewModel = makeRestoreViewModel(client: client)

    let restoreTask = Task { @MainActor in
        await viewModel.restore(
            threadId: "session-success",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
    }

    await client.gate.waitUntilEntered()
    #expect(viewModel.restoreState == .restoring)
    #expect(viewModel.shouldShowConnectingIndicator)

    await client.gate.succeed()
    await restoreTask.value

    #expect(viewModel.restoreState == .restored)
    #expect(!viewModel.shouldShowConnectingIndicator)
}

@Test @MainActor
func restoreState_isRestoringWhileResumeIsInFlight_thenFailedOnError() async {
    let client = GatedRestoreClient()
    let viewModel = makeRestoreViewModel(client: client)

    let restoreTask = Task { @MainActor in
        await viewModel.restore(
            threadId: "session-failure",
            approvalPolicy: .named("on-request"),
            sandbox: .named("workspace-write")
        )
    }

    await client.gate.waitUntilEntered()
    #expect(viewModel.restoreState == .restoring)
    #expect(viewModel.shouldShowConnectingIndicator)

    await client.gate.fail()
    await restoreTask.value

    #expect(viewModel.restoreState == .failed(message: "resumeFailed"))
    #expect(!viewModel.shouldShowConnectingIndicator)
}

@Test
func connectingIndicatorVisibility_requiresRestoringAndEmptyTranscript() {
    #expect(!ChatSessionViewModel.shouldShowConnectingIndicator(
        restoreState: .notRestored,
        transcriptIsEmpty: true
    ))
    #expect(ChatSessionViewModel.shouldShowConnectingIndicator(
        restoreState: .restoring,
        transcriptIsEmpty: true
    ))
    #expect(!ChatSessionViewModel.shouldShowConnectingIndicator(
        restoreState: .restoring,
        transcriptIsEmpty: false
    ))
    #expect(!ChatSessionViewModel.shouldShowConnectingIndicator(
        restoreState: .restored,
        transcriptIsEmpty: true
    ))
    #expect(!ChatSessionViewModel.shouldShowConnectingIndicator(
        restoreState: .failed(message: "failure"),
        transcriptIsEmpty: true
    ))
}
