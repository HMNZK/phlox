// 契約の正本: tasks/task-4.md — ターン途中の transcript 永続化（作業中クローズでのデータ欠落修正）。
// このファイルは PM が凍結する受け入れテスト。実装役はアサーションを変更禁止
// （テストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい）。
//
// 背景: 従来はターン境界（turnCompleted/turnInterrupted/error）でしか flush されず、
// 作業中にアプリを閉じると途中までの transcript が失われていた。
//
// 契約:
//   - ターン途中でも、非 delta イベント（コマンド実行等）の到着で当該アイテムが
//     TranscriptStore へ永続化される（leading-edge: 最初の到着は遅延なく flush。
//     以後のスロットルは実装の裁量だが、ターン完了を待ってはならない）
//   - flushTranscriptNow() は保留中のストリーム delta を含む現在の transcript を
//     upsert し、書き込み完了まで待つ（アプリ終了経路から呼ぶための API）

import Foundation
import os
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class MidTurnFakeClient: StructuredAgentClient, @unchecked Sendable {
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

private final class InMemoryTranscriptStore: TranscriptStore, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [SessionID: [ChatItem]]())

    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] {
        state.withLock { $0[sessionID] ?? [] }
    }

    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {
        state.withLock { storage in
            var current = storage[sessionID] ?? []
            for item in items {
                if let index = current.firstIndex(where: { $0.id == item.id }) {
                    current[index] = item
                } else {
                    current.append(item)
                }
            }
            storage[sessionID] = current
        }
    }

    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {
        state.withLock { $0[sessionID] = items }
    }

    func persistedItems(for sessionID: SessionID) -> [ChatItem] {
        state.withLock { $0[sessionID] ?? [] }
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
private func makeViewModel() -> (ChatSessionViewModel, MidTurnFakeClient, InMemoryTranscriptStore, SessionID) {
    let client = MidTurnFakeClient()
    let store = InMemoryTranscriptStore()
    let sessionID = SessionID()
    let vm = ChatSessionViewModel(
        id: sessionID,
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-midturn-persistence-test",
        transcriptStore: store
    )
    return (vm, client, store, sessionID)
}

@Suite("Acceptance: ターン途中の transcript 永続化（task-4）")
struct AcceptanceMidTurnPersistenceTests {
    @Test @MainActor
    func ターン途中のコマンド実行がターン完了を待たず永続化される() async throws {
        let (vm, client, store, sessionID) = makeViewModel()

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        client.yield(.commandExecution(itemId: "cmd-1", command: "swift build", outputDelta: "Compiling...\n"))
        try await waitUntil { vm.transcript.contains { $0.id == "cmd-1" } }

        // turnCompleted は流さない。それでも store に載ることが契約。
        try await waitUntil {
            store.persistedItems(for: sessionID).contains { $0.id == "cmd-1" }
        }
        let persisted = store.persistedItems(for: sessionID)
        #expect(persisted.contains { $0.id == "cmd-1" })
    }

    @Test @MainActor
    func flushTranscriptNowは保留中deltaを含めて書き切る() async throws {
        let (vm, client, store, sessionID) = makeViewModel()

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        client.yield(.agentMessageDelta(itemId: "msg-1", "書きかけの応答です。"))
        try await waitUntil { vm.transcript.contains { $0.id == "msg-1" } }

        await vm.flushTranscriptNow()

        let persisted = store.persistedItems(for: sessionID)
        let persistedText = persisted.compactMap { item -> String? in
            if case .agentMessage(let id, let text, _) = item, id == "msg-1" { return text }
            return nil
        }.first
        #expect(persistedText?.contains("書きかけの応答です。") == true)
    }
}
