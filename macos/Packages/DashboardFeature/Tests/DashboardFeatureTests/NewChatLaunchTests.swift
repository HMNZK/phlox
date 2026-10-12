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
    var resumes: [String] = []
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
    func resume(sessionRef: String) async throws { resumes.append(sessionRef) }
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
                           store: InMemorySessionStore = InMemorySessionStore(),
                           codexHome: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)) -> DashboardViewModel {
        let sequence = StructuredClientSequence(clients)
        let dashboard = DashboardViewModel(environment: makeTestEnvironment(
            pty: MockPTYManager(), hookStream: AsyncStream { $0.finish() }, sessions: store,
            codexHome: codexHome,
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

    @Test func AC5c_launchNewChatResumesHistoryWithSelectedWorkingDirectoryAndSettings() async throws {
        let historyID = "thread-1"
        let codexHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-chat-history-\(UUID().uuidString)", isDirectory: true)
        let day = codexHome.appendingPathComponent("sessions/2026/10/12", isDirectory: true)
        try FileManager.default.createDirectory(at: day, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: codexHome) }
        let rollout = day.appendingPathComponent("rollout-\(historyID).jsonl")
        try [
            #"{"type":"session_meta","payload":{"id":"\#(historyID)","cwd":"/tmp","timestamp":"2026-10-12T10:00:00.000Z"}}"#,
            #"{"type":"response_item","timestamp":"2026-10-12T10:01:00.000Z","payload":{"type":"message","id":"u1","role":"user","content":[{"type":"input_text","text":"過去の依頼"}]}}"#,
        ].joined(separator: "\n").write(to: rollout, atomically: true, encoding: .utf8)

        let transport = ScriptedAppServerTransport()
        let client = CodexStructuredAgentClient(client: CodexAppServerClient(transport: transport))
        let dashboard = dashboard([client], kind: .codex, codexHome: codexHome)
        let project = try #require(dashboard.projects.first)
        let settings = CodexAppServerSessionSettings(
            selectedModel: "gpt-5-codex",
            selectedEffort: "high",
            selectedPermissionProfile: ":read-only",
            isPlanMode: false
        )
        let request = NewChatLaunchRequest(
            projectID: project.id,
            agentRef: .builtin(.codex),
            settings: settings,
            usesWorktree: false,
            text: "",
            attachments: [],
            resumeHistoryID: historyID
        )

        let id = try await dashboard.launchNewChat(request)
        let vm = try #require(dashboard.sessionNode(id: id)?.appServer)
        #expect(vm.agentRef == .builtin(.codex))
        #expect(vm.rawWorkspacePath == project.directoryPath)
        let resume = try #require(transport.capturedParams(for: "thread/resume").first)
        #expect(resume["threadId"] as? String == historyID)
        #expect(resume["cwd"] as? String == project.directoryPath)
        #expect(resume["model"] as? String == settings.selectedModel)
        #expect(transport.sentMethods().contains("thread/start") == false)
        #expect(transport.sentMethods().contains("turn/start") == false)
        let applied = try #require(transport.capturedParams(for: "thread/settings/update").last)
        #expect(applied["effort"] as? String == settings.selectedEffort)
        #expect(applied["permissions"] as? String == settings.selectedPermissionProfile)
        await dashboard.removeSession(id)
    }

    @Test func AC4_sameDirectoryAllowsSecondNewChatWithoutConfirmation() async throws {
        let firstClient = LaunchClient()
        let secondClient = LaunchClient()
        let dashboard = dashboard([firstClient, secondClient])
        let launch = request(dashboard)

        let firstID = try await dashboard.launchNewChat(launch)
        let secondID = try await dashboard.launchNewChat(launch)

        #expect(firstID != secondID)
        #expect(dashboard.sessionNodes.count == 2)
        #expect(dashboard.sessionNode(id: firstID)?.appServer?.rawWorkspacePath == "/tmp")
        #expect(dashboard.sessionNode(id: secondID)?.appServer?.rawWorkspacePath == "/tmp")
        await dashboard.removeSession(firstID)
        await dashboard.removeSession(secondID)
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

    @Test func launchNewChatUsesExistingWorktreeOverride() async throws {
        let client = LaunchClient()
        let dashboard = dashboard([client])
        let worktree = FileManager.default.temporaryDirectory.appendingPathComponent("phlox-worktree-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        defer {
            do { try FileManager.default.removeItem(at: worktree) }
            catch { Issue.record("一時 worktree の後片付けに失敗: \(error)") }
        }
        let base = request(dashboard)
        let launch = NewChatLaunchRequest(projectID: base.projectID, agentRef: base.agentRef, settings: base.settings,
            usesWorktree: false, text: base.text, attachments: base.attachments,
            workingDirectoryOverride: worktree.path)

        let id = try await dashboard.launchNewChat(launch)

        #expect(dashboard.sessionNode(id: id)?.appServer?.rawWorkspacePath == worktree.path)
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
        let launchError = try #require(vm.transcript.first { $0.id == "launch-error-\(id.rawValue)" })
        if case .error(_, let message, _) = launchError {
            #expect(message.contains("最初のメッセージは送っていません"))
            #expect(message.contains("本文を入力欄に戻しました"))
        } else {
            Issue.record("launch failure explanation is missing")
        }
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
        let base = request(dashboard)
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("new-chat-restart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let launchRequest = NewChatLaunchRequest(
            projectID: base.projectID,
            agentRef: base.agentRef,
            settings: base.settings,
            usesWorktree: false,
            text: base.text,
            attachments: base.attachments,
            workingDirectoryOverride: workspace.path
        )
        let id = try await dashboard.launchNewChat(launchRequest)
        let old = try #require(dashboard.sessionNode(id: id)?.appServer)
        old.draft = "edited text"
        let attachments = [ComposerAttachment(data: Data([2]), mediaType: "image/png")]
        old.attachmentStore.restore(attachments)
        let router = AppRouter()
        router.showNewChat(projectID: base.projectID)
        let newID = try await dashboard.restartNewChat(id) { newID in
            router.completeNewChat(sessionID: newID, projectID: base.projectID)
        }
        let vm = try #require(dashboard.sessionNode(id: newID)?.appServer)
        #expect(newID != id)
        #expect(dashboard.sessionNodes.count == 1)
        #expect(dashboard.sessionNode(id: id) == nil)
        #expect(router.selectedSession == newID)
        #expect(router.tabs.layout(for: base.projectID).selected == .chat(newID))
        #expect(vm.rawWorkspacePath == workspace.path)
        #expect(vm.agentRef == launchRequest.agentRef)
        #expect(vm.draft == "edited text")
        #expect(vm.attachmentStore.attachments == attachments)
        #expect(await replacement.starts == 1)
        #expect(await replacement.inputs.isEmpty)
        let settings = try #require(await replacement.settings)
        #expect(settings.0 == launchRequest.settings.selectedModel)
        #expect(settings.1 == launchRequest.settings.selectedPermissionProfile)
        #expect(settings.2 == launchRequest.settings.selectedEffort)
        await dashboard.removeSession(newID)
    }

    @Test func restartPreservesEditsMadeWhileStartingAndRejectsSecondRestart() async throws {
        let failed = LaunchClient(failsStart: true)
        let replacement = LaunchClient(holdsStart: true)
        let unexpected = LaunchClient()
        let dashboard = dashboard([failed, replacement, unexpected])
        let id = try await dashboard.launchNewChat(request(dashboard))
        var replacementID: SessionID?
        let task = Task { try await dashboard.restartNewChat(id) { replacementID = $0 } }
        for _ in 0..<100 {
            if await replacement.starts == 1 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let newID = try #require(replacementID)
        let vm = try #require(dashboard.sessionNode(id: newID)?.appServer)
        vm.draft = "edited while starting"
        let image = ComposerAttachment(data: Data([3]), mediaType: "image/png")
        vm.attachmentStore.restore([image])
        await #expect(throws: CancellationError.self) {
            try await dashboard.restartNewChat(id)
        }
        await replacement.releaseStart()
        #expect(try await task.value == newID)
        #expect(vm.draft == "edited while starting")
        #expect(vm.attachmentStore.attachments == [image])
        #expect(dashboard.sessionNodes.count == 1)
        #expect(await unexpected.starts == 0)
        #expect(await replacement.inputs.isEmpty)
        for node in dashboard.sessionNodes { await dashboard.removeSession(node.id) }
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
