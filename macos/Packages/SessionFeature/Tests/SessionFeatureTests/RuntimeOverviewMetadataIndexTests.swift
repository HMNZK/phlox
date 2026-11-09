import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import SwiftUI
import Testing
@testable import SessionFeature

@Suite @MainActor
struct RuntimeOverviewMetadataIndexTests {
    @Test func sourceAppendBodyUpdatesAndQuestionResolutionMatchTheRawScan() async throws {
        let client = MetadataClient()
        defer { client.finish() }
        let (source, _) = await restored(client, [input("u0"), command("work")])
        try #require(!source.isRuntimeProjection)
        _ = try checkOverview(source)
        client.yield(.turnStarted)
        client.yield(.agentMessageDelta(itemId: "reply", "最初の返答"))
        try await wait { source.transcript.contains { $0.id == "reply" } }
        let appended = try checkOverview(source)
        client.yield(.agentMessageDelta(itemId: "reply", "を更新"))
        client.yield(.userQuestionRequested(requestId: "ask", questions: [question("続けますか")]))
        try await wait { source.transcript.contains { $0.id == "question-ask" } }
        let pending = try checkOverview(source)
        client.yield(.userQuestionResolved(requestId: "ask", outcome: .answered(answers: ["続けますか": ["はい"]])))
        try await wait { questionState(source, "question-ask") == .answered }
        let answered = try checkOverview(source)

        #expect(appended.lastAgentText?.text == "最初の返答")
        #expect(pending.lastAgentText?.text == "最初の返答を更新")
        #expect(pending.pendingInteractionCount == 1)
        #expect(answered.pendingInteractionCount == 0)
        #expect(answered.pendingIdentity != pending.pendingIdentity)
    }

    @Test func hiddenQuestionsAndApprovalItemChangesRemainInTheIdentityHash() async throws {
        let client = MetadataClient()
        defer { client.finish() }
        let broker = ChatApprovalBroker()
        defer { Task { await broker.cancelAll() } }
        let (source, _) = await restored(client, [input("u0"), command("work")], broker: broker)
        try #require(!source.isRuntimeProjection)
        enqueueQuestions(client, count: 18)
        try await wait { rawPendingCount(source) == 18 }
        let before = try checkOverview(source)
        client.yield(.userQuestionResolved(requestId: "q-17", outcome: .answered(answers: [:])))
        try await wait { questionState(source, "question-q-17") == .answered }
        let hiddenResolved = try checkOverview(source)
        let request = try JSONDecoder().decode(CommandExecutionApprovalRequest.self, from: Data("""
            {"threadId":"thread","turnId":"turn","itemId":"work","startedAtMs":1,"command":"echo work","reason":"実行を許可","cwd":"/workspace"}
            """.utf8))
        let handler = broker.serverRequestHandler
        let wire = Task { try await handler(.commandExecutionApproval(request)) }
        try await wait { source.pendingApprovals.count == 1 }
        let approvalID = try #require(source.pendingApprovals.first?.id)
        let withApproval = try checkOverview(source)
        client.yield(.commandExecution(itemId: "work", command: nil, outputDelta: "更新"))
        try await wait { commandOutput(source, "work") == "出力更新" }
        let relatedChanged = try checkOverview(source)

        #expect(before.pendingInteractionCount == 18)
        #expect(hiddenResolved.pendingInteractionCount == 17)
        #expect(before.pendingInteractions == hiddenResolved.pendingInteractions)
        #expect(before.pendingIdentity != hiddenResolved.pendingIdentity)
        #expect(withApproval.pendingInteractionCount == 18)
        #expect(withApproval.pendingInteractions.count == 16)
        guard case .approval(let id, _, _, _) = withApproval.pendingInteractions.first else {
            Issue.record("承認が質問より先にありません"); return
        }
        #expect(id == approvalID)
        #expect(relatedChanged.pendingInteractions == withApproval.pendingInteractions)
        #expect(relatedChanged.pendingIdentity != withApproval.pendingIdentity)
        await source.respondToApproval(approvalID, decision: .decline)
        #expect(try await wire.value["decision"]?.stringValue == "decline")
    }

    @Test func sourceQuestionSelectionKeepsSynchronousPriorityAndTheAsyncRequestedDate() async throws {
        let client = MetadataClient()
        defer { client.finish() }
        let asyncID = try #require(CodexAsyncQuestionID(threadID: "thread", turnID: "turn", itemID: "async"))
        let (source, _) = await restored(client, [input("u0"),
            pending("qa", requestID: asyncID.requestID, text: "非同期", timestamp: at(10)),
            pending("permission", requestID: "permission", text: "許可", timestamp: at(20), permission: true),
            pending("sync", requestID: "sync", text: "同期", timestamp: at(30))])
        try #require(!source.isRuntimeProjection)
        _ = try checkOverview(source)
        #expect(source.pendingAsyncQuestionDate == nil)
        client.yield(.userQuestionResolved(requestId: "sync", outcome: .expired))
        try await wait { questionState(source, "sync") == .expired }
        let asynchronous = try checkOverview(source)

        #expect(source.pendingAsyncQuestionDate == at(10))
        #expect(source.displayStatus == .awaitingUserQuestion)
        #expect(asynchronous.pendingInteractionCount == 2)
        #expect(source.makeRuntimeOverview().displayStatusEnteredAt == at(10))
    }

    @Test func sourcePermissionQuestionKeepsItsApprovalDisplayStatus() async throws {
        let client = MetadataClient()
        defer { client.finish() }
        let (source, _) = await restored(client, [input("u0")])
        try #require(!source.isRuntimeProjection)
        _ = try checkOverview(source)
        client.yield(.userQuestionRequested(requestId: "permission", questions: [question("実行しますか", permission: true)]))
        try await wait { source.status == .awaitingUserQuestion }
        let overview = try checkOverview(source)

        #expect(source.displayStatus == .awaitingApproval(prompt: "実行しますか"))
        guard case .question(_, _, let isPermission, _) = overview.pendingInteractions.first else {
            Issue.record("許可質問がありません"); return
        }
        #expect(isPermission)
    }

    @Test func aSourceWithoutAgentMessagesKeepsAnEmptyPreviewAcrossWorkUpdates() async throws {
        let client = MetadataClient()
        defer { client.finish() }
        let (source, _) = await restored(client, [input("u0")] + (0..<128).map { command("work-\($0)") })
        try #require(!source.isRuntimeProjection)
        let before = try checkOverview(source)
        client.yield(.turnStarted)
        client.yield(.commandExecution(itemId: "work-new", command: "echo new", outputDelta: "開始"))
        try await wait { source.transcript.contains { $0.id == "work-new" } }
        _ = try checkOverview(source)
        client.yield(.commandExecution(itemId: "work-new", command: nil, outputDelta: "更新"))
        try await wait { commandOutput(source, "work-new") == "開始更新" }
        let after = try checkOverview(source)

        #expect(before.lastAgentText == nil)
        #expect(after.lastAgentText == nil)
        #expect(after.pendingInteractionCount == 0)
        #expect(source.displayStatus == .running)
    }

    @Test func sourcePreviewPreservesTheBoundedWhitespaceRuleAndFallsBackAfterRestore() async throws {
        let client = MetadataClient()
        defer { client.finish() }
        let (source, store) = await restored(client, [input("u0"),
            .agentMessage(id: "old", text: "以前の返答", timestamp: at(1)),
            .agentMessage(id: "leading-space", text: String(repeating: " ", count: 600) + "末尾", timestamp: at(2))])
        try #require(!source.isRuntimeProjection)
        let before = try checkOverview(source)
        client.yield(.agentMessageDelta(itemId: "tail", "最新"))
        try await wait { source.transcript.contains { $0.id == "tail" } }
        let appended = try checkOverview(source)
        client.yield(.agentMessageDelta(itemId: "tail", "の返答"))
        try await wait { agentText(source, "tail") == "最新の返答" }
        let updated = try checkOverview(source)
        await store.set([input("u0"), .agentMessage(id: "old", text: "以前の返答", timestamp: at(1)),
            .agentMessage(id: "tail", text: "  \n  ", timestamp: at(3))])
        await source.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        let restored = try checkOverview(source)

        #expect(before.lastAgentText?.text == "以前の返答")
        #expect(appended.lastAgentText?.text == "最新")
        #expect(updated.lastAgentText?.text == "最新の返答")
        #expect(restored.lastAgentText?.text == "以前の返答")
    }

    @Test func sourceTrimAndSameLengthRestoreRebuildTheirPendingPositions() async throws {
        let client = MetadataClient()
        defer { client.finish() }
        let (source, store) = await restored(client, [input("u0"),
            .agentMessage(id: "old", text: "古い返答", timestamp: at(1)), input("u1"),
            pending("old-question", requestID: "old-question", text: "古い質問", timestamp: at(3))])
        try #require(!source.isRuntimeProjection)
        let before = try checkOverview(source)
        let reverted = await source.revert(toUserMessageID: "u1")
        let trimmed = try checkOverview(source)
        await store.set([input("u2"), pending("new-question", requestID: "new-question", text: "新しい質問", timestamp: at(4))])
        await source.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        let restored = try checkOverview(source)

        #expect(before.pendingInteractionCount == 1)
        #expect(reverted == "入力 u1")
        #expect(trimmed.pendingInteractionCount == 0)
        #expect(source.transcript.count == 2)
        #expect(restored.pendingInteractionCount == 1)
        guard case .question(let index, let preview, _, _) = restored.pendingInteractions.first else {
            Issue.record("復元した質問がありません"); return
        }
        #expect(index == 1)
        #expect(preview.text == "新しい質問")
    }

    @Test func duplicateIDsKeepBothPositionsAndTheExactLegacyIdentityHash() throws {
        var snapshot = snapshot([pending("dup", requestID: "first", text: "最初", timestamp: at(1)),
            pending("dup", requestID: "second", text: "次", timestamp: at(2))])
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let before = try checkOverview(source)
        snapshot.transcript = [.agentMessage(id: "one", text: "新しい返答", timestamp: at(3)), input("two")]
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)
        let replaced = try checkOverview(source)
        snapshot.executionID = UUID(uuidString: "D140D0A4-1260-434D-B99A-631ED1B32FF5")!
        snapshot.transcript = [pending("new", requestID: "new", text: "新実行の質問", timestamp: at(4)), input("two")]
        snapshot.transcriptRevision = 1
        try source.applyRuntimeSnapshot(snapshot)
        let newExecution = try checkOverview(source)

        #expect(before.pendingInteractionCount == 2)
        #expect(before.pendingIdentity == "0b8020e72a660b045dbfec695b408ae09b21ff1babf33d87cb28f756ea525b80")
        #expect(replaced.pendingInteractionCount == 0)
        #expect(replaced.lastAgentText?.text == "新しい返答")
        #expect(newExecution.pendingInteractionCount == 1)
        #expect(newExecution.lastAgentText == nil)
    }

    @Test func giantAgentTextOnlyContributesItsOriginalBoundedPreview() async throws {
        let client = MetadataClient()
        defer { client.finish() }
        let (source, _) = await restored(client, [input("u0"),
            .agentMessage(id: "giant", text: String(repeating: "x", count: 1_000_000), timestamp: at(1))])
        try #require(!source.isRuntimeProjection)
        let metadata = try checkOverview(source)
        let encoded = try JSONEncoder().encode(source.makeRuntimeOverview())

        #expect(metadata.lastAgentText?.text.utf8.count == 512)
        #expect(metadata.lastAgentText?.truncated == true)
        #expect(encoded.count < 16_384)
    }

    @Test func projectionPendingOverlayAndRawPrependKeepTheirPreviousSelectionOrder() async throws {
        let asyncID = try #require(CodexAsyncQuestionID(threadID: "thread", turnID: "turn", itemID: "async"))
        let source = ChatSessionViewModel(projection: snapshot([
            pending("async", requestID: asyncID.requestID, text: "非同期", timestamp: at(1)),
            pending("sync", requestID: "sync", text: "同期", timestamp: at(2))]
            + (0..<60).map { command("work-\($0)") })) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }
        try #require(projected.isRuntimeProjection)
        try await projected.refreshRuntimeContent()
        _ = try checkOverview(projected)
        let selected = ChatReplyArea<EmptyView>.pendingQuestionItem(in: projected.replyItems)
        try await projected.loadEarlierRuntimeContent()
        let after = try checkOverview(projected)

        guard case .userQuestion(_, let requestID, _, _, _, _) = selected else {
            Issue.record("projectionの質問候補がありません"); return
        }
        #expect(requestID == "sync")
        #expect(projected.pendingAsyncQuestionDate == nil)
        #expect(after.pendingInteractionCount == 2)
    }

    private func checkOverview(_ source: ChatSessionViewModel) throws -> SessionRuntimeSessionOverview.ChatState {
        let overview = source.makeRuntimeOverview()
        guard case .chat(let metadata) = overview.kind else { throw MetadataError.unexpected }
        let expected = rawMetadata(source.makeRuntimeSnapshot())
        #expect(metadata.pendingInteractionCount == expected.count)
        #expect(metadata.pendingInteractions == expected.interactions)
        #expect(metadata.lastAgentText == expected.preview)
        if !source.isRuntimeProjection {
            let expectedStatus = rawDisplayStatus(source)
            #expect(overview.displayStatus == expectedStatus.status)
            #expect(source.pendingAsyncQuestionDate == expectedStatus.date)
            if let date = expectedStatus.date, expectedStatus.status == .awaitingUserQuestion {
                #expect(overview.displayStatusEnteredAt == date)
            }
        }
        return metadata
    }

    private func rawMetadata(_ snapshot: SessionRuntimeChatSnapshot)
        -> (count: Int, interactions: [SessionRuntimePendingInteractionOverview], preview: SessionRuntimeTextPreview?) {
        var interactions = snapshot.pendingApprovals.prefix(16).map {
            SessionRuntimePendingInteractionOverview.approval(id: $0.id, prompt: .init($0.prompt), requiresDetail: true, requestedAt: $0.requestedAt)
        }
        var count = snapshot.pendingApprovals.count
        for (index, item) in snapshot.transcript.enumerated() {
            guard case .userQuestion(_, _, let questions, _, .pending, let timestamp) = item else { continue }
            count += 1
            if interactions.count < 16 {
                interactions.append(.question(index: index, prompt: .init(questions.first?.question ?? ""),
                    isToolPermission: questions.count == 1 && questions.first?.permission != nil, requestedAt: timestamp))
            }
        }
        var preview: SessionRuntimeTextPreview?
        for item in snapshot.transcript.reversed() {
            guard case .agentMessage(_, let text, _) = item else { continue }
            let candidate = SessionRuntimeTextPreview(text)
            if !candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { preview = candidate; break }
        }
        return (count, interactions, preview)
    }

    private func rawDisplayStatus(_ source: ChatSessionViewModel) -> (status: SessionStatus, date: Date?) {
        let item = ChatReplyArea<EmptyView>.pendingQuestionItem(in: source.transcript)
        let date: Date?
        if case .userQuestion(_, let requestID, _, _, .pending, let timestamp) = item,
           CodexAsyncQuestionID.isAsyncRequest(requestID) { date = timestamp }
        else { date = nil }
        let base = SessionDisplayStatus.resolve(rawStatus: source.status, isProcessing: source.isProcessing)
        switch base {
        case .idle, .running, .completed:
            if date != nil { return (.awaitingUserQuestion, date) }
        default: break
        }
        guard base == .awaitingUserQuestion else { return (base, date) }
        var prompt: String?
        for item in source.transcript.reversed() {
            guard case .userQuestion(_, _, let questions, _, .pending, _) = item else { continue }
            guard questions.count == 1 && questions.first?.permission != nil else { return (base, date) }
            prompt = prompt ?? questions.first?.question
        }
        return (prompt.map { .awaitingApproval(prompt: $0) } ?? base, date)
    }

    private func restored(_ client: MetadataClient, _ items: [ChatItem], broker: ChatApprovalBroker = ChatApprovalBroker()) async -> (ChatSessionViewModel, MetadataStore) {
        let store = MetadataStore(items)
        let source = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.claudeCode), client: client,
            approvalBroker: broker, workingDirectory: "/workspace", transcriptStore: store)
        source.userNotificationGate = { _ in false }
        await source.restore(threadId: "thread", approvalPolicy: .named("never"), sandbox: .named("workspace-write"))
        return (source, store)
    }

    private func snapshot(_ items: [ChatItem]) -> SessionRuntimeChatSnapshot {
        var value = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: at(0), agentRef: .builtin(.codex), workingDirectory: "/workspace")
        value.status = .idle
        value.transcript = items
        value.transcriptRevision = 7
        return value
    }
    private func input(_ id: String) -> ChatItem { .userMessage(id: id, text: "入力 \(id)", timestamp: at(0), attachments: []) }
    private func command(_ id: String) -> ChatItem { .commandExecution(id: id, command: "echo work", output: "出力", timestamp: at(1)) }
    private func question(_ text: String, permission: Bool = false) -> ChatUserQuestion {
        .init(question: text, header: "確認", options: [], multiSelect: false,
            permission: permission ? .init(toolName: "Bash", detail: "許可の詳細") : nil)
    }
    private func pending(_ id: String, requestID: String, text: String, timestamp: Date, permission: Bool = false) -> ChatItem {
        .userQuestion(id: id, requestId: requestID, questions: [question(text, permission: permission)], answers: nil, state: .pending, timestamp: timestamp)
    }
    private func enqueueQuestions(_ client: MetadataClient, count: Int) {
        for index in 0..<count { client.yield(.userQuestionRequested(requestId: "q-\(index)", questions: [question("質問\(index)")])) }
    }
    private func rawPendingCount(_ source: ChatSessionViewModel) -> Int {
        source.transcript.filter { if case .userQuestion(_, _, _, _, .pending, _) = $0 { return true }; return false }.count
    }
    private func questionState(_ source: ChatSessionViewModel, _ id: String) -> ChatUserQuestionState? {
        guard case .userQuestion(_, _, _, _, let state, _) = source.transcript.first(where: { $0.id == id }) else { return nil }
        return state
    }
    private func commandOutput(_ source: ChatSessionViewModel, _ id: String) -> String? {
        guard case .commandExecution(_, _, let output, _, _, _) = source.transcript.first(where: { $0.id == id }) else { return nil }; return output
    }
    private func agentText(_ source: ChatSessionViewModel, _ id: String) -> String? {
        guard case .agentMessage(_, let text, _) = source.transcript.first(where: { $0.id == id }) else { return nil }; return text
    }
    private func wait(_ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !predicate() { guard ContinuousClock.now < deadline else { throw MetadataError.timedOut }; await Task.yield() }
    }
    private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_000 + seconds) }
    private enum MetadataError: Error { case unexpected, timedOut }
}

private final class MetadataClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    init() { (events, continuation) = AsyncStream.makeStream() }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func finish() { continuation.finish() }
    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

private actor MetadataStore: TranscriptStore {
    private var items: [ChatItem]
    init(_ items: [ChatItem]) { self.items = items }
    func set(_ items: [ChatItem]) { self.items = items }
    func loadTranscript(for sessionID: SessionID) async throws -> [ChatItem] { items }
    func upsertTranscriptItems(_ items: [ChatItem], for sessionID: SessionID) async throws {}
    func replaceTranscript(for sessionID: SessionID, with items: [ChatItem]) async throws {}
}
