// availableCommandsUpdated イベントをセッションの状態として保持し、
// composer の補完がそのセッションの一覧を使えるようにする（nil は静的フォールバック、空配列は候補なし）。

import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class AvailableCommandsFakeClient: StructuredAgentClient, @unchecked Sendable {
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
    timeoutNanoseconds: UInt64 = 1_500_000_000,
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
private func makeViewModel() -> (ChatSessionViewModel, AvailableCommandsFakeClient) {
    let client = AvailableCommandsFakeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/phlox-available-commands-test"
    )
    return (vm, client)
}

@Suite("Composer available commands")
struct ComposerAvailableCommandsTests {

    @Test @MainActor
    func availableCommandsAreNilBeforeInitArrives() async throws {
        let (vm, _) = makeViewModel()

        #expect(
            vm.availableSlashCommands == nil,
            "init 受領前は「一覧未取得」を nil で表し、静的フォールバックへ委ねること"
        )
    }

    @Test @MainActor
    func availableCommandsUpdatedIsStoredOnTheSession() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.availableCommandsUpdated(commands: ["compact", "clear", "recap"]))
        try await waitUntil { vm.availableSlashCommands != nil }

        #expect(vm.availableSlashCommands == ["compact", "clear", "recap"])
    }

    @Test @MainActor
    func laterUpdatesReplaceTheStoredList() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.availableCommandsUpdated(commands: ["compact"]))
        try await waitUntil { vm.availableSlashCommands != nil }

        client.yield(.availableCommandsUpdated(commands: ["clear", "model"]))
        try await waitUntil { vm.availableSlashCommands?.count == 2 }

        #expect(
            vm.availableSlashCommands == ["clear", "model"],
            "一覧は差分ではなく最新スナップショットで置き換えること"
        )
    }

    @Test @MainActor
    func storedListIsNotClearedByUnrelatedEvents() async throws {
        let (vm, client) = makeViewModel()

        client.yield(.availableCommandsUpdated(commands: ["compact", "clear"]))
        try await waitUntil { vm.availableSlashCommands != nil }

        client.yield(.turnStarted)
        try await waitUntil { vm.status == .running }

        #expect(
            vm.availableSlashCommands == ["compact", "clear"],
            "ターンをまたいで一覧を保持すること（init は毎ターン来るとは限らない）"
        )
    }

    @MainActor
    @Test("nil は静的フォールバック、空配列は候補なし")
    func nilAndEmptyAvailableCommandsAreDistinct() async throws {
        let controller = ComposerSuggestionController.production(workingDirectory: "/tmp")

        controller.update(text: "/clear", cursorUTF16: 6)
        try await waitForScan(controller)
        #expect(controller.candidates.map(\.title).contains("/clear"))

        controller.availableSlashCommands = []
        controller.update(text: "/clear", cursorUTF16: 6)
        try await waitForScan(controller)
        #expect(controller.candidates.isEmpty)
    }

    @MainActor
    private func waitForScan(_ controller: ComposerSuggestionController) async throws {
        for _ in 0..<100 where controller.isScanning {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(!controller.isScanning, "候補走査が 1 秒以内に完了すること")
    }
}
