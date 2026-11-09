import AgentDomain
import CodexAppServerKit
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite @MainActor struct RuntimeChatPresentationTests {
    @Test func viewedChatRestoresHistorySkillAndSubAgentWithoutFullSnapshot() async throws {
        var snapshot = baseSnapshot()
        snapshot.hasHistoryProvider = true
        snapshot.historyEntries = [ClaudeSessionHistoryEntry(sessionID: "history-42",
            preview: "前回の作業", firstUserAt: .distantPast,
            lastModified: Date(timeIntervalSince1970: 1_700_000_000), gitBranch: "feature/login",
            fileURL: URL(fileURLWithPath: "/work/history-42.jsonl"))]
        snapshot.historySummaries = ["history-42": ChatHistorySummary(items: [
            .agentMessage(id: "answer-42", text: "ログインを修正", timestamp: .distantPast),
        ])]
        snapshot.skillSelection = SessionRuntimeSkillSnapshot(skills: [
            SkillMetadata(description: "コードを調査する", enabled: true, name: "inspect",
                path: "/work/.agents/skills/inspect/SKILL.md", scope: .repo),
        ], fingerprints: ["/work/.agents/skills/inspect/SKILL.md": "fingerprint-42"],
            isLoading: false, isStale: false, errorMessage: nil)
        var subAgents = SessionRuntimeSubAgentSnapshot()
        subAgents.subAgents = [SubAgentRef(id: "child-42", subagentType: "reviewer",
            description: "認証を確認", status: .running,
            startedAt: Date(timeIntervalSince1970: 1_700_000_001))]
        subAgents.stoppableIDs = ["child-42"]
        snapshot.subAgents = subAgents
        var codexChildren = CodexSubAgentState(parentThreadId: "parent-42")
        codexChildren.apply(.available(children: [CodexChildThread(id: "codex-child-42",
            parentThreadId: "parent-42", activeTurnId: "turn-42", status: "running",
            summary: "レビュー中", taskName: "レビュー")]))
        snapshot.codexSubAgents = codexChildren
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }

        try await projected.refreshRuntimeContent()

        #expect(projected.shouldOfferHistoryStart)
        #expect(projected.historyEntries.first?.sessionID == "history-42")
        #expect(projected.historySummaries["history-42"]?.lastMessage == "ログインを修正")
        #expect(projected.codexSkillSelectionState?.skills.first?.name == "inspect")
        #expect(projected.codexSkillSelectionState?.skills.first?.path == "/work/.agents/skills/inspect/SKILL.md")
        #expect(projected.stripSubAgents.first?.id == "child-42")
        #expect(projected.subAgentStopState(forDisplayID: "child-42") == .available)
        #expect(projected.stripSubAgents.contains { $0.id == CodexSubAgentPresentation.displayID(for: "codex-child-42") })
    }

    @Test func hugeDisplayTextIsBoundedWhileHistoryIdentityRemainsUsable() async throws {
        var snapshot = baseSnapshot()
        snapshot.hasHistoryProvider = true
        snapshot.historyEntries = [ClaudeSessionHistoryEntry(sessionID: "history-huge",
            preview: String(repeating: "長", count: 3_000_000), firstUserAt: .distantPast,
            lastModified: Date(timeIntervalSince1970: 1_700_000_002), gitBranch: nil,
            fileURL: URL(fileURLWithPath: "/work/history-huge.jsonl"))]
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }

        let first = try source.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatPresentation(offset: 0, digest: nil)))
        try await projected.refreshRuntimeContent()

        #expect(try JSONEncoder().encode(first).count <= SessionRuntimeContentLimits.maximumResponseBytes)
        #expect(projected.historyEntries.first?.sessionID == "history-huge")
        #expect(projected.historyEntries.first?.fileURL.path == "/work/history-huge.jsonl")
        #expect(projected.historyEntries.first?.preview.hasSuffix("…") == true)
        #expect((projected.historyEntries.first?.preview.utf8.count ?? 0) <= 520)
    }

    @Test func largeActionableListArrivesInBoundedChunksWithoutDroppedOptions() async throws {
        var snapshot = baseSnapshot()
        let command = "/" + String(repeating: "x", count: 1_000)
        snapshot.availableSlashCommands = Array(repeating: command, count: 6_000)
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }

        let first = try source.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatPresentation(offset: 0, digest: nil)))
        try await projected.refreshRuntimeContent()

        guard case .presentationChunk(let chunk) = first else {
            Issue.record("補助情報の分割応答がありません")
            return
        }
        #expect(chunk.totalBytes > SessionRuntimeContentLimits.maximumResponseBytes)
        #expect(try JSONEncoder().encode(first).count <= SessionRuntimeContentLimits.maximumResponseBytes)
        #expect(projected.availableSlashCommands?.count == 6_000)
        #expect(projected.availableSlashCommands?.first == command)
    }

    @Test func inputRecallLoadsOlderPagesBeforeChoosingFromHistory() async throws {
        var snapshot = baseSnapshot()
        snapshot.transcript = [.userMessage(id: "old-user", text: "oldest-message", timestamp: .distantPast)]
            + (0..<75).map { .agentMessage(id: "agent-\($0)", text: "reply-\($0)",
                timestamp: Date(timeIntervalSince1970: Double($0))) }
        snapshot.transcriptRevision = 1
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        let pageGate = PresentationPageGate()
        projected.runtimeContentLoader = { request in
            if case .chatBefore = request.target { await pageGate.wait() }
            return try source.runtimeContent(for: request)
        }
        try await projected.refreshRuntimeContent()
        #expect(projected.hasMoreRuntimeTranscript)
        #expect(projected.recallInputHistory(.older))
        #expect(projected.draft.isEmpty)
        pageGate.release()
        #expect(try await waitUntil {
            projected.hasCompleteRuntimeTranscript && projected.draft == "oldest-message"
        })
    }

    @Test func inputRecallReadsStableOlderPageWhileAgentKeepsStreaming() async throws {
        var snapshot = baseSnapshot()
        snapshot.transcript = [.userMessage(id: "old-user", text: "oldest-message", timestamp: .distantPast)]
            + (0..<75).map { .agentMessage(id: "agent-\($0)", text: "reply-\($0)",
                timestamp: Date(timeIntervalSince1970: Double($0))) }
            + [.userMessage(id: "recent-user", text: "recent-message", timestamp: .distantPast)]
        snapshot.transcriptRevision = 1
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        var streaming = snapshot
        streaming.transcript[75] = .agentMessage(id: "agent-74", text: "reply-74 continued",
            timestamp: Date(timeIntervalSince1970: 74))
        streaming.transcriptRevision = 2
        let streamingSource = ChatSessionViewModel(projection: streaming) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        let pageGate = PresentationPageGate()
        projected.runtimeContentLoader = { request in
            if case .chatBefore = request.target {
                await pageGate.wait()
                return try streamingSource.runtimeContent(for: request)
            }
            return try source.runtimeContent(for: request)
        }
        try await projected.refreshRuntimeContent()
        #expect(projected.recallInputHistory(.older))
        #expect(projected.draft == "recent-message")
        #expect(projected.recallInputHistory(.older))
        try projected.applyRuntimeOverview(streamingSource.makeRuntimeOverview())
        pageGate.release()

        #expect(try await waitUntil { projected.draft == "oldest-message" })
        #expect(!projected.hasCompleteRuntimeTranscript)
        #expect(projected.recallInputHistory(.newer))
        #expect(projected.draft == "recent-message")
        #expect(projected.recallInputHistory(.newer))
        #expect(projected.draft.isEmpty)
    }

    @Test func inputRecallReportsInvalidatedOlderPage() async throws {
        var snapshot = baseSnapshot()
        snapshot.transcript = [.userMessage(id: "old-user", text: "oldest-message", timestamp: .distantPast)]
            + (0..<75).map { .agentMessage(id: "agent-\($0)", text: "reply-\($0)",
                timestamp: Date(timeIntervalSince1970: Double($0))) }
        snapshot.transcriptRevision = 1
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        var revised = snapshot
        revised.transcript[1] = .agentMessage(id: "agent-0", text: "changed-prefix", timestamp: .distantPast)
        revised.transcriptRevision = 2
        let revisedSource = ChatSessionViewModel(projection: revised) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        let pageGate = PresentationPageGate()
        projected.runtimeContentLoader = { request in
            if case .chatBefore = request.target {
                await pageGate.wait()
                return try revisedSource.runtimeContent(for: request)
            }
            return try source.runtimeContent(for: request)
        }
        try await projected.refreshRuntimeContent()
        #expect(projected.recallInputHistory(.older))
        try projected.applyRuntimeOverview(revisedSource.makeRuntimeOverview())
        pageGate.release()

        #expect(try await waitUntil { projected.runtimeConnectionError != nil })
        #expect(projected.draft.isEmpty)
        #expect(!projected.transcript.contains { $0.id == "old-user" })
    }

    private func baseSnapshot() -> SessionRuntimeChatSnapshot {
        var snapshot = SessionRuntimeChatSnapshot(
            id: SessionID(rawValue: UUID(uuidString: "B196A622-8296-47D5-BC0C-290AD41047B6")!),
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            agentRef: .builtin(.codex), workingDirectory: "/work/project")
        snapshot.executionID = UUID(uuidString: "64F310B4-19FA-4C5D-916A-24CB959E969E")!
        return snapshot
    }
}

@MainActor private final class PresentationPageGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor private func waitUntil(_ condition: () -> Bool) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while !condition(), clock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}
