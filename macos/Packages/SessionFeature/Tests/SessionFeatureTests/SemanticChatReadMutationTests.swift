import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite @MainActor
struct SemanticChatReadMutationTests {
    @Test func streamingBodyUpdatesKeepCursorsValidButCompletionChangesTheCardVersion() async throws {
        let client = ReadClient()
        defer { client.finish() }
        let source = makeOwner(client)
        try await source.sendText("作業してください", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running }
        appendCommands(client)
        try await waitUntil { source.transcript.count == 56 }
        let inputID = try #require(source.transcript.first?.id)
        let beforeRows = try await rows(source, inputID)
        let rowID = try #require(beforeRows.rows.first?.id)
        let before = try await entries(source, inputID, rowID)
        let oldCursor = try #require(before.nextCursor)

        client.yield(.commandExecution(itemId: "command-0", command: nil, outputDelta: " UPDATED"))
        try await waitUntil { output(source, "command-0") == "output-0 UPDATED" }
        let bodyRows = try await rows(source, inputID)
        let continued = try await entries(source, inputID, rowID, cursor: oldCursor)

        #expect(bodyRows.card.revision == beforeRows.card.revision)
        #expect(bodyRows.card.contentRevision > beforeRows.card.contentRevision)
        #expect(continued.entries.map(\.id) == ["command-0", "command-1", "command-2", "command-3", "command-4"])

        client.yield(.itemCompleted(itemId: "command-0"))
        try await waitUntil { completed(source, "command-0") }
        let completedRows = try await rows(source, inputID)

        #expect(completedRows.card.revision > bodyRows.card.revision)
        #expect(completedRows.rows.first?.totalEntryCount == 55)
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await entries(source, inputID, rowID, cursor: oldCursor)
        }
    }

    @Test func reasoningBeforeTheFirstWorkRemainsAboveTheCardDuringIncrementalAppend() async throws {
        let client = ReadClient()
        defer { client.finish() }
        let source = makeOwner(client)
        try await source.sendText("考えてください", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running }
        let inputID = try #require(source.transcript.first?.id)
        _ = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        client.yield(.reasoningDelta(itemId: "before-work", "検討します"))
        try await waitUntil { source.transcript.count == 2 }
        let response = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        guard case .chatReadPage(let page) = response else { Issue.record("会話ページではありません"); return }
        #expect(page.blocks.map(\.id) == [inputID, "before-work", "status-card-\(inputID)"])
        let cardRows = try await rows(source, inputID)
        #expect(cardRows.rows.isEmpty)
    }

    @Test func anAdditionalInputClosesThePreviousCardAndStartsANewCard() async throws {
        let client = ReadClient()
        defer { client.finish() }
        let source = makeOwner(client)
        try await source.sendText("最初の依頼", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running }
        client.yield(.commandExecution(itemId: "first-work", command: "echo first", outputDelta: "開始"))
        try await waitUntil { source.transcript.count == 2 }
        _ = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))

        try await source.sendText("追加の依頼", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running && source.transcript.count == 3 }
        let response = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        guard case .chatReadPage(let page) = response else { Issue.record("会話ページではありません"); return }
        let states = page.blocks.compactMap { block -> AgentStatusHeader.State? in
            if case .card(let card) = block.content { return card.header.state }; return nil
        }
        #expect(states == [.superseded, .running])
        #expect(page.blocks.count == 4)
    }

    @Test func changingASearchResultUpdatesItsCountWithoutChangingItsActionIdentity() async throws {
        let client = ReadClient()
        defer { client.finish() }
        let source = makeOwner(client)
        try await source.sendText("検索してください", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running }
        client.yield(.commandExecution(itemId: "search", command: "Grep query", outputDelta: "one"))
        try await waitUntil { source.transcript.count == 2 }
        let inputID = try #require(source.transcript.first?.id)
        let before = try await rows(source, inputID)
        let rowID = try #require(before.rows.first?.id)
        let first = try await entries(source, inputID, rowID)

        client.yield(.commandExecution(itemId: "search", command: nil, outputDelta: "\ntwo"))
        try await waitUntil { output(source, "search") == "one\ntwo" }
        let after = try await rows(source, inputID)
        let second = try await entries(source, inputID, rowID)
        guard case .action(let oldAction) = first.entries.first,
              case .action(let newAction) = second.entries.first else { Issue.record("検索作業ではありません"); return }
        #expect(oldAction.id == "search")
        #expect(newAction.id == "search")
        #expect(oldAction.label == .search(query: "query", hits: 1))
        #expect(newAction.label == .search(query: "query", hits: 2))
        #expect(after.card.revision > before.card.revision)
    }

    @Test func anEditReplacedWithNoChangesStopsBeingAWorkRow() async throws {
        let client = ReadClient()
        defer { client.finish() }
        let source = makeOwner(client)
        try await source.sendText("編集してください", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running }
        client.yield(.fileChange(itemId: "edit", [.init(path: "File.swift", diff: "+line", kind: "edit")]))
        try await waitUntil { source.transcript.count == 2 }
        let inputID = try #require(source.transcript.first?.id)
        let before = try await rows(source, inputID)

        client.yield(.fileChange(itemId: "edit", []))
        try await waitUntil { hasEmptyChanges(source, "edit") }
        let after = try await rows(source, inputID)

        #expect(before.rows.first?.totalActionCount == 1)
        #expect(after.rows.isEmpty)
        #expect(after.card.totalRowCount == 0)
    }

    @Test func appendingToACursorCommandGroupKeepsItsIdentityAndUpdatedTailMetadata() async throws {
        let client = ReadClient()
        defer { client.finish() }
        let source = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.cursor), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/workspace")
        try await source.sendText("実行してください", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running }
        appendCommands(client)
        try await waitUntil { source.transcript.count == 56 }
        let before = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))

        client.yield(.commandExecution(itemId: "command-last", command: "echo last", outputDelta: "最後"))
        try await waitUntil { source.transcript.count == 57 }
        let after = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        guard case .chatReadPage(let beforePage) = before, case .commandGroup(let beforeGroup) = beforePage.blocks.last?.content,
              case .chatReadPage(let afterPage) = after, case .commandGroup(let afterGroup) = afterPage.blocks.last?.content else {
            Issue.record("コマンドグループではありません"); return
        }
        #expect(beforeGroup.id == "command-0")
        #expect(afterGroup.id == "command-0")
        #expect(beforeGroup.totalItemCount == 55)
        #expect(afterGroup.totalItemCount == 56)
        #expect(afterGroup.commandGroup?.firstCommand == "echo command-0")
        #expect(afterGroup.commandGroup?.lastCommand == "echo last")
    }

    private func hasEmptyChanges(_ source: ChatSessionViewModel, _ id: String) -> Bool {
        guard case .fileChange(_, let changes, _, _) = source.transcript.first(where: { $0.id == id }) else { return false }
        return changes.isEmpty
    }

    @Test func lateWorkUpdatesOnlyChangeTheirOwningInputScope() async throws {
        let client = ReadClient()
        defer { client.finish() }
        let source = makeOwner(client)
        try await source.sendText("最初の依頼", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running }
        client.yield(.commandExecution(itemId: "old-work", command: "echo old", outputDelta: "old"))
        try await waitUntil { source.transcript.count == 2 }
        let firstID = try #require(source.transcript.first?.id)
        try await source.sendText("次の依頼", submit: true)
        client.yield(.turnStarted)
        client.yield(.commandExecution(itemId: "new-work", command: "echo new", outputDelta: "new"))
        try await waitUntil { source.transcript.count == 4 }
        let secondID = try #require(source.transcript.dropFirst(2).first?.id)
        let first = try await rows(source, firstID)
        let second = try await rows(source, secondID)

        client.yield(.commandExecution(itemId: "old-work", command: nil, outputDelta: " later"))
        try await waitUntil { output(source, "old-work") == "old later" }
        let bodyFirst = try await rows(source, firstID)
        let bodySecond = try await rows(source, secondID)

        #expect(bodyFirst.card.revision == first.card.revision)
        #expect(bodyFirst.card.contentRevision > first.card.contentRevision)
        #expect(bodySecond.card.revision == second.card.revision)
        #expect(bodySecond.card.contentRevision == second.card.contentRevision)

        client.yield(.itemCompleted(itemId: "old-work"))
        try await waitUntil { completed(source, "old-work") }
        let doneFirst = try await rows(source, firstID)
        let doneSecond = try await rows(source, secondID)
        #expect(doneFirst.card.revision > bodyFirst.card.revision)
        #expect(doneSecond.card.revision == second.card.revision)
        #expect(doneSecond.card.contentRevision == second.card.contentRevision)
    }

    @Test func anEmptyFileChangeDoesNotReplaceTheCurrentRunningWorkOnRepeatedReads() async throws {
        let client = ReadClient()
        defer { client.finish() }
        let source = makeOwner(client)
        try await source.sendText("確認してください", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running }
        client.yield(.commandExecution(itemId: "running-work", command: "echo work", outputDelta: "実行中"))
        client.yield(.fileChange(itemId: "empty", []))
        try await waitUntil { source.transcript.count == 3 }
        let inputID = try #require(source.transcript.first?.id)
        let first = try await rows(source, inputID)
        let repeated = try await rows(source, inputID)
        #expect(first.card.header.current == .command("echo work"))
        #expect(repeated.card.header.current == .command("echo work"))
    }

    @Test func unrelatedCursorInputChangesKeepTheOldGroupContentVersion() async throws {
        let client = ReadClient()
        defer { client.finish() }
        let source = ChatSessionViewModel(id: SessionID(), agentRef: .builtin(.cursor), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/workspace")
        try await source.sendText("最初の依頼", submit: true)
        client.yield(.turnStarted)
        try await waitUntil { source.status == .running }
        client.yield(.commandExecution(itemId: "old-group", command: "echo old", outputDelta: "old"))
        try await waitUntil { source.transcript.count == 2 }
        let initial = try await groupSummary(source, "old-group")

        try await source.sendText("次の依頼", submit: true)
        client.yield(.turnStarted)
        client.yield(.reasoningDelta(itemId: "new-reasoning", "新しい依頼を検討"))
        try await waitUntil { source.transcript.count == 4 }
        let afterInput = try await groupSummary(source, "old-group")
        client.yield(.agentMessageDelta(itemId: "new-answer", "新しい返答"))
        try await waitUntil { source.transcript.count == 5 }
        let afterUnrelatedBody = try await groupSummary(source, "old-group")

        #expect(initial.contentRevision > 0)
        #expect(afterInput.contentRevision == initial.contentRevision)
        #expect(afterUnrelatedBody.contentRevision == initial.contentRevision)

        client.yield(.commandExecution(itemId: "old-group", command: nil, outputDelta: " changed"))
        try await waitUntil { output(source, "old-group") == "old changed" }
        let afterOwnBody = try await groupSummary(source, "old-group")
        #expect(afterOwnBody.id == "old-group")
        #expect(afterOwnBody.totalItemCount == 1)
        #expect(afterOwnBody.contentRevision > initial.contentRevision)
    }

    private func groupSummary(_ source: ChatSessionViewModel, _ actionID: String) async throws -> SessionRuntimeActionSummary {
        let response = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        guard case .chatReadPage(let page) = response,
              let group = page.blocks.compactMap({ block -> SessionRuntimeActionSummary? in
                  if case .commandGroup(let group) = block.content, group.id == actionID { return group }; return nil
              }).first else { throw ReadError.unexpected }
        return group
    }

    private func makeOwner(_ client: ReadClient) -> ChatSessionViewModel {
        .init(id: SessionID(), agentRef: .builtin(.claudeCode), client: client,
            approvalBroker: ChatApprovalBroker(), workingDirectory: "/workspace")
    }

    private func appendCommands(_ client: ReadClient) {
        for number in 0..<55 {
            client.yield(.commandExecution(itemId: "command-\(number)", command: "echo command-\(number)", outputDelta: "output-\(number)"))
        }
    }

    private func output(_ source: ChatSessionViewModel, _ id: String) -> String? {
        guard case .commandExecution(_, _, let output, _, _, _) = source.transcript.first(where: { $0.id == id }) else { return nil }
        return output
    }

    private func completed(_ source: ChatSessionViewModel, _ id: String) -> Bool {
        guard case .commandExecution(_, _, _, _, let completedAt, _) = source.transcript.first(where: { $0.id == id }) else { return false }
        return completedAt != nil
    }

    private func request(_ source: ChatSessionViewModel, _ target: SessionRuntimeContentRequest.Target) -> SessionRuntimeContentRequest {
        .init(sessionID: source.id, executionID: source.executionID, target: target)
    }

    private func rows(_ source: ChatSessionViewModel, _ inputID: String) async throws -> SessionRuntimeCardRowsPage {
        let response = try await source.runtimeChatReadContent(for: request(source, .chatCardRows(inputID: inputID, cursor: nil)))
        guard case .cardRowsPage(let page) = response else { throw ReadError.unexpected }
        return page
    }

    private func entries(_ source: ChatSessionViewModel, _ inputID: String, _ rowID: String,
                         cursor: SessionRuntimeChatReadCursor? = nil) async throws -> SessionRuntimeCardEntriesPage {
        let response = try await source.runtimeChatReadContent(for: request(source, .chatRowEntries(inputID: inputID, rowID: rowID, cursor: cursor)))
        guard case .cardEntriesPage(let page) = response else { throw ReadError.unexpected }
        return page
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw ReadError.timedOut }
            await Task.yield()
        }
    }

    private enum ReadError: Error { case unexpected, timedOut }
}

private final class ReadClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    init() {
        (events, continuation) = AsyncStream.makeStream()
    }
    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {}
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
    func finish() { continuation.finish() }
}
