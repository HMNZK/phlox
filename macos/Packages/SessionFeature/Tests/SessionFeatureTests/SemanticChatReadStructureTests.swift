import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite @MainActor
struct SemanticChatReadStructureTests {
    @Test func replacingAnOldBlockInvalidatesTheTimelineEvenWhenThePageBoundarySurvives() async throws {
        var snapshot = fixture(items: bareReplies())
        let source = owner(snapshot)
        let before = try await timeline(source)
        let historyBefore = try await history(source)
        let cursor = try #require(before.olderCursor)
        snapshot.transcript[5] = .reasoning(id: "replacement", text: "置き換えた思考", timestamp: at(5))
        snapshot.transcriptRevision = 8

        try source.applyRuntimeSnapshot(snapshot)
        let after = try await timeline(source)
        let historyAfter = try await history(source)

        #expect(before.blocks.first?.id == "answer-30")
        #expect(after.blocks.first?.id == "answer-30")
        #expect(after.startIndex == before.startIndex)
        #expect(after.totalBlockCount == 80)
        #expect(after.revision != before.revision)
        #expect(historyAfter.revision == historyBefore.revision)
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await source.runtimeChatReadContent(for: request(source, .chatReadBefore(cursor: cursor)))
        }
    }

    @Test func reorderingOldInputsInvalidatesHistoryEvenWhenItsCountAndBoundarySurvive() async throws {
        var snapshot = fixture(items: inputReplies())
        let source = owner(snapshot)
        let before = try await history(source)
        let cursor = try #require(before.olderCursor)
        snapshot.transcript.swapAt(2, 4)
        snapshot.transcriptRevision = 8

        try source.applyRuntimeSnapshot(snapshot)
        let after = try await history(source)

        #expect(before.entries.first?.id == "input-30")
        #expect(after.entries.first?.id == "input-30")
        #expect(after.totalCount == 80)
        #expect(after.revision != before.revision)
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await source.runtimeChatReadContent(for: request(source, .inputHistory(before: cursor)))
        }
    }

    @Test func pureAppendsAndBodyEditsPreserveBothScopesAndExistingCursors() async throws {
        var snapshot = fixture(items: inputReplies())
        let source = owner(snapshot)
        let before = try await timeline(source)
        let historyBefore = try await history(source)
        let timelineCursor = try #require(before.olderCursor)
        let historyCursor = try #require(historyBefore.olderCursor)
        snapshot.transcript.append(contentsOf: pair(80))
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)
        let appended = try await timeline(source)
        let historyAppended = try await history(source)
        snapshot.transcript[1] = .agentMessage(id: "answer-0", text: "更新された本文", timestamp: at(1))
        snapshot.transcriptRevision = 9

        try source.applyRuntimeSnapshot(snapshot)
        let edited = try await timeline(source)
        let historyEdited = try await history(source)
        let olderResponse = try await source.runtimeChatReadContent(for: request(source, .chatReadBefore(cursor: timelineCursor)))
        let olderHistoryResponse = try await source.runtimeChatReadContent(for: request(source, .inputHistory(before: historyCursor)))
        let changedResponse = try await source.runtimeChatReadContent(for: request(source, .chatReadAroundItem(itemID: "answer-0")))
        guard case .chatReadPage(let older) = olderResponse,
              case .inputHistoryPage(let olderHistory) = olderHistoryResponse,
              case .chatReadPage(let changed) = changedResponse,
              case .item(.inline(.agentMessage(_, let text, _))) = changed.blocks.first?.content else {
            Issue.record("元の境界と更新本文を取得できません"); return
        }

        #expect(appended.revision == before.revision)
        #expect(edited.revision == before.revision)
        #expect(historyAppended.revision == historyBefore.revision)
        #expect(historyEdited.revision == historyBefore.revision)
        #expect(edited.totalBlockCount == 162)
        #expect(historyEdited.totalCount == 81)
        #expect(older.blocks.count == 50)
        #expect(older.blocks.first?.id == "input-30")
        #expect(older.blocks.last?.id == "answer-54")
        #expect(olderHistory.entries.count == 30)
        #expect(olderHistory.entries.first?.id == "input-0")
        #expect(olderHistory.entries.last?.id == "input-29")
        #expect(text == "更新された本文")
    }

    @Test func rewindingTheTailInvalidatesBothScopesWithoutMovingTheirOldBoundaryAnchors() async throws {
        var snapshot = fixture(items: inputReplies())
        let source = owner(snapshot)
        let before = try await timeline(source)
        let historyBefore = try await history(source)
        let timelineCursor = try #require(before.olderCursor)
        let historyCursor = try #require(historyBefore.olderCursor)
        snapshot.transcript.removeLast(2)
        snapshot.transcriptRevision = 8

        try source.applyRuntimeSnapshot(snapshot)
        let after = try await timeline(source)
        let historyAfter = try await history(source)

        #expect(after.totalBlockCount == 158)
        #expect(historyAfter.totalCount == 79)
        #expect(after.revision != before.revision)
        #expect(historyAfter.revision != historyBefore.revision)
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await source.runtimeChatReadContent(for: request(source, .chatReadBefore(cursor: timelineCursor)))
        }
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await source.runtimeChatReadContent(for: request(source, .inputHistory(before: historyCursor)))
        }
    }

    @Test func aNewExecutionRejectsTheOldExecutionRequestEvenWhenTheBlockIDsMatch() async throws {
        var snapshot = fixture(items: inputReplies())
        let source = owner(snapshot)
        let before = try await timeline(source)
        let cursor = try #require(before.olderCursor)
        let oldRequest = request(source, .chatReadBefore(cursor: cursor))
        snapshot.executionID = UUID(uuidString: "A0C33BC6-930F-49FA-AB9E-93C84E4FC099")!
        snapshot.transcriptRevision = 1
        try source.applyRuntimeSnapshot(snapshot)

        let after = try await timeline(source)

        #expect(after.executionID == snapshot.executionID)
        #expect(after.executionID != before.executionID)
        #expect(after.blocks.first?.id == "input-55")
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await source.runtimeChatReadContent(for: oldRequest)
        }
    }

    private func fixture(items: [ChatItem]) -> SessionRuntimeChatSnapshot {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: at(0),
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.status = .idle
        snapshot.transcript = items
        snapshot.transcriptRevision = 7
        return snapshot
    }

    private func owner(_ snapshot: SessionRuntimeChatSnapshot) -> ChatSessionViewModel {
        .init(projection: snapshot) { _, _ in .none }
    }

    private func request(_ source: ChatSessionViewModel, _ target: SessionRuntimeContentRequest.Target) -> SessionRuntimeContentRequest {
        .init(sessionID: source.id, executionID: source.executionID, target: target)
    }

    private func timeline(_ source: ChatSessionViewModel) async throws -> SessionRuntimeChatReadPage {
        let response = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        guard case .chatReadPage(let page) = response else { throw ReadError.unexpected }
        return page
    }

    private func history(_ source: ChatSessionViewModel) async throws -> SessionRuntimeInputHistoryPage {
        let response = try await source.runtimeChatReadContent(for: request(source, .inputHistory(before: nil)))
        guard case .inputHistoryPage(let page) = response else { throw ReadError.unexpected }
        return page
    }

    private func bareReplies() -> [ChatItem] {
        (0..<80).map { .agentMessage(id: "answer-\($0)", text: "回答\($0)", timestamp: at(Double($0))) }
    }

    private func inputReplies() -> [ChatItem] { (0..<80).flatMap(pair) }

    private func pair(_ number: Int) -> [ChatItem] {
        [.userMessage(id: "input-\(number)", text: "入力\(number)", timestamp: at(Double(number * 2)), attachments: [],
            turnEnd: .init(outcome: .completed, at: at(Double(number * 2 + 1)))),
         .agentMessage(id: "answer-\(number)", text: "回答\(number)", timestamp: at(Double(number * 2 + 1)))]
    }

    private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_000 + seconds) }
    private enum ReadError: Error { case unexpected }
}
