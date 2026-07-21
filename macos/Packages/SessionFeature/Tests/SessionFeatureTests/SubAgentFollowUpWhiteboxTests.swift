import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private enum FollowUpTestError: Error {
    case turnStartFailed
}

private final class FailingTurnStartClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private let state = NSLock()
    private var _turnStartCount = 0

    var turnStartCount: Int {
        state.withLock { _turnStartCount }
    }

    init() {
        var captured: AsyncStream<NormalizedChatEvent>.Continuation?
        events = AsyncStream { captured = $0 }
        continuation = captured!
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        state.withLock { _turnStartCount += 1 }
        throw FollowUpTestError.turnStartFailed
    }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

@MainActor
private func makeViewModel(client: FailingTurnStartClient) -> ChatSessionViewModel {
    ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-subagent-followup-whitebox-test"
    )
}

private func subAgent() -> SubAgentRef {
    SubAgentRef(
        id: "toolu_whitebox",
        subagentType: "general-purpose",
        description: "白箱テスト用サブエージェント",
        status: .completed,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@Suite("Whitebox: サブエージェント・フォローアップ送信（task-3）")
struct SubAgentFollowUpWhiteboxTests {
    @Test @MainActor
    func composePromptIncludesSubAgentReferenceAndUserText() {
        let prompt = ChatSessionViewModel.composeSubAgentFollowUpPrompt(
            subAgent: subAgent(),
            userText: "続きをお願い"
        )
        #expect(prompt.contains("toolu_whitebox"))
        #expect(prompt.contains("白箱テスト用サブエージェント"))
        #expect(prompt.contains("続きをお願い"))
        #expect(prompt.contains("SendMessage"))
    }

    @Test @MainActor
    func turnStartFailureRevertsStatusToIdle() async {
        let client = FailingTurnStartClient()
        let vm = makeViewModel(client: client)

        await #expect(throws: FollowUpTestError.turnStartFailed) {
            try await vm.sendSubAgentFollowUp(subAgent: subAgent(), text: "失敗後 idle に戻る")
        }

        #expect(client.turnStartCount == 1)
        #expect(vm.status == .idle)
        let hasUserMessage = vm.transcript.contains { item in
            if case .userMessage(_, let text, _, _) = item {
                return text.contains("失敗後 idle に戻る")
            }
            return false
        }
        #expect(hasUserMessage)
    }
}
