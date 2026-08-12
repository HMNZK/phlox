import Foundation
import Observation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

/// task-6 の統合シーム契約。
/// process/item/thread/turn の値が、既存 transcript と Codex 専用 surface の間で
/// 配列位置や表示文言から再推測されないことを固定する。
@Suite("ContractCodexChatParityIntegrationTests")
@MainActor
struct ContractCodexChatParityIntegrationTests {
    private final class Client: StructuredAgentClient, @unchecked Sendable {
        private actor Recorder {
            private var resumes: [String] = []

            func recordResume(_ sessionRef: String) {
                resumes.append(sessionRef)
            }

            var snapshot: [String] { resumes }
        }

        let events: AsyncStream<NormalizedChatEvent>
        private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
        private let recorder = Recorder()

        init() {
            var captured: AsyncStream<NormalizedChatEvent>.Continuation?
            events = AsyncStream { captured = $0 }
            continuation = captured!
        }

        func start() async {}
        func turnStart(_ input: [ChatInput]) async throws {}
        func resume(sessionRef: String) async throws {
            await recorder.recordResume(sessionRef)
        }
        func interrupt() async throws {}
        func close() async { continuation.finish() }
        func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }

        var recordedResumes: [String] { get async { await recorder.snapshot } }
    }

    private func makeVM(_ client: Client) -> ChatSessionViewModel {
        ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-codex-parity-contract"
        )
    }

    private enum ObservationWaitError: Error {
        case timedOut
    }

    private func awaitObservation(
        timeout: Duration = .seconds(2),
        observing: @escaping () -> Void,
        trigger: () -> Void
    ) async throws {
        let (changes, continuation) = AsyncStream<Void>.makeStream()
        withObservationTracking {
            observing()
        } onChange: {
            continuation.yield()
            continuation.finish()
        }
        trigger()
        defer { continuation.finish() }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                var iterator = changes.makeAsyncIterator()
                guard await iterator.next() != nil else {
                    throw ObservationWaitError.timedOut
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ObservationWaitError.timedOut
            }
            defer { group.cancelAll() }
            guard try await group.next() != nil else {
                throw ObservationWaitError.timedOut
            }
        }
    }

    private func withTerminatedViewModels<T>(
        _ viewModels: [ChatSessionViewModel],
        operation: () async throws -> T
    ) async throws -> T {
        do {
            let result = try await operation()
            for viewModel in viewModels {
                await viewModel.terminate()
            }
            return result
        } catch {
            for viewModel in viewModels {
                await viewModel.terminate()
            }
            throw error
        }
    }

    @Test("重複する値を持つ process/item/thread ID を別 surface へ混線させない")
    func overlappingIDsRemainDistinctAcrossSurfaces() async throws {
        let client = Client()
        let viewModel = makeVM(client)

        try await withTerminatedViewModels([viewModel]) {
            try await awaitObservation(
                observing: { _ = viewModel.subAgents },
                trigger: {
                    client.yield(.turnStarted)
                    client.yield(.taskListUpdated(tasks: [
                        AgentTaskItem(id: "same-id", title: "plan", status: .inProgress),
                    ]))
                    client.yield(.backgroundTaskStarted(
                        taskId: "same-id",
                        taskType: "backgroundTerminal",
                        description: "same id process",
                        toolUseId: "same-id"
                    ))
                    client.yield(.subAgentStarted(
                        toolUseId: "same-id",
                        subagentType: "worker",
                        description: "same id child"
                    ))
                }
            )

            let taskCard = try #require(viewModel.transcript.compactMap { item -> [AgentTaskItem]? in
                guard case .taskList(_, let tasks, _) = item else { return nil }
                return tasks
            }.first)
            #expect(taskCard.map(\.id) == ["same-id"])
            #expect(viewModel.runningBackgroundTasks.count == 1,
                    "plan の task ID を background item ID の存在判定へ流用しないこと")
            #expect(viewModel.runningBackgroundTasks.first?.taskId == "same-id")
            #expect(viewModel.subAgents.first?.id == "same-id")
        }
    }

    @Test("履歴 resume の成功判定は選択した thread ID に限定する")
    func resumeIdentityUsesSelectedThreadID() async throws {
        let client = Client()
        let viewModel = makeVM(client)
        let entry = ClaudeSessionHistoryEntry(
            sessionID: "selected-thread",
            preview: "selected",
            firstUserAt: nil,
            lastModified: Date(),
            gitBranch: nil,
            fileURL: URL(fileURLWithPath: "/tmp/selected-thread.jsonl")
        )

        // この契約は UI の表示順ではなく、選択値そのものを resume へ渡す境界を検査する。
        // provider/loader は task-2 の Codex 専用 state が公開する統合 API に置き換えず、
        // 現行 VM の実 resume seam を通す。
        let historyVM = ChatSessionViewModel(
            id: SessionID(),
            agentRef: .builtin(.codex),
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: "/tmp/phlox-codex-parity-contract",
            historyProvider: { [entry] },
            historyTranscriptLoader: { _ in [] }
        )
        try await withTerminatedViewModels([viewModel, historyVM]) {
            await historyVM.startFromHistory(entry)

            #expect(await client.recordedResumes == [entry.sessionID])
            #expect(historyVM.threadId == entry.sessionID)
            #expect(viewModel.threadId == nil, "別 VM の current thread を誤って更新しないこと")
        }
    }
}
