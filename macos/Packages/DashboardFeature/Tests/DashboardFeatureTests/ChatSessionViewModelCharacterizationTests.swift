// ChatSessionViewModel 特性化テスト（Feathers / task-4）
// 現在の観測可能な振る舞いを固定する。既存テストが覆う領域は重複させない。

import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

// MARK: - Test doubles

private final class CharacterizationFakeClient: StructuredAgentClient, @unchecked Sendable {
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
    func resetConversation() async {}

    func yield(_ event: NormalizedChatEvent) {
        continuation.yield(event)
    }
}

// MARK: - Helpers

@MainActor
private func characterizationVM(
    id: SessionID = SessionID(),
    agentRef: AgentRef = .builtin(.cursor),
    client: CharacterizationFakeClient = CharacterizationFakeClient(),
    workingDirectory: String? = "/tmp/phlox-char-work",
    attachmentStore: ComposerAttachmentStore? = nil
) -> (ChatSessionViewModel, CharacterizationFakeClient) {
    let vm: ChatSessionViewModel
    if let attachmentStore {
        vm = ChatSessionViewModel(
            id: id,
            agentRef: agentRef,
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: workingDirectory,
            attachmentStore: attachmentStore
        )
    } else {
        vm = ChatSessionViewModel(
            id: id,
            agentRef: agentRef,
            client: client,
            approvalBroker: ChatApprovalBroker(),
            workingDirectory: workingDirectory
        )
    }
    return (vm, client)
}

@MainActor
private func characterizationCodexVM(
    transport: ScriptedAppServerTransport = ScriptedAppServerTransport()
) -> (ChatSessionViewModel, ScriptedAppServerTransport) {
    let broker = ChatApprovalBroker()
    let client = CodexAppServerClient(transport: transport, serverRequestHandler: broker.serverRequestHandler)
    let vm = ChatSessionViewModel(
        id: SessionID(),
        client: CodexStructuredAgentClient(client: client),
        approvalBroker: broker,
        workingDirectory: "/tmp/phlox-char-work"
    )
    return (vm, transport)
}

private let characterizationFixedSessionID = SessionID(
    rawValue: UUID(uuidString: "F8392100-0000-0000-0000-000000000000")!
)

// MARK: - Characterization tests

@Test @MainActor
func characterization_init_exposesStartingSessionDefaults() {
    let (vm, _) = characterizationVM()

    #expect(vm.status == .starting)
    #expect(vm.transcript.isEmpty)
    #expect(vm.restoreState == .notRestored)
    #expect(vm.sessionTotalCostUSD == 0)
    #expect(vm.completedTurnSeq == 0)
    #expect(vm.draft == "")
    #expect(vm.pendingApprovals.isEmpty)
    #expect(vm.selectedSubAgentId == nil)
}

@Test @MainActor
func characterization_displayName_fallsBackToShortIDWhenNameBlank() {
    let (vm, _) = characterizationVM(id: characterizationFixedSessionID)

    #expect(vm.displayName == "#F83921")
}

@Test @MainActor
func characterization_displayName_returnsTrimmedCustomName() {
    let (vm, _) = characterizationVM(id: characterizationFixedSessionID)
    vm.name = "  特性化セッション  "

    #expect(vm.displayName == "特性化セッション")
}

@Test @MainActor
func characterization_workspaceNameAndPath_emptyWhenWorkingDirectoryNil() {
    let (vm, _) = characterizationVM(workingDirectory: nil)

    #expect(vm.workspaceName == "")
    #expect(vm.workspacePath == "")
}

@Test @MainActor
func characterization_workspaceNameAndPath_resolveBasenameAndFullPath() {
    let (vm, _) = characterizationVM(workingDirectory: "/tmp/phlox-char-work")

    #expect(vm.workspaceName == "phlox-char-work")
    #expect(vm.workspacePath == "/tmp/phlox-char-work")
}

@Test @MainActor
func characterization_isReadyForInput_falseWhileStarting_trueWhenIdleOrRunning() async throws {
    let (vm, client) = characterizationVM()

    #expect(vm.isReadyForInput == false)

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    #expect(vm.isReadyForInput == true)

    try await vm.sendText("実行中", submit: true)
    #expect(vm.status == .running)
    #expect(vm.isReadyForInput == true)

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    #expect(vm.isReadyForInput == true)
}

@Test @MainActor
func characterization_spawnAgentModelDisplayName_mapsKnownAliasAndPassesThroughUnknown() {
    let (vm, _) = characterizationVM()

    #expect(vm.spawnAgentModelDisplayName("opus") == "Opus 4.8")
    #expect(vm.spawnAgentModelDisplayName("sonnet") == "Sonnet 5")
    #expect(vm.spawnAgentModelDisplayName("cursor-custom-model") == "cursor-custom-model")
}

@Test @MainActor
func characterization_codexSettingsSnapshot_reflectsPlanModeDefaultThenThreadStartSettings() async throws {
    let (vm, _) = characterizationCodexVM()

    let beforeStart = try #require(vm.codexSettingsSnapshot)
    #expect(beforeStart.selectedModel == nil)
    #expect(beforeStart.selectedEffort == nil)
    #expect(beforeStart.selectedPermissionProfile == nil)
    #expect(beforeStart.isPlanMode == false)

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))

    let afterStart = try #require(vm.codexSettingsSnapshot)
    #expect(afterStart.selectedModel == "gpt-5-codex")
    #expect(afterStart.selectedEffort == "medium")
    #expect(afterStart.selectedPermissionProfile == ":workspace")
    #expect(afterStart.isPlanMode == false)
}

@Test @MainActor
func characterization_consumeDraftForSend_attachmentOnlyReturnsEmptyStringAndClearsDraft() {
    let store = ComposerAttachmentStore()
    store.addImage(data: Data([0x89, 0x50, 0x4E, 0x47]), mediaType: "image/png")
    let (vm, _) = characterizationVM(attachmentStore: store)
    vm.draft = "   "

    #expect(vm.consumeDraftForSend() == "")
    #expect(vm.draft == "")
}

@Test @MainActor
func characterization_sendText_nonSubmit_defersTextUntilNextSubmit() async throws {
    let (vm, _) = characterizationVM()

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("hel", submit: false)

    #expect(vm.status == .idle)
    #expect(vm.transcript.isEmpty)

    try await vm.sendText("lo", submit: true)
    #expect(vm.transcript.count == 1)
    #expect(vm.transcript[0].plainText == "User: hello")
}

@Test @MainActor
func characterization_readText_zeroLinesReturnsEntireTranscript() async throws {
    let (vm, client) = characterizationVM()

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("一行目", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    try await vm.sendText("二行目", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.transcript.count == 2 }

    let full = vm.readText(lines: 0)
    #expect(full.contains("一行目"))
    #expect(full.contains("二行目"))

    let tail = vm.readText(lines: 1)
    #expect(tail == "User: 二行目")
}

@Test @MainActor
func characterization_revert_unknownUserMessageIDReturnsNilWithoutMutatingTranscript() async throws {
    let (vm, client) = characterizationVM()

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("既存メッセージ", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    let transcriptBefore = vm.transcript
    let restored = await vm.revert(toUserMessageID: "unknown-user-message-id")

    #expect(restored == nil)
    #expect(vm.transcript == transcriptBefore)
    #expect(vm.status == .idle)
}

@Test @MainActor
func characterization_escapeClosingPicker_allowsFreshDoubleTapToReopen() async throws {
    let (vm, client) = characterizationVM()

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("巻き戻し候補", submit: true)
    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }
    try #require(!vm.revertCandidates.isEmpty)

    let t0 = Date(timeIntervalSinceReferenceDate: 7_000)
    vm.handleEscapeKey(now: t0)
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.3))
    try #require(vm.isHistoryPickerPresented)

    vm.handleEscapeKey(now: t0.addingTimeInterval(0.6))
    try #require(!vm.isHistoryPickerPresented)

    vm.handleEscapeKey(now: t0.addingTimeInterval(0.7))
    vm.handleEscapeKey(now: t0.addingTimeInterval(0.9))
    #expect(vm.isHistoryPickerPresented)
}

@Test @MainActor
func characterization_consumeSubmitBaseline_clearsReservedBaselineTurnSeq() async throws {
    let (vm, client) = characterizationVM()

    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    try await vm.sendText("baseline", submit: true)
    #expect(vm.submitBaselineTurnSeq == 0)

    client.yield(.turnCompleted(nativeSessionId: nil))
    try await waitUntil { vm.status == .idle }

    vm.consumeSubmitBaseline()
    #expect(vm.submitBaselineTurnSeq == nil)
}
