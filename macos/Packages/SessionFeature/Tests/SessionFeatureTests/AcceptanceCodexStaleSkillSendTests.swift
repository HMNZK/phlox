import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
@testable import SessionFeature

@Suite("Acceptance: Codex stale skill send")
@MainActor
struct AcceptanceCodexStaleSkillSendTests {
    @Test("stale な選択の送信は no-op にならず、下書きと明示エラーを残す")
    func staleSelectionSendReportsReselectionError() async throws {
        let client = StaleSkillSendClient()
        let viewModel = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/workspace/project"
        )
        do {
            let state = try #require(viewModel.codexSkillSelectionState)
            await state.refresh()
            let skill = try #require(state.skills.first)
            #expect(state.select(skill))

            viewModel.draft = "$review 本文"
            let input = try #require(viewModel.consumeDraftForSend())
            state.invalidate()

            try await viewModel.sendText(input, submit: true)

            #expect(viewModel.draft == "$review 本文")
            #expect(viewModel.transcript.contains { item in
                guard case .error(_, let message, _) = item else { return false }
                return message.contains("再選択")
            })
            #expect(await client.sentInputs.isEmpty)
        } catch {
            await viewModel.terminate()
            throw error
        }
        await viewModel.terminate()
    }
}

private final class StaleSkillSendClient: StructuredAgentClient, CodexSkillSelectionClient, @unchecked Sendable {
    let events = AsyncStream<NormalizedChatEvent> { continuation in
        continuation.finish()
    }
    let skillEvents = AsyncStream<ThreadEvent> { continuation in
        continuation.finish()
    }

    private actor Recorder {
        private(set) var sentInputs: [[ChatInput]] = []

        func record(_ input: [ChatInput]) {
            sentInputs.append(input)
        }
    }

    private let recorder = Recorder()

    func start() async {}

    func turnStart(_ input: [ChatInput]) async throws {
        await recorder.record(input)
    }

    func resume(sessionRef: String) async throws {}

    func interrupt() async throws {}

    func close() async {}

    func skillsList(_ params: SkillsListParams) async throws -> SkillsListResponse {
        SkillsListResponse(data: [SkillsListEntry(
            cwd: "/workspace/project",
            errors: [],
            skills: [SkillMetadata(
                description: "",
                enabled: true,
                name: "review",
                path: "/skills/review",
                scope: .user
            )]
        )])
    }

    var sentInputs: [[ChatInput]] {
        get async { await recorder.sentInputs }
    }
}
