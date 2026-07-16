import AgentDomain
import Foundation
import HookServer
import StructuredChatKit
import Testing
@testable import DashboardFeature
@testable import SessionFeature

@Test @MainActor
func chatHistoryStart_whitebox_environmentProvidersReturnNilForEmptyWorkingDirectory() {
    let (hookStream, _) = AsyncStream<(SessionID, HookEvent)>.makeStream()
    let env = AppEnvironment(
        pty: MockPTYManager(),
        hook: MockHookServer(events: hookStream),
        hookURL: URL(string: "http://127.0.0.1:8080/hook")!,
        claudeSettingsURL: URL(fileURLWithPath: "/tmp/settings.json"),
        hookDispatcherPath: "/tmp/hook-dispatcher.sh",
        claudeBinaryPath: "/usr/bin/claude",
        pathEnvironment: "/usr/bin",
        workspaceDirectory: URL(fileURLWithPath: "/tmp/workspaces"),
        controlURL: URL(string: "http://127.0.0.1:9999")!,
        tokenStore: SessionTokenStore(),
        messages: MockMessageStore(),
        cliPath: "/tmp/phlox"
    )

    let missingCWD = env.claudeSessionHistoryProviders(workingDirectory: nil)
    let emptyCWD = env.claudeSessionHistoryProviders(workingDirectory: "")
    #expect(missingCWD == nil)
    #expect(emptyCWD == nil)
}

@Test @MainActor
func chatHistoryStart_whitebox_startFromHistoryDoesNotPersistToStore() async throws {
    let store = RecordingTranscriptStore()
    let entry = ClaudeSessionHistoryEntry(
        sessionID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        preview: "preview",
        firstUserAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastModified: Date(timeIntervalSince1970: 1_700_000_100),
        gitBranch: "main",
        fileURL: URL(fileURLWithPath: "/tmp/a.jsonl")
    )
    let loaded: [ChatItem] = [
        .userMessage(id: "u1", text: "hello", timestamp: Date()),
    ]
    let client = HistoryStartRecordingClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        transcriptStore: store,
        historyProvider: { [entry] },
        historyTranscriptLoader: { _ in loaded }
    )

    await vm.startFromHistory(entry)

    #expect(vm.transcript == loaded)
    #expect(await store.upsertedBatches.isEmpty)
    #expect(await store.replacedBatches.isEmpty)
    #expect(client.resumedSessionID == entry.sessionID)
}

@Test @MainActor
func chatHistoryStart_whitebox_initReturnsBeforeSlowProviderCompletes() async throws {
    let entry = ClaudeSessionHistoryEntry(
        sessionID: "dddddddd-dddd-4ddd-8ddd-dddddddddddd",
        preview: "preview",
        firstUserAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastModified: Date(timeIntervalSince1970: 1_700_000_100),
        gitBranch: "main",
        fileURL: URL(fileURLWithPath: "/tmp/d.jsonl")
    )
    let start = Date()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: HistoryStartRecordingClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        historyProvider: {
            Thread.sleep(forTimeInterval: 0.5)
            return [entry]
        },
        historyTranscriptLoader: { _ in [] }
    )
    let elapsed = Date().timeIntervalSince(start)
    #expect(elapsed < 0.1)

    try await waitUntil(timeoutNanoseconds: 2_000_000_000) { vm.shouldOfferHistoryStart }
    #expect(vm.shouldOfferHistoryStart)
}

@Test @MainActor
func chatHistoryStart_whitebox_providerCalledAtMostOnceAcrossMultipleReads() async throws {
    let entry = ClaudeSessionHistoryEntry(
        sessionID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        preview: "preview",
        firstUserAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastModified: Date(timeIntervalSince1970: 1_700_000_100),
        gitBranch: "main",
        fileURL: URL(fileURLWithPath: "/tmp/b.jsonl")
    )
    final class CallCounter: @unchecked Sendable {
        var count = 0
    }
    let counter = CallCounter()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: HistoryStartRecordingClient(),
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        historyProvider: {
            counter.count += 1
            return [entry]
        },
        historyTranscriptLoader: { _ in [] }
    )

    try await waitUntil { vm.shouldOfferHistoryStart }

    _ = vm.shouldOfferHistoryStart
    _ = vm.historyEntries
    _ = vm.shouldOfferHistoryStart
    _ = vm.historyEntries.count
    _ = vm.historyEntries.map(\.sessionID)

    #expect(counter.count <= 1)
    #expect(vm.shouldOfferHistoryStart)
}

@Test @MainActor
func chatHistoryStart_whitebox_resumeFailureRestoresHistoryOfferAndErrorStatus() async throws {
    let entry = ClaudeSessionHistoryEntry(
        sessionID: "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
        preview: "preview",
        firstUserAt: Date(timeIntervalSince1970: 1_700_000_000),
        lastModified: Date(timeIntervalSince1970: 1_700_000_100),
        gitBranch: "main",
        fileURL: URL(fileURLWithPath: "/tmp/c.jsonl")
    )
    let loaded: [ChatItem] = [
        .userMessage(id: "u1", text: "hello", timestamp: Date()),
    ]
    let client = FailingHistoryResumeClient()
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work",
        historyProvider: { [entry] },
        historyTranscriptLoader: { _ in loaded }
    )

    try await waitUntil { vm.shouldOfferHistoryStart }

    await vm.startFromHistory(entry)

    #expect(vm.transcript.isEmpty)
    #expect(vm.shouldOfferHistoryStart)
    if case .error = vm.status {
        // expected
    } else {
        Issue.record("Expected .error status after resume failure, got \(vm.status)")
    }
}

private final class FailingHistoryResumeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "resume failed"])
    }
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}

private final class HistoryStartRecordingClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var resumedSessionID: String?

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws { resumedSessionID = sessionRef }
    func interrupt() async throws {}
    func close() async { continuation.finish() }
}
