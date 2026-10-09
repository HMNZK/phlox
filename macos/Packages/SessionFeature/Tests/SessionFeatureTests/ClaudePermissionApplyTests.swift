import Foundation
import Testing
import AgentDomain
import StructuredChatKit
@testable import SessionFeature

private final class ConfirmingPermissionClient: StructuredAgentClient, SpawnAgentSettingsControlling,
    SpawnAgentPermissionControlling, @unchecked Sendable {
    let events = AsyncStream<NormalizedChatEvent> { _ in }
    let gate = AsyncStream<Void>.makeStream()
    var rejects = false
    var rejectionError: any Error = NSError(domain: "ClaudePermission", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "The permission change was rejected.",
    ])
    var turnBarrier: AsyncStream<Void>?
    private let lock = NSLock()
    private var changing = false
    private var sent = 0
    var sentTurns: Int { lock.withLock { sent } }
    func start() async {}
    func resume(sessionRef: String) async throws {}
    func turnStart(_ input: [ChatInput]) async throws {
        try lock.withLock {
            if changing { throw ChatSettingsUpdateError.spawnSettingsUpdateInProgress }
            sent += 1
        }
        if let turnBarrier {
            var iterator = turnBarrier.makeAsyncIterator()
            _ = await iterator.next()
        }
    }
    func interrupt() async throws {}
    func close() async { gate.continuation.finish() }
    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {}
    func setSpawnAgentPermission(_ permission: String?) async throws {
        lock.withLock { changing = true }
        defer { lock.withLock { changing = false } }
        var iterator = gate.stream.makeAsyncIterator()
        _ = await iterator.next()
        if rejects { throw rejectionError }
    }
}

@MainActor @Suite struct ClaudePermissionApplyTests {
    private func makeVM(_ client: ConfirmingPermissionClient) async throws -> ChatSessionViewModel {
        let vm = ChatSessionViewModel(
            id: SessionID(), agentRef: .builtin(.claudeCode), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/tmp",
            spawnAgentPermissionOverride: "manual", spawnAgentModelsProvider: { ["default"] }
        )
        try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
        return vm
    }

    private func waitForChange(_ vm: ChatSessionViewModel) async throws {
        for _ in 0..<100 {
            if vm.isApplyingSpawnAgentPermission { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        throw ChatSettingsUpdateError.spawnSettingsUpdateInProgress
    }

    @Test func displayedAndSavedPermissionWaitForConfirmation() async throws {
        let client = ConfirmingPermissionClient()
        let vm = try await makeVM(client)
        var saved: [CodexAppServerSessionSettings?] = []
        vm.codexSettingsDidChange = { saved.append($0) }
        let change = Task { await vm.setSpawnAgentPermission("bypassPermissions") }
        try await waitForChange(vm)
        #expect(vm.selectedPermissionProfile == "manual")
        #expect(saved.isEmpty)
        #expect(await vm.applyControlModel("default") == .failed)
        client.gate.continuation.yield(())
        await change.value
        #expect(vm.selectedPermissionProfile == "bypassPermissions")
        #expect(saved.last??.selectedPermissionProfile == "bypassPermissions")
        #expect(!vm.isApplyingSpawnAgentPermission)
        await client.close()
    }

    @Test(arguments: [false, true])
    func rejectedPermissionKeepsDisplayAndSavedValueAndShowsError(transportFailure: Bool) async throws {
        let client = ConfirmingPermissionClient()
        client.rejects = true
        if transportFailure { client.rejectionError = LineDelimitedProcessTransportError.stdinClosed }
        let vm = try await makeVM(client)
        var saveCount = 0
        vm.codexSettingsDidChange = { _ in saveCount += 1 }
        let change = Task { await vm.setSpawnAgentPermission("bypassPermissions") }
        try await waitForChange(vm)
        client.gate.continuation.yield(())
        await change.value
        #expect(vm.selectedPermissionProfile == "manual")
        #expect(!vm.isPlanMode)
        #expect(saveCount == 0)
        #expect(vm.transcript.contains {
            if case .error(_, let message, _) = $0 {
                return message.hasSuffix(transportFailure
                    ? "The agent's input channel has closed."
                    : "The permission change was rejected.")
            }
            return false
        })
        await client.close()
    }

    @Test func planModeWaitsForConfirmationAndRetainsReturnPermission() async throws {
        let client = ConfirmingPermissionClient()
        let vm = try await makeVM(client)
        let change = Task { try await vm.setPlanMode(true) }
        try await waitForChange(vm)
        #expect(!vm.isPlanMode)
        client.gate.continuation.yield(())
        try await change.value
        #expect(vm.isPlanMode)
        #expect(vm.selectedPermissionProfile == "manual")
        let leave = Task { try await vm.setPlanMode(false) }
        try await waitForChange(vm)
        client.gate.continuation.yield(())
        try await leave.value
        #expect(!vm.isPlanMode)
        #expect(vm.selectedPermissionProfile == "manual")
        await client.close()
    }

    @Test func pendingPermissionChangeRejectsSendWithoutChangingRunningTurnOrDraft() async throws {
        let client = ConfirmingPermissionClient()
        let vm = try await makeVM(client)
        try await vm.sendText("first", submit: true)
        #expect(vm.status == .running)
        vm.draft = "follow-up"
        let before = vm.transcript.count
        let change = Task { await vm.setSpawnAgentPermission("bypassPermissions") }
        try await waitForChange(vm)
        #expect(!vm.isReadyForInput)
        #expect(vm.consumeDraftForSend() == nil)
        await #expect(throws: ChatSettingsUpdateError.spawnSettingsUpdateInProgress) {
            try await vm.sendText("follow-up", submit: true)
        }
        #expect(vm.status == .running)
        #expect(vm.draft == "follow-up")
        #expect(vm.transcript.count == before)
        #expect(client.sentTurns == 1)
        client.gate.continuation.yield(())
        await change.value
        #expect(vm.isReadyForInput)
        await client.close()
    }

    @Test func permissionChangeWaitsUntilTurnSubmissionHasFinished() async throws {
        let client = ConfirmingPermissionClient()
        let vm = try await makeVM(client)
        let turn = AsyncStream<Void>.makeStream()
        client.turnBarrier = turn.stream
        let send = Task { try await vm.sendText("first", submit: true) }
        for _ in 0..<100 {
            if client.sentTurns == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(client.sentTurns == 1)
        client.gate.continuation.yield(())
        await vm.setSpawnAgentPermission("bypassPermissions")
        #expect(vm.selectedPermissionProfile == "manual")
        #expect(vm.status == .running)
        turn.continuation.yield(())
        try await send.value
        await vm.setSpawnAgentPermission("bypassPermissions")
        #expect(vm.selectedPermissionProfile == "bypassPermissions")
        await client.close()
    }
}
