import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite @MainActor
struct SemanticChatReadActionAnchorTests {
    @Test func insertingBeforeAManualPageKeepsItsFirstIncludedItemAndItsForwardWindow() async throws {
        var snapshot = fixture(reads: 120)
        let source = owner(snapshot)
        let first = try await items(source, .chatActionItems(inputID: "request", actionID: "read-0", cursor: nil))
        let oldCursor = try #require(first.nextCursor)
        let manual = try await items(source, .chatActionItems(inputID: "request", actionID: "read-0", cursor: oldCursor))
        let firstID = try #require(manual.items.first?.id)
        snapshot.transcript.insert(read("inserted", number: 10), at: 11)
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)

        let fresh = try await items(source, .chatActionItemsFrom(inputID: "request", actionID: "read-0", itemID: firstID))
        let retagged = SessionRuntimeChatReadCursor(scopeID: oldCursor.scopeID, revision: fresh.revision,
            index: oldCursor.index, anchorID: oldCursor.anchorID)
        let nextCursor = try #require(fresh.nextCursor)
        let next = try await items(source, .chatActionItems(inputID: "request", actionID: "read-0", cursor: nextCursor))

        #expect(fresh.items.map(\.id) == [
            "read-50", "read-51", "read-52", "read-53", "read-54",
            "read-55", "read-56", "read-57", "read-58", "read-59",
            "read-60", "read-61", "read-62", "read-63", "read-64",
            "read-65", "read-66", "read-67", "read-68", "read-69",
            "read-70", "read-71", "read-72", "read-73", "read-74",
            "read-75", "read-76", "read-77", "read-78", "read-79",
            "read-80", "read-81", "read-82", "read-83", "read-84",
            "read-85", "read-86", "read-87", "read-88", "read-89",
            "read-90", "read-91", "read-92", "read-93", "read-94",
            "read-95", "read-96", "read-97", "read-98", "read-99",
        ])
        #expect(fresh.nextCursor != nil)
        #expect(next.items.map(\.id) == ["read-100", "read-101", "read-102", "read-103", "read-104",
            "read-105", "read-106", "read-107", "read-108", "read-109",
            "read-110", "read-111", "read-112", "read-113", "read-114",
            "read-115", "read-116", "read-117", "read-118", "read-119"])
        #expect(next.nextCursor == nil)
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await items(source, .chatActionItems(inputID: "request", actionID: "read-0", cursor: retagged))
        }
    }

    @Test func rebasingAShortFinalPageDoesNotPullEarlierItemsIntoThePage() async throws {
        var snapshot = fixture(reads: 60)
        let source = owner(snapshot)
        let first = try await items(source, .chatActionItems(inputID: "request", actionID: "read-0", cursor: nil))
        let cursor = try #require(first.nextCursor)
        let manual = try await items(source, .chatActionItems(inputID: "request", actionID: "read-0", cursor: cursor))
        let firstID = try #require(manual.items.first?.id)
        snapshot.transcript.insert(read("inserted", number: 10), at: 11)
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)

        let fresh = try await items(source, .chatActionItemsFrom(inputID: "request", actionID: "read-0", itemID: firstID))

        #expect(fresh.items.map(\.id) == ["read-50", "read-51", "read-52", "read-53", "read-54",
            "read-55", "read-56", "read-57", "read-58", "read-59"])
        #expect(fresh.nextCursor == nil)
    }

    @Test func aRemovedPageAnchorReturnsNotFoundInsteadOfReusingItsOldIndex() async throws {
        var snapshot = fixture(reads: 120)
        let source = owner(snapshot)
        _ = try await items(source, .chatActionItemsFrom(inputID: "request", actionID: "read-0", itemID: "read-50"))
        snapshot.transcript.remove(at: 51)
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)

        await #expect(throws: SessionRuntimeContentError.notFound) {
            _ = try await items(source, .chatActionItemsFrom(inputID: "request", actionID: "read-0", itemID: "read-50"))
        }
    }

    @Test func aRemovedActionReturnsNotFoundForItsPreviouslyValidAnchor() async throws {
        var snapshot = fixture(reads: 60)
        let source = owner(snapshot)
        _ = try await items(source, .chatActionItemsFrom(inputID: "request", actionID: "read-0", itemID: "read-50"))
        snapshot.transcript.removeSubrange(1...)
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)

        await #expect(throws: SessionRuntimeContentError.notFound) {
            _ = try await items(source, .chatActionItemsFrom(inputID: "request", actionID: "read-0", itemID: "read-50"))
        }
    }

    @Test func anAnchorCannotEscapeItsInputOrActionScope() async throws {
        var snapshot = fixture(reads: 10, agent: .claudeCode)
        snapshot.transcript += [.reasoning(id: "separator", text: "次の作業", timestamp: at(20)), read("other", number: 21)]
        let source = owner(snapshot)

        await #expect(throws: SessionRuntimeContentError.notFound) {
            _ = try await items(source, .chatActionItemsFrom(inputID: "request", actionID: "read-0", itemID: "other"))
        }
        await #expect(throws: SessionRuntimeContentError.notFound) {
            _ = try await items(source, .chatActionItemsFrom(inputID: "different-input", actionID: "read-0", itemID: "read-5"))
        }
    }

    @Test func anAnchoredPageEnforcesTheEncodedByteLimitWithoutDroppingItsFirstItem() async throws {
        let source = owner(fixture(reads: 80, output: String(repeating: "x", count: 7_500)))
        let request = SessionRuntimeContentRequest(sessionID: source.id, executionID: source.executionID,
            target: .chatActionItemsFrom(inputID: "request", actionID: "read-0", itemID: "read-20"))
        let response = try await source.runtimeChatReadContent(for: request)
        guard case .actionItemsPage(let page) = response,
              case .inline(.commandExecution(_, _, let output, _, _, _)) = page.items.first else {
            Issue.record("先頭の本文を取得できません"); return
        }

        #expect(page.items.first?.id == "read-20")
        #expect(output.utf8.count == 7_500)
        #expect(page.items.count < 50)
        #expect(page.nextCursor != nil)
        #expect(try JSONEncoder().encode(response).count <= SessionRuntimeChatReadLimits.maximumResponseBytes)
    }

    @Test func aPreambleGroupCanBeReadFromAnItemWithoutAnInputID() async throws {
        var snapshot = fixture(reads: 60)
        snapshot.transcript.removeFirst()
        let source = owner(snapshot)

        let page = try await items(source, .chatActionItemsFrom(inputID: nil, actionID: "read-0", itemID: "read-50"))

        #expect(page.items.map(\.id) == ["read-50", "read-51", "read-52", "read-53", "read-54",
            "read-55", "read-56", "read-57", "read-58", "read-59"])
        #expect(page.nextCursor == nil)
    }

    @Test(arguments: [(AgentKind.codex, true), (.cursor, true), (.codex, false)], [40, 119])
    func shrinkingAnActionInvalidatesItsIssuedCursor(_ mode: (AgentKind, Bool), retained: Int) async throws {
        var snapshot = fixture(reads: 120, agent: mode.0, includeInput: mode.1)
        let inputID: String? = mode.1 ? "request" : nil
        let source = owner(snapshot)
        let before = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: nil))
        let cursor = try #require(before.nextCursor)
        snapshot.transcript.removeLast(120 - retained)
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)

        let after = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: nil))

        #expect(after.revision != before.revision)
        #expect(after.items.first?.id == "read-0")
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: cursor))
        }
    }

    @Test(arguments: [(AgentKind.cursor, true), (.codex, false)])
    func reorderingItemsBeyondTheBoundaryInvalidatesAnUngroupedActionCursor(_ mode: (AgentKind, Bool)) async throws {
        var snapshot = fixture(reads: 120, agent: mode.0, includeInput: mode.1)
        let inputID: String? = mode.1 ? "request" : nil
        let source = owner(snapshot)
        let before = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: nil))
        let cursor = try #require(before.nextCursor)
        let offset = mode.1 ? 1 : 0
        snapshot.transcript.swapAt(60 + offset, 61 + offset)
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)

        let after = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: nil))

        #expect(after.revision != before.revision)
        #expect(after.items.last?.id == "read-49")
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: cursor))
        }
    }

    @Test(arguments: [(AgentKind.cursor, true), (.codex, false)])
    func replacingItemsBeyondTheBoundaryInvalidatesAnUngroupedActionCursor(_ mode: (AgentKind, Bool)) async throws {
        var snapshot = fixture(reads: 120, agent: mode.0, includeInput: mode.1)
        let inputID: String? = mode.1 ? "request" : nil
        let source = owner(snapshot)
        let before = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: nil))
        let cursor = try #require(before.nextCursor)
        let offset = mode.1 ? 1 : 0
        snapshot.transcript[60 + offset] = read("replacement", number: 60)
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)

        let after = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: nil))

        #expect(after.revision != before.revision)
        #expect(after.items.last?.id == "read-49")
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: cursor))
        }
    }

    @Test(arguments: [(AgentKind.cursor, true), (.codex, false)])
    func pureAppendsAndBodyEditsPreserveUngroupedActionCursorsAcrossRebuilds(_ mode: (AgentKind, Bool)) async throws {
        var snapshot = fixture(reads: 60, agent: mode.0, includeInput: mode.1)
        let inputID: String? = mode.1 ? "request" : nil
        let source = owner(snapshot)
        let before = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: nil))
        let cursor = try #require(before.nextCursor)
        snapshot.status = .running
        snapshot.transcript.append(read("read-60", number: 60))
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)
        let appended = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: cursor))
        snapshot.status = .idle
        snapshot.transcript[mode.1 ? 51 : 50] = read("read-50", number: 50, output: "更新された本文")
        snapshot.transcriptRevision = 9
        try source.applyRuntimeSnapshot(snapshot)

        let edited = try await items(source, .chatActionItems(inputID: inputID, actionID: "read-0", cursor: cursor))
        guard case .inline(.commandExecution(_, _, let output, _, _, _)) = edited.items.first else {
            Issue.record("更新された本文を取得できません"); return
        }

        #expect(appended.revision == before.revision)
        #expect(edited.revision == before.revision)
        #expect(appended.items.first?.id == "read-50")
        #expect(appended.items.last?.id == "read-60")
        #expect(edited.items.first?.id == "read-50")
        #expect(edited.items.last?.id == "read-60")
        #expect(output == "更新された本文")
    }

    private func fixture(reads: Int, output: String = "内容", agent: AgentKind = .codex, includeInput: Bool = true) -> SessionRuntimeChatSnapshot {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: at(0),
            agentRef: .builtin(agent), workingDirectory: "/workspace")
        snapshot.status = .idle
        snapshot.transcript = [.userMessage(id: "request", text: "確認してください", timestamp: at(0), attachments: [],
            turnEnd: .init(outcome: .completed, at: at(200)))]
            + (0..<reads).map { read("read-\($0)", number: $0, output: output) }
        if !includeInput { snapshot.transcript.removeFirst() }
        snapshot.transcriptRevision = 7
        return snapshot
    }

    private func read(_ id: String, number: Int, output: String = "内容") -> ChatItem {
        .commandExecution(id: id, command: "Read src/file-\(number).swift", output: output,
            timestamp: at(Double(number + 1)), completedAt: at(Double(number + 2)))
    }

    private func owner(_ snapshot: SessionRuntimeChatSnapshot) -> ChatSessionViewModel {
        .init(projection: snapshot) { _, _ in .none }
    }

    private func items(_ source: ChatSessionViewModel, _ target: SessionRuntimeContentRequest.Target) async throws -> SessionRuntimeActionItemsPage {
        let request = SessionRuntimeContentRequest(sessionID: source.id, executionID: source.executionID, target: target)
        let response = try await source.runtimeChatReadContent(for: request)
        guard case .actionItemsPage(let page) = response else { throw ReadError.unexpected }
        return page
    }

    private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_000 + seconds) }
    private enum ReadError: Error { case unexpected }
}
