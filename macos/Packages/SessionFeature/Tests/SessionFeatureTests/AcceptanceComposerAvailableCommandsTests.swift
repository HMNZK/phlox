// task-4 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-4.md
// 目的: availableCommandsUpdated イベントをセッションの状態として保持し、
//       composer の補完がそのセッションの一覧を使えるようにする。

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

@Suite("Acceptance: セッションの利用可能コマンドを composer へ届ける（task-4）")
struct AcceptanceComposerAvailableCommandsTests {

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
}
