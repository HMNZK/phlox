import Foundation
import Testing
import AgentDomain
import CodexAppServerKit
import StructuredChatKit
import ClaudeAgentKit
@testable import DashboardFeature
@testable import SessionFeature

private actor LaunchClient: StructuredAgentClient, SpawnAgentSettingsControlling {
    nonisolated let events: AsyncStream<NormalizedChatEvent>
    nonisolated let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    var starts = 0
    var inputs: [[ChatInput]] = []
    var settings: (String?, String?, String?)?
    let failsStart: Bool
    let holdsStart: Bool
    private var startGate: CheckedContinuation<Void, Never>?
    init(failsStart: Bool = false, holdsStart: Bool = false) {
        (events, continuation) = AsyncStream.makeStream()
        self.failsStart = failsStart
        self.holdsStart = holdsStart
    }
    func start() async throws {
        starts += 1
        if holdsStart { await withCheckedContinuation { startGate = $0 } }
        if failsStart { throw ChatLaunchError.processFailed("fake launch failure") }
    }
    func releaseStart() { startGate?.resume(); startGate = nil }
    func turnStart(_ input: [ChatInput]) async throws { inputs.append(input) }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func applySpawnAgentSettings(model: String?, permissionOrMode: String?, effort: String?) async {
        settings = (model, permissionOrMode, effort)
    }
}

@Suite("New chat launch", .serialized) @MainActor
final class NewChatLaunchTests {
    private let defaultsSuite = "phlox-unc-launch-\(UUID())"
    deinit { UserDefaults(suiteName: defaultsSuite)?.removePersistentDomain(forName: defaultsSuite) }
    private func dashboard(_ clients: [any StructuredAgentClient], kind: AgentKind = .claudeCode,
                           store: InMemorySessionStore = InMemorySessionStore()) -> DashboardViewModel {
        let sequence = StructuredClientSequence(clients)
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() }, sessions: store,
            agentBinaryPaths: [kind: "/bin/echo"],
            appServerClientFactory: { _, _, _, _, _ in try sequence.next() }
        ))
        dashboard.addProject(name: "Launch", directoryPath: "/tmp")
        dashboard.lastUsedChatSettingsStoreForTesting = LastUsedChatSettingsStore(defaults: UserDefaults(suiteName: defaultsSuite)!)
        return dashboard
    }
    private func request(_ dashboard: DashboardViewModel, kind: AgentKind = .claudeCode,
                         attachments: [ComposerAttachment] = []) -> NewChatLaunchRequest {
        NewChatLaunchRequest(projectID: dashboard.projects[0].id, agentRef: .builtin(kind),
            settings: CodexAppServerSessionSettings(selectedModel: kind == .cursor ? "auto" : "fable",
                selectedEffort: "high", selectedPermissionProfile: kind == .cursor ? "ask" : "acceptEdits",
                isPlanMode: false), usesWorktree: false, text: "first message", attachments: attachments)
    }
    @Test(arguments: [AgentKind.claudeCode, .cursor])
    func AC2_settingsAndFirstMessage(kind: AgentKind) async throws {
        let client = LaunchClient()
        let dashboard = dashboard([client], kind: kind)
        let r = request(dashboard, kind: kind)
        let id = try await dashboard.launchNewChat(r)
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        #expect(dashboard.sessionNodes.count == 1)
        #expect(vm.rawWorkspacePath == "/tmp")
        #expect(await client.starts == 1)
        #expect(await client.inputs == [[.text(r.text)]])
        let settings = try #require(await client.settings)
        #expect(settings.0 == r.settings.selectedModel)
        #expect(settings.1 == r.settings.selectedPermissionProfile)
        if kind == .claudeCode { #expect(settings.2 == r.settings.selectedEffort) }
        await dashboard.removeSession(id)
    }
    @Test func AC2_codexModelAtThreadStartAndSettingsBeforeTurn() async throws {
        let transport = ScriptedAppServerTransport()
        let client = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
        let dashboard = dashboard([client], kind: .codex)
        let r = NewChatLaunchRequest(projectID: dashboard.projects[0].id, agentRef: .builtin(.codex),
            settings: CodexAppServerSessionSettings(selectedModel: "o4-mini", selectedEffort: "high",
                selectedPermissionProfile: ":read-only", isPlanMode: false),
            usesWorktree: false, text: "first", attachments: [])
        let id = try await dashboard.launchNewChat(r)
        #expect(transport.capturedThreadStartParams()?["model"] as? String == "o4-mini")
        let applied = try #require(transport.capturedParams(for: "thread/settings/update").last)
        #expect(applied["effort"] as? String == "high")
        #expect(applied["permissions"] as? String == ":read-only")
        #expect(transport.capturedParams(for: "turn/start").count == 1)
        await dashboard.removeSession(id)
    }
    @Test func AC5_claudeLaunchFailureRetainsRowAndDraft() async throws {
        let client = LaunchClient(failsStart: true)
        let store = InMemorySessionStore()
        let dashboard = dashboard([client], store: store)
        let attachments = [ComposerAttachment(data: Data([1]), mediaType: "image/png")]
        let id = try await dashboard.launchNewChat(request(dashboard, attachments: attachments))
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        #expect(dashboard.sessionNodes.count == 1)
        #expect(vm.launchFailure == .processFailed("fake launch failure"))
        #expect(vm.draft == "first message")
        #expect(vm.attachmentStore.attachments == attachments)
        #expect(await client.inputs.isEmpty)
        #expect(await store.load().isEmpty)
        if case .error = vm.status {} else { Issue.record("launch error overwritten") }
        await dashboard.removeSession(id)
    }
    @Test func AC5_codexSettingsFailureDoesNotSend() async throws {
        let transport = ScriptedAppServerTransport()
        transport.settingsUpdateErrorMessage = "fake settings failure"
        let client = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
        let dashboard = dashboard([client], kind: .codex)
        let attachments = [ComposerAttachment(data: Data([1]), mediaType: "image/png")]
        let id = try await dashboard.launchNewChat(request(dashboard, kind: .codex, attachments: attachments))
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        #expect(dashboard.sessionNodes.count == 1)
        if case .settingsNotApplied = vm.launchFailure {} else { Issue.record("missing settings error") }
        #expect(vm.draft == "first message")
        #expect(vm.attachmentStore.attachments == attachments)
        #expect(!transport.sentMethods().contains("turn/start"))
        await dashboard.removeSession(id)
    }
    @Test func AC5_sendRejectionKeepsSessionAndAttachments() async throws {
        let client = LaunchClient()
        let dashboard = dashboard([client], kind: .cursor)
        let attachments = [ComposerAttachment(data: Data([1]), mediaType: "image/png")]
        let id = try await dashboard.launchNewChat(request(dashboard, kind: .cursor, attachments: attachments))
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        #expect(vm.launchFailure == nil)
        #expect(vm.draft == "first message")
        #expect(vm.attachmentStore.attachments == attachments)
        #expect(await client.inputs.isEmpty)
        vm.attachmentStore.clear()
        let text = try #require(vm.consumeDraftForSend())
        try await vm.sendText(text, submit: true)
        #expect(await client.inputs == [[.text("first message")]])
        #expect(dashboard.sessionNodes.count == 1)
        await dashboard.removeSession(id)
    }
    @Test func AC5a_requestDoesNotStartConversation() async {
        let client = LaunchClient()
        let dashboard = dashboard([client])
        _ = request(dashboard)
        #expect(await client.starts == 0)
        #expect(dashboard.sessionNodes.isEmpty)
    }
    @Test func AC7_permissionAndPlanRoundTripPerHarness() throws {
        let suite = "phlox-launch-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = LastUsedChatSettingsStore(defaults: defaults)
        store.record(agentID: "claude-code", model: "fable", effort: "high", permission: "acceptEdits", isPlanMode: true)
        store.record(agentID: "cursor", model: "auto", effort: nil, permission: "ask", isPlanMode: false)
        let settings = try #require(DashboardViewModel.persistedSettings(from: store.lastUsed(agentID: "claude-code")))
        #expect(settings.selectedPermissionProfile == "acceptEdits")
        #expect(settings.isPlanMode == true)
        #expect(store.lastUsed(agentID: "cursor")?.permission == "ask")
        #expect(store.lastUsed(agentID: "codex") == nil)
    }
    @Test func AC15_restartMovesEditedDraftWithoutSending() async throws {
        let failed = LaunchClient(failsStart: true)
        let replacement = LaunchClient()
        let dashboard = dashboard([failed, replacement])
        let id = try await dashboard.launchNewChat(request(dashboard))
        let old = try #require(dashboard.sessionNode(id: id)?.appServer)
        old.draft = "edited text"
        let attachments = [ComposerAttachment(data: Data([2]), mediaType: "image/png")]
        old.attachmentStore.restore(attachments)
        let newID = try await dashboard.restartNewChat(id)
        let vm = try #require(dashboard.sessionNode(id: newID)?.appServer)
        #expect(newID != id)
        #expect(dashboard.sessionNodes.count == 1)
        #expect(dashboard.sessionNode(id: id) == nil)
        #expect(vm.draft == "edited text")
        #expect(vm.attachmentStore.attachments == attachments)
        #expect(await replacement.starts == 1)
        #expect(await replacement.inputs.isEmpty)
        await dashboard.removeSession(newID)
    }

    @Test(arguments: [AgentKind.claudeCode, .cursor])
    func AC5_asyncFirstTurnErrorRestoresDraft(kind: AgentKind) async throws {
        let client = LaunchClient()
        let dashboard = dashboard([client], kind: kind)
        let id = try await dashboard.launchNewChat(request(dashboard, kind: kind))
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        client.continuation.yield(.error(message: "fake first turn failure"))
        for _ in 0..<100 {
            if vm.draft == "first message" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(vm.draft == "first message")
        #expect(dashboard.sessionNodes.count == 1)
        #expect(await client.inputs.count == 1)
        await dashboard.removeSession(id)
    }
    @Test func responseBeforeErrorDoesNotRestoreFirstDraft() async throws {
        let client = LaunchClient()
        let dashboard = dashboard([client])
        let id = try await dashboard.launchNewChat(request(dashboard))
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        client.continuation.yield(.agentMessageDelta(itemId: "reply", "response"))
        client.continuation.yield(.error(message: "fake later error"))
        for _ in 0..<100 {
            if case .error = vm.status { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        if case .error = vm.status {} else { Issue.record("error not processed") }
        #expect(vm.draft.isEmpty)
        await dashboard.removeSession(id)
    }

    @Test func E5_rowIsPublishedWithPendingMessageBeforeStartCompletes() async throws {
        let client = LaunchClient(holdsStart: true)
        let dashboard = dashboard([client])
        var rowID: SessionID?
        let task = Task { try await dashboard.launchNewChat(request(dashboard), onRowAppended: { rowID = $0 }) }
        for _ in 0..<100 {
            if await client.starts == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let observed = rowID.flatMap { dashboard.sessionNode(id: $0)?.appServer }
        #expect(observed?.status == .starting)
        #expect(observed?.draft == "")
        #expect(observed?.pendingFirstMessage != nil)
        #expect(observed?.isReadyForInput == false)
        #expect(await client.inputs.isEmpty)
        await client.releaseStart()
        let id = try await task.value
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        #expect(vm.pendingFirstMessage == nil)
        #expect(vm.transcript.filter { if case .userMessage = $0 { true } else { false } }.count == 1)
        #expect(vm.transcriptItemIDs == Set(vm.transcript.map(\.id)))
        #expect(dashboard.lastUsedChatSettingsStoreForTesting.lastHarness == AgentRef.builtin(.claudeCode).id)
        await dashboard.removeSession(id)
    }

    @Test func AC5_claudeAdapterPropagatesFakeExecutableFailure() async throws {
        let client = ClaudeChatClient(command: "/tmp/phlox-missing-fake-cli-\(UUID())", workingDirectory: nil, environment: [:])
        let dashboard = dashboard([client])
        let attachments = [ComposerAttachment(data: Data([1]), mediaType: "image/png")]
        let id = try await dashboard.launchNewChat(request(dashboard, attachments: attachments))
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        if case .processFailed = vm.launchFailure {} else { Issue.record("missing launch failure") }
        #expect(vm.draft == "first message")
        #expect(vm.attachmentStore.attachments == attachments)
        #expect(vm.pendingFirstMessage == nil)
        #expect(dashboard.sessionNodes.count == 1)
        #expect(vm.transcript.allSatisfy { if case .userMessage = $0 { false } else { true } })
        await dashboard.removeSession(id)
    }

    @Test func AC7_undetectedHarnessIsRejectedBeforeStarting() async throws {
        let client = LaunchClient()
        let dashboard = dashboard([client])
        await #expect(throws: AgentSpawnError.binaryNotFound(.codex)) {
            try await dashboard.launchNewChat(request(dashboard, kind: .codex))
        }
        #expect(dashboard.sessionNodes.isEmpty)
        #expect(await client.starts == 0)
    }

    @Test(arguments: [false, true])
    func codexFirstTurnErrorRestoresDraftOnlyWithoutResponse(hasResponse: Bool) async throws {
        let transport = ScriptedAppServerTransport()
        let client = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
        let dashboard = dashboard([client], kind: .codex)
        let r = NewChatLaunchRequest(projectID: dashboard.projects[0].id, agentRef: .builtin(.codex),
            settings: CodexAppServerSessionSettings(selectedModel: "gpt-5-codex", selectedEffort: "medium",
                selectedPermissionProfile: ":workspace", isPlanMode: false),
            usesWorktree: false, text: "first", attachments: [])
        let id = try await dashboard.launchNewChat(r)
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        if hasResponse {
            transport.receive(#"{"jsonrpc":"2.0","method":"item/completed","params":{"threadId":"thread-1","turnId":"turn-1","item":{"id":"reply","type":"agent_message","text":"response"}}}"#)
        }
        transport.receive(#"{"jsonrpc":"2.0","method":"error","params":{"threadId":"thread-1","turnId":"turn-1","error":{"message":"fake turn failure"},"willRetry":false}}"#)
        for _ in 0..<100 {
            if case .error = vm.status { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        if case .error = vm.status {} else { Issue.record("error not processed") }
        #expect(vm.draft == (hasResponse ? "" : "first"))
        #expect(dashboard.sessionNodes.count == 1)
        await dashboard.removeSession(id)
    }
}
