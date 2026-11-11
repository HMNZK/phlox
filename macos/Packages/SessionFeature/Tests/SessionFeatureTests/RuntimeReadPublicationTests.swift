import AgentDomain
import Foundation
import StructuredChatKit
import Testing
import os
@testable import SessionFeature

@Suite @MainActor struct RuntimeReadPublicationTests {
    @Test(arguments: [false, true])
    func initialAndExplicitNavigationStillPublishProgress(explicit: Bool) async throws {
        let source = source()
        let projected = projection(source)
        if explicit { try await projected.refreshRuntimeChatRead() }
        let target: SessionRuntimeContentRequest.Target = explicit ? .chatReadAround(inputID: "input-0") : .chatReadTail
        let response = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: target))
        let gate = PublicationResponseGate()
        var holdsFirst = true
        projected.runtimeContentLoader = { request in
            if holdsFirst { holdsFirst = false; return await gate.response() }
            return try await source.runtimeChatReadContent(for: request)
        }
        let loading = Task {
            if explicit { try await projected.loadRuntimeChatRead(target: target) }
            else { try await projected.refreshRuntimeChatRead() }
        }
        await gate.waitForRequest()
        #expect(projected.runtimeChatRead.isLoading)
        #expect(projected.runtimeChatRead.page == nil || explicit)

        gate.release(response)
        try await loading.value

        #expect(!projected.runtimeChatRead.isLoading)
        #expect(projected.runtimeChatRead.page?.blocks.first?.id == (explicit ? "input-0" : "input-78"))
    }

    @Test func aBackgroundReadWaitsForHistoryBeforePublishingTheNewPageAndPreviews() async throws {
        let source = source()
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        try update(source)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        let history = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .inputHistory(before: nil)))
        let gate = PublicationResponseGate()
        projected.runtimeContentLoader = { request in
            if case .inputHistory = request.target { return await gate.response() }
            return try await source.runtimeChatReadContent(for: request)
        }
        let invalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = projected.runtimeChatRead.page
            _ = projected.runtimeChatRead.history
            _ = projected.runtimeChatRead.latestHistory
        } onChange: { invalidated.withLock { $0 = true } }
        let refreshing = Task { try await projected.refreshRuntimeChatRead() }
        await gate.waitForRequest()

        #expect(!invalidated.withLock { $0 })
        #expect(!projected.runtimeChatRead.isLoading)
        #expect(!projected.runtimeChatRead.isLoadingHistory)
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 7)
        #expect(lastInputText(projected) == "依頼 127")
        #expect(projected.runtimeChatRead.latestEntries.last?.text == "依頼 127")
        gate.release(history)
        try await refreshing.value

        #expect(invalidated.withLock { $0 })
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(lastInputText(projected) == "更新した依頼")
        #expect(projected.runtimeChatRead.history?.entries.last?.preview.displayText == "更新した依頼")
        #expect(projected.runtimeChatRead.latestEntries.last?.text == "更新した依頼")
    }

    @Test(arguments: [false, true])
    func aWaitingBackgroundHistoryCannotOverwriteANewerManualRead(manualLatest: Bool) async throws {
        let source = source()
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let oldHistory = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .inputHistory(before: nil)))
        try update(source)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        let timeline = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .chatReadTail))
        let gate = PublicationResponseGate()
        var holdsFirstTail = true
        var latestRequests = 0
        projected.runtimeContentLoader = { request in
            if holdsFirstTail, case .chatReadTail = request.target {
                holdsFirstTail = false
                return await gate.response()
            }
            if manualLatest, case .inputHistory(let cursor) = request.target, cursor == nil {
                latestRequests += 1
                // A late coherent old response must not replace the completed manual read.
                if latestRequests > 1 { return oldHistory }
            }
            return try await source.runtimeChatReadContent(for: request)
        }
        let refreshing = Task { try await projected.refreshRuntimeChatRead() }
        await gate.waitForRequest()

        let release = Task { gate.release(timeline) }
        try await projected.loadRuntimeInputHistory(earlier: !manualLatest)
        await release.value
        try await refreshing.value

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(lastInputText(projected) == "更新した依頼")
        #expect(projected.runtimeChatRead.history?.entries.first?.id == (manualLatest ? "input-78" : "input-28"))
        #expect(projected.runtimeChatRead.history?.entries.last?.id == (manualLatest ? "input-127" : "input-77"))
        #expect(projected.runtimeChatRead.latestEntries.last?.text == "更新した依頼")
        #expect(!projected.runtimeChatRead.isLoadingHistory)
    }

    @Test func aHistoryFailurePublishesTheSuccessfulPageAndCanRetryWithoutLosingOldHistory() async throws {
        let source = source()
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let oldHistory = projected.runtimeChatRead.history
        let oldLatest = projected.runtimeChatRead.latestHistory
        try update(source)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        projected.runtimeContentLoader = { request in
            if case .inputHistory = request.target { throw URLError(.networkConnectionLost) }
            return try await source.runtimeChatReadContent(for: request)
        }

        await #expect(throws: URLError.self) { try await projected.refreshRuntimeChatRead() }

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(lastInputText(projected) == "更新した依頼")
        #expect(projected.runtimeChatRead.history == oldHistory)
        #expect(projected.runtimeChatRead.latestHistory == oldLatest)
        #expect(projected.runtimeChatRead.historyError != nil)
        #expect(projected.runtimeChatRead.error == nil)
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }
        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.history?.entries.last?.preview.displayText == "更新した依頼")
        #expect(projected.runtimeChatRead.latestEntries.last?.text == "更新した依頼")
        #expect(projected.runtimeChatRead.historyError == nil)
    }

    @Test func anUnchangedSilentHistoryReadDoesNotInvalidateDisplayedContent() async throws {
        let source = source()
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let invalidated = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = projected.runtimeChatRead.history } onChange: { invalidated.withLock { $0 = true } }

        try await projected.loadRuntimeInputHistory(refreshLatest: true)

        #expect(!invalidated.withLock { $0 })
        #expect(projected.runtimeChatRead.latestEntries.last?.id == "input-127")
    }

    @Test func aHeldBackgroundHistoryCannotPublishAfterTheExecutionChanges() async throws {
        let source = source()
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let oldHistory = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .inputHistory(before: nil)))
        let gate = PublicationResponseGate()
        projected.runtimeContentLoader = { request in
            if case .inputHistory = request.target { return await gate.response() }
            return try await source.runtimeChatReadContent(for: request)
        }
        let refreshing = Task { try await projected.refreshRuntimeChatRead() }
        await gate.waitForRequest()
        var replacement = SessionRuntimeChatSnapshot(id: source.id, startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        replacement.transcript = [.userMessage(id: "new-input", text: "新しい実行", timestamp: .distantPast, attachments: [])]
        replacement.transcriptRevision = 9
        let current = ChatSessionViewModel(projection: replacement) { _, _ in .none }
        try projected.applyRuntimeOverview(current.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await current.runtimeChatReadContent(for: $0) }
        try await projected.refreshRuntimeChatRead()

        gate.release(oldHistory)
        try await refreshing.value

        #expect(projected.runtimeChatRead.page?.blocks.map(\.id) == ["new-input"])
        #expect(projected.runtimeChatRead.latestEntries.map(\.id) == ["new-input"])
        #expect(projected.runtimeChatRead.historyError == nil)
        #expect(projected.runtimeChatRead.error == nil)
    }

    private func lastInputText(_ projected: ChatSessionViewModel) -> String? {
        guard let block = projected.runtimeChatRead.page?.blocks.last,
              case .item(.inline(.userMessage(_, let text, _, _, _))) = block.content else { return nil }
        return text
    }

    private func update(_ source: ChatSessionViewModel) throws {
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[127] = .userMessage(id: "input-127", text: "更新した依頼", timestamp: .distantPast, attachments: [])
        changed.transcriptRevision = 8
        try source.applyRuntimeSnapshot(changed)
    }

    private func source() -> ChatSessionViewModel {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = (0..<128).map { .userMessage(id: "input-\($0)", text: "依頼 \($0)", timestamp: .distantPast, attachments: []) }
        snapshot.transcriptRevision = 7
        return ChatSessionViewModel(projection: snapshot) { _, _ in .none }
    }

    private func projection(_ source: ChatSessionViewModel) -> ChatSessionViewModel {
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeSupportsChatReadModel = true
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }
        return projected
    }
}

@MainActor private final class PublicationResponseGate {
    private var request: CheckedContinuation<SessionRuntimeContentResponse, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func response() async -> SessionRuntimeContentResponse {
        await withCheckedContinuation { continuation in
            request = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitForRequest() async {
        if request != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func release(_ response: SessionRuntimeContentResponse) {
        request?.resume(returning: response)
        request = nil
    }
}
