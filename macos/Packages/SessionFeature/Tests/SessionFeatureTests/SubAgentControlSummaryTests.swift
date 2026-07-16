import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class SummaryFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

@MainActor
private func waitUntil(
    timeoutNanoseconds: UInt64 = 2_000_000_000,
    pollIntervalNanoseconds: UInt64 = 10_000_000,
    _ condition: @escaping () -> Bool
) async throws {
    var elapsed: UInt64 = 0
    while !condition() {
        guard elapsed < timeoutNanoseconds else {
            Issue.record("Timed out waiting for condition")
            return
        }
        try await Task.sleep(nanoseconds: pollIntervalNanoseconds)
        elapsed += pollIntervalNanoseconds
    }
}

@MainActor
private func makeChatVM() -> (ChatSessionViewModel, SummaryFakeClient) {
    let client = SummaryFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-subagent-summary-test"
    )
    return (vm, client)
}

@Suite @MainActor
struct SubAgentControlSummaryTests {
    private static let toolUseId = "toolu_summary_whitebox"

    @Test
    func subAgentControlSummariesMapsMessageCountFromTranscript() async throws {
        let (vm, client) = makeChatVM()
        client.yield(.subAgentStarted(
            toolUseId: Self.toolUseId,
            subagentType: "explore-map",
            description: "map workspace"
        ))
        client.yield(.subAgentActivity(
            toolUseId: Self.toolUseId,
            kind: .message,
            itemId: "m1",
            text: "line one"
        ))
        client.yield(.subAgentActivity(
            toolUseId: Self.toolUseId,
            kind: .message,
            itemId: "m2",
            text: "line two"
        ))

        try await waitUntil {
            vm.subAgentControlSummaries().first?.messageCount == 2
        }

        let summary = try #require(vm.subAgentControlSummaries().first)
        #expect(summary.id == Self.toolUseId)
        #expect(summary.name == "explore-map")
        #expect(summary.status == .running)
        #expect(summary.messageCount == 2)
    }

    @Test
    func subAgentControlSummariesMapsMarkerMessageIdFromMainTranscript() async throws {
        let (vm, client) = makeChatVM()
        client.yield(.subAgentStarted(
            toolUseId: Self.toolUseId,
            subagentType: "general-purpose",
            description: "probe"
        ))
        client.yield(.subAgentCompleted(
            toolUseId: Self.toolUseId,
            status: "completed",
            summary: "done",
            outputFile: nil
        ))

        try await waitUntil {
            vm.subAgentControlSummaries().contains { $0.markerMessageId == Self.toolUseId }
        }

        let summary = try #require(vm.subAgentControlSummaries().first { $0.id == Self.toolUseId })
        #expect(summary.markerMessageId == Self.toolUseId)
        let markers = vm.transcript.filter {
            if case .subAgentMarker(let id, _, _, _) = $0 { return id == Self.toolUseId }
            return false
        }
        #expect(markers.count == 1)
        #expect(markers[0].id == summary.markerMessageId)
    }

    @Test
    func subAgentControlSummariesReportsZeroMessageCountBeforeActivity() async throws {
        let (vm, client) = makeChatVM()
        client.yield(.subAgentStarted(
            toolUseId: Self.toolUseId,
            subagentType: "explore-map",
            description: "idle subagent"
        ))

        try await waitUntil { !vm.subAgentControlSummaries().isEmpty }

        let summary = try #require(vm.subAgentControlSummaries().first)
        #expect(summary.messageCount == 0)
        #expect(summary.markerMessageId == Self.toolUseId)
    }
}
