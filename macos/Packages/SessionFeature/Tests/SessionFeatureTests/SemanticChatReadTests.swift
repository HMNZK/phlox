import AgentDomain
import Foundation
import Testing
import StructuredChatKit
@testable import SessionFeature

@Suite @MainActor
struct SemanticChatReadTests {
    @Test func aTailWithoutItsInputStillContainsTheCanonicalCard() async throws {
        let source = owner(items: longSingleInput())
        let response = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        guard case .chatReadPage(let page) = response else { Issue.record("会話ページではありません"); return }
        #expect(page.blocks.map(\.id) == ["input", "status-card-input", "answer"])
        #expect(page.blocks.map(\.ownerInputID) == ["input", "input", "input"])
        #expect(try JSONEncoder().encode(response).count <= SessionRuntimeChatReadLimits.maximumResponseBytes)
    }

    @Test func actionDetailsArePagedWithoutChangingTheirSummaryOrIdentity() async throws {
        let source = owner(items: longSingleInput())
        let response = try await source.runtimeChatReadContent(for: request(source, .chatRowEntries(
            inputID: "input", rowID: "outside-work-1", cursor: nil)))
        guard case .cardEntriesPage(let page) = response,
              case .action(let action) = page.entries.first else { Issue.record("集約作業ではありません"); return }
        let detail = try await source.runtimeChatReadContent(for: request(source, .chatActionItems(
            inputID: "input", actionID: action.id, cursor: nil)))
        guard case .actionItemsPage(let items) = detail else { Issue.record("詳細ページではありません"); return }
        #expect(action.id == "work-1")
        #expect(action.totalItemCount == 125)
        #expect(action.state == .completed)
        #expect(items.items.count == 50)
        #expect(items.items.first?.id == "work-1")
        #expect(items.items.last?.id == "work-50")
        #expect(items.nextCursor != nil)
        let allItems = try await allActionItems(source, inputID: "input", actionID: action.id)
        #expect(allItems.map(\.id) == [
            "work-1", "work-2", "work-3", "work-4", "work-5",
            "work-6", "work-7", "work-8", "work-9", "work-10",
            "work-11", "work-12", "work-13", "work-14", "work-15",
            "work-16", "work-17", "work-18", "work-19", "work-20",
            "work-21", "work-22", "work-23", "work-24", "work-25",
            "work-26", "work-27", "work-28", "work-29", "work-30",
            "work-31", "work-32", "work-33", "work-34", "work-35",
            "work-36", "work-37", "work-38", "work-39", "work-40",
            "work-41", "work-42", "work-43", "work-44", "work-45",
            "work-46", "work-47", "work-48", "work-49", "work-50",
            "work-51", "work-52", "work-53", "work-54", "work-55",
            "work-56", "work-57", "work-58", "work-59", "work-60",
            "work-61", "work-62", "work-63", "work-64", "work-65",
            "work-66", "work-67", "work-68", "work-69", "work-70",
            "work-71", "work-72", "work-73", "work-74", "work-75",
            "work-76", "work-77", "work-78", "work-79", "work-80",
            "work-81", "work-82", "work-83", "work-84", "work-85",
            "work-86", "work-87", "work-88", "work-89", "work-90",
            "work-91", "work-92", "work-93", "work-94", "work-95",
            "work-96", "work-97", "work-98", "work-99", "work-100",
            "work-101", "work-102", "work-103", "work-104", "work-105",
            "work-106", "work-107", "work-108", "work-109", "work-110",
            "work-111", "work-112", "work-113", "work-114", "work-115",
            "work-116", "work-117", "work-118", "work-119", "work-120",
            "work-121", "work-122", "work-123", "work-124", "work-125",
        ])
        #expect(action.label == .read(file: "file-1.swift", more: 124))
        #expect(action.startedAt == Date(timeIntervalSince1970: 1_001))
        #expect(action.duration == 125)
        let rows = try await readRows(source, inputID: "input")
        let timelineResponse = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        guard case .chatReadPage(let timeline) = timelineResponse else { Issue.record("会話ページではありません"); return }
        #expect(rows.card.header.state == .completed)
        #expect(rows.card.header.startedAt == Date(timeIntervalSince1970: 1_000))
        #expect(rows.card.header.endedAt == Date(timeIntervalSince1970: 1_300))
        #expect(timeline.blocks.map(\.id) == ["input", "status-card-input", "answer"])
        #expect(timeline.blocks.map(\.ownerInputID) == ["input", "input", "input"])
    }

    @Test func inputHistoryAndDirectJumpDoNotNeedInterveningBodyPages() async throws {
        let source = owner(items: manyInputs())
        let historyResponse = try await source.runtimeChatReadContent(for: request(source, .inputHistory(before: nil)))
        let jumpResponse = try await source.runtimeChatReadContent(for: request(source, .chatReadAround(inputID: "input-1")))
        guard case .inputHistoryPage(let history) = historyResponse,
              case .chatReadPage(let jump) = jumpResponse else { Issue.record("ページではありません"); return }
        #expect(history.totalCount == 85)
        #expect(history.entries.count == 50)
        #expect(history.entries.first?.id == "input-36")
        #expect(history.entries.last?.id == "input-85")
        #expect(jump.blocks.first?.id == "input-1")
        #expect(jump.blocks.count == 50)
        #expect(jump.newerCursor != nil)
    }

    @Test func giantInputHasAPreviewAndAnExplicitReferenceInsteadOfInlineBody() async throws {
        let source = owner(items: [.userMessage(id: "giant", text: String(repeating: "巨大な入力", count: 100_000),
            timestamp: Date(timeIntervalSince1970: 1_000), attachments: [])])
        let response = try await source.runtimeChatReadContent(for: request(source, .inputHistory(before: nil)))
        guard case .inputHistoryPage(let page) = response,
              case .deferred(let marker) = page.entries.first?.content else {
            Issue.record("巨大入力をインライン返送しました"); return
        }
        #expect(page.entries.first?.id == "giant")
        #expect(page.entries.first?.canRecall == true)
        #expect(marker.itemKind == "userMessage")
        #expect(marker.totalBytes > 1_000_000)
        #expect(try JSONEncoder().encode(response).count < 16_384)
    }

    @Test func anInputWithAnImageCannotBeRecalledAsPlainText() async throws {
        let source = owner(items: [.userMessage(id: "image", text: "[Image #1] 見てください",
            timestamp: Date(timeIntervalSince1970: 1_000), attachments: [])])
        let response = try await source.runtimeChatReadContent(for: request(source, .inputHistory(before: nil)))
        guard case .inputHistoryPage(let page) = response else { Issue.record("履歴ではありません"); return }
        #expect(page.entries.first?.canRecall == false)
    }

    @Test func forgedCursorsAreRejectedAtTheReadBoundary() async throws {
        let source = owner(items: manyInputs())
        let cursor = SessionRuntimeChatReadCursor(scopeID: "timeline", revision: 77, index: -1, anchorID: "input-1")
        await #expect(throws: SessionRuntimeContentError.invalidRequest) {
            _ = try await source.runtimeChatReadContent(for: request(source, .chatReadBefore(cursor: cursor)))
        }
    }

    @Test(arguments: [
        (1, "status-card-first", ["first"]),
        (2, "first-answer", ["first", "status-card-first"]),
        (3, "second", ["first", "status-card-first", "first-answer"]),
        (4, "status-card-second", ["first", "status-card-first", "first-answer", "second"]),
        (5, "second-answer", ["first", "status-card-first", "first-answer", "second", "status-card-second"])
    ])
    func everyTopLevelCutKeepsTheCardMeaning(_ sample: (Int, String, [String])) async throws {
        let source = owner(items: twoTaskIntervals())
        let response = try await source.runtimeChatReadContent(for: request(source, .chatReadBefore(cursor:
            .init(scopeID: "timeline", revision: 1, index: sample.0, anchorID: sample.1))))
        guard case .chatReadPage(let page) = response else { Issue.record("会話ページではありません"); return }
        let headers = page.blocks.compactMap { block -> AgentStatusHeader.State? in
            if case .card(let card) = block.content { return card.header.state }; return nil
        }
        #expect(page.blocks.map(\.id) == sample.2)
        #expect(headers.allSatisfy { $0 == .completed })
    }

    @Test func taskReorderingKeepsHistoricalOwnershipInsteadOfPaintingWithTheLatestSnapshot() async throws {
        let source = owner(items: twoTaskIntervals())
        let rows = try await readRows(source, inputID: "first")
        let a = try await readEntries(source, inputID: "first", rowID: "task-A")
        let b = try await readEntries(source, inputID: "first", rowID: "task-B")
        #expect(rows.rows.map(\.id) == ["task-B", "task-A"])
        #expect(a.entries.map(\.id) == ["work-A"])
        #expect(b.entries.map(\.id) == ["work-B"])
        #expect(rows.card.header.state == .completed)
        #expect(rows.card.header.startedAt == Date(timeIntervalSince1970: 1_001))
        #expect(rows.card.header.endedAt == Date(timeIntervalSince1970: 1_010))
        guard case .task(_, _, let bState, let bStart, let bEnd) = rows.rows.first?.kind,
              case .task(_, _, let aState, let aStart, let aEnd) = rows.rows.last?.kind,
              case .action(let aAction) = a.entries.first,
              case .action(let bAction) = b.entries.first else { Issue.record("タスクと作業がありません"); return }
        #expect(aState == .completed)
        #expect(aStart == Date(timeIntervalSince1970: 1_003))
        #expect(aEnd == Date(timeIntervalSince1970: 1_005))
        #expect(bState == .completed)
        #expect(bStart == Date(timeIntervalSince1970: 1_005))
        #expect(bEnd == Date(timeIntervalSince1970: 1_007))
        #expect(aAction.label == .command("echo work-A"))
        #expect(aAction.state == .completed)
        #expect(aAction.startedAt == Date(timeIntervalSince1970: 1_004))
        #expect(aAction.duration == 1)
        #expect(bAction.label == .command("echo work-B"))
        #expect(bAction.state == .completed)
        #expect(bAction.startedAt == Date(timeIntervalSince1970: 1_006))
        #expect(bAction.duration == 1)
        let timelineResponse = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        guard case .chatReadPage(let timeline) = timelineResponse else { Issue.record("会話ページではありません"); return }
        #expect(timeline.blocks.map(\.id) == ["first", "status-card-first", "first-answer", "second", "status-card-second", "second-answer"])
        #expect(timeline.blocks.map(\.ownerInputID) == ["first", "first", "first", "second", "second", "second"])
    }

    @Test func tasksThatChangedAndReturnedRemainVisibleWhileDeletedAndUnchangedTasksDoNot() async throws {
        let source = owner(items: changedAndReturnedTasks())
        let rows = try await readRows(source, inputID: "changed")
        let owned = try await readEntries(source, inputID: "changed", rowID: "task-A")
        #expect(rows.rows.map(\.id) == ["outside-before", "task-A", "outside-after"])
        #expect(owned.entries.map(\.id) == ["during"])
    }

    @Test func byteBoundedTailAndBeforePagesAlwaysTouchTheirRequestedBoundary() async throws {
        let source = owner(items: largeInlineReplies())
        let tailResponse = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        guard case .chatReadPage(let tail) = tailResponse else { Issue.record("会話ページではありません"); return }
        let cursor = try #require(tail.olderCursor)
        let olderResponse = try await source.runtimeChatReadContent(for: request(source, .chatReadBefore(cursor: cursor)))
        guard case .chatReadPage(let older) = olderResponse else { Issue.record("会話ページではありません"); return }
        #expect(tail.blocks.last?.id == "reply-79")
        #expect(older.startIndex + older.blocks.count == tail.startIndex)
        #expect(try JSONEncoder().encode(tailResponse).count <= SessionRuntimeChatReadLimits.maximumResponseBytes)
        #expect(try JSONEncoder().encode(olderResponse).count <= SessionRuntimeChatReadLimits.maximumResponseBytes)
    }

    @Test func aGiantTaskTitleAndCommandStillProduceAnAdvancingFinitePage() async throws {
        let source = owner(items: giantDescriptors())
        let rowsResponse = try await source.runtimeChatReadContent(for: request(source, .chatCardRows(inputID: "giant-task", cursor: nil)))
        let entriesResponse = try await source.runtimeChatReadContent(for: request(source,
            .chatRowEntries(inputID: "giant-task", rowID: "task-huge", cursor: nil)))
        guard case .cardRowsPage(let rows) = rowsResponse,
              case .task(_, let title, _, _, _) = rows.rows.first?.kind,
              case .cardEntriesPage(let entries) = entriesResponse,
              case .action(let action) = entries.entries.first else { Issue.record("巨大項目を取得できません"); return }
        #expect(rows.rows.map(\.id) == ["task-huge"])
        #expect(title.utf8.count < 1024)
        #expect(action.id == "huge-command")
        #expect(entries.nextCursor == nil)
        #expect(try JSONEncoder().encode(rowsResponse).count < 16_384)
        #expect(try JSONEncoder().encode(entriesResponse).count < 16_384)
    }

    @Test func aSnapshotRewindInvalidatesRemovedTargetsWithoutLosingTheRetainedInput() async throws {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(timeIntervalSince1970: 1_000),
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = twoTaskIntervals()
        snapshot.transcriptRevision = 7
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        _ = try await source.runtimeChatReadContent(for: request(source, .chatReadTail))
        snapshot.transcript = Array(twoTaskIntervals().prefix(8))
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)
        let response = try await source.runtimeChatReadContent(for: request(source, .inputHistory(before: nil)))
        guard case .inputHistoryPage(let history) = response else { Issue.record("履歴ページではありません"); return }
        #expect(history.entries.map(\.id) == ["first"])
        await #expect(throws: SessionRuntimeContentError.notFound) {
            _ = try await source.runtimeChatReadContent(for: request(source, .chatReadAround(inputID: "second")))
        }
    }

    @Test func aLiveTaskBeyondTheFirstRowsIsAddressableWithoutLoadingInterveningRows() async throws {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: at(1),
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.status = .running
        snapshot.transcript = liveDeepTask()
        snapshot.transcriptRevision = 7
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let first = try await readRows(source, inputID: "deep")
        let around = try await source.runtimeChatReadContent(for: request(source, .chatCardRowsAround(inputID: "deep", rowID: "task-80")))
        guard case .cardRowsPage(let selected) = around else { Issue.record("タスクページではありません"); return }
        #expect(first.card.activeRowID == "task-80")
        #expect(first.rows.count == 8)
        #expect(first.rows.count <= SessionRuntimeChatReadLimits.maximumItemsPerPage)
        #expect(first.rows.last?.id == "task-8")
        #expect(selected.rows.map(\.id) == ["task-80"])
    }

    @Test func shrinkingRowsClassifiesAnIssuedCursorAsStaleBeforeCheckingItsCurrentRange() async throws {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: at(1),
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = liveDeepTask()
        snapshot.transcriptRevision = 7
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let before = try await readRows(source, inputID: "deep")
        let cursor = try #require(before.nextCursor)
        snapshot.transcript[1] = .taskList(id: "deep-tasks", tasks: [
            .init(id: "80", title: "タスク80", status: .inProgress)
        ], timestamp: at(2))
        snapshot.transcriptRevision = 8
        try source.applyRuntimeSnapshot(snapshot)
        let after = try await readRows(source, inputID: "deep")
        let outOfRange = SessionRuntimeChatReadCursor(scopeID: cursor.scopeID, revision: after.card.revision,
            index: cursor.index, anchorID: cursor.anchorID)
        let wrongScope = SessionRuntimeChatReadCursor(scopeID: "rows:other", revision: cursor.revision,
            index: cursor.index, anchorID: cursor.anchorID)
        let negative = SessionRuntimeChatReadCursor(scopeID: cursor.scopeID, revision: cursor.revision,
            index: -1, anchorID: cursor.anchorID)

        #expect(after.rows.map(\.id) == ["task-80"])
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            _ = try await source.runtimeChatReadContent(for: request(source, .chatCardRows(inputID: "deep", cursor: cursor)))
        }
        await #expect(throws: SessionRuntimeContentError.invalidRequest) {
            _ = try await source.runtimeChatReadContent(for: request(source, .chatCardRows(inputID: "deep", cursor: outOfRange)))
        }
        await #expect(throws: SessionRuntimeContentError.invalidRequest) {
            _ = try await source.runtimeChatReadContent(for: request(source, .chatCardRows(inputID: "deep", cursor: wrongScope)))
        }
        await #expect(throws: SessionRuntimeContentError.invalidRequest) {
            _ = try await source.runtimeChatReadContent(for: request(source, .chatCardRows(inputID: "deep", cursor: negative)))
        }
    }

    private func liveDeepTask() -> [ChatItem] {
        [
            .userMessage(id: "deep", text: "多数のタスク", timestamp: at(1), attachments: []),
            .taskList(id: "deep-tasks", tasks: (1...80).map {
                .init(id: "\($0)", title: "タスク\($0)", status: $0 == 80 ? .inProgress : .pending)
            }, timestamp: at(2)),
            .commandExecution(id: "deep-work", command: "echo running", output: "実行中", timestamp: at(3))
        ]
    }

    @Test func anItemJumpStartsAtItsActualCardEvenWithMoreThanAPageOfReasoningBeforeIt() async throws {
        let source = owner(items: wideInterval())
        let response = try await source.runtimeChatReadContent(for: request(source, .chatReadAroundItem(itemID: "deep-command")))
        guard case .chatReadPage(let page) = response else { Issue.record("会話ページではありません"); return }
        #expect(page.blocks.map(\.id) == ["status-card-wide", "wide-answer"])
        #expect(page.revealTarget?.cardID == "status-card-wide")
        #expect(page.revealTarget?.rowID == "outside-wide-reasoning-1")
        #expect(page.revealTarget?.entryID == "deep-command")
        #expect(page.revealTarget?.inputID == "wide")
    }

    @Test func anItemJumpToReasoningRevealsItsCardAndExactEntry() async throws {
        let source = owner(items: wideInterval())
        let response = try await source.runtimeChatReadContent(for: request(source, .chatReadAroundItem(itemID: "wide-reasoning-68")))
        guard case .chatReadPage(let page) = response else { Issue.record("会話ページではありません"); return }
        #expect(page.blocks.map(\.id) == ["status-card-wide", "wide-answer"])
        #expect(page.revealTarget?.cardID == "status-card-wide")
        #expect(page.revealTarget?.rowID == "outside-wide-reasoning-1")
        #expect(page.revealTarget?.entryID == "wide-reasoning-68")
        #expect(page.revealTarget?.itemID == "wide-reasoning-68")
        #expect(page.revealTarget?.inputID == "wide")
    }

    private func wideInterval() -> [ChatItem] {
        [.userMessage(id: "wide", text: "長い思考の後に実行", timestamp: at(1), attachments: [],
            turnEnd: .init(outcome: .completed, at: at(100)))]
        + (1...70).map { .reasoning(id: "wide-reasoning-\($0)", text: "思考\($0)", timestamp: at(Double($0 + 1))) }
        + [done("deep-command", 80), .agentMessage(id: "wide-answer", text: "完了しました", timestamp: at(101))]
    }

    private func allActionItems(_ source: ChatSessionViewModel, inputID: String, actionID: String) async throws -> [SessionRuntimeChatItemReference] {
        var items: [SessionRuntimeChatItemReference] = []
        var cursor: SessionRuntimeChatReadCursor?
        repeat {
            let response = try await source.runtimeChatReadContent(for: request(source,
                .chatActionItems(inputID: inputID, actionID: actionID, cursor: cursor)))
            guard case .actionItemsPage(let page) = response else { throw ReadError.unexpected }
            try #require(JSONEncoder().encode(response).count <= SessionRuntimeChatReadLimits.maximumResponseBytes)
            if let previous = cursor, let next = page.nextCursor { try #require(next.index > previous.index) }
            items.append(contentsOf: page.items)
            cursor = page.nextCursor
        } while cursor != nil
        return items
    }

    private func readRows(_ source: ChatSessionViewModel, inputID: String) async throws -> SessionRuntimeCardRowsPage {
        let response = try await source.runtimeChatReadContent(for: request(source, .chatCardRows(inputID: inputID, cursor: nil)))
        guard case .cardRowsPage(let page) = response else { throw ReadError.unexpected }
        return page
    }

    private func readEntries(_ source: ChatSessionViewModel, inputID: String, rowID: String) async throws -> SessionRuntimeCardEntriesPage {
        let response = try await source.runtimeChatReadContent(for: request(source, .chatRowEntries(inputID: inputID, rowID: rowID, cursor: nil)))
        guard case .cardEntriesPage(let page) = response else { throw ReadError.unexpected }
        return page
    }

    private func task(_ id: String, _ status: AgentTaskStatus) -> AgentTaskItem { .init(id: id, title: "タスク\(id)", status: status) }
    private func at(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1_000 + seconds) }
    private func done(_ id: String, _ seconds: Double) -> ChatItem {
        .commandExecution(id: id, command: "echo \(id)", output: "終了", timestamp: at(seconds), completedAt: at(seconds + 1))
    }

    private func twoTaskIntervals() -> [ChatItem] {
        [
            .userMessage(id: "first", text: "最初", timestamp: at(1), attachments: [], turnEnd: .init(outcome: .completed, at: at(10))),
            .taskList(id: "s1", tasks: [task("A", .pending), task("B", .pending)], timestamp: at(2)),
            .taskList(id: "s2", tasks: [task("A", .inProgress), task("B", .pending)], timestamp: at(3)),
            done("work-A", 4),
            .taskList(id: "s3", tasks: [task("A", .completed), task("B", .inProgress)], timestamp: at(5)),
            done("work-B", 6),
            .taskList(id: "s4", tasks: [task("B", .completed), task("A", .completed)], timestamp: at(7)),
            .agentMessage(id: "first-answer", text: "最初の回答", timestamp: at(11)),
            .userMessage(id: "second", text: "次", timestamp: at(12), attachments: [], turnEnd: .init(outcome: .completed, at: at(20))),
            done("second-work", 14),
            .agentMessage(id: "second-answer", text: "次の回答", timestamp: at(21))
        ]
    }

    private func changedAndReturnedTasks() -> [ChatItem] {
        [
            .taskList(id: "baseline", tasks: [task("A", .completed), task("B", .pending), task("C", .completed)], timestamp: at(1)),
            .userMessage(id: "changed", text: "変更", timestamp: at(2), attachments: [], turnEnd: .init(outcome: .completed, at: at(30))),
            done("before", 3),
            .taskList(id: "open", tasks: [task("A", .inProgress), task("B", .pending), task("C", .completed)], timestamp: at(4)),
            done("during", 5),
            .taskList(id: "returned", tasks: [task("C", .completed), task("A", .completed)], timestamp: at(6)),
            done("after", 7)
        ]
    }

    private func largeInlineReplies() -> [ChatItem] {
        (0..<80).map { .agentMessage(id: "reply-\($0)", text: String(repeating: "a", count: 7_500), timestamp: at(Double($0))) }
    }

    private func giantDescriptors() -> [ChatItem] {
        [
            .userMessage(id: "giant-task", text: "巨大", timestamp: at(1), attachments: [], turnEnd: .init(outcome: .completed, at: at(30))),
            .taskList(id: "huge-task", tasks: [.init(id: "huge", title: String(repeating: "巨大タスク", count: 100_000), status: .inProgress)], timestamp: at(2)),
            .commandExecution(id: "huge-command", command: String(repeating: "echo x ", count: 100_000), output: "終了", timestamp: at(3), completedAt: at(4))
        ]
    }

    private enum ReadError: Error { case unexpected }

    private func owner(items: [ChatItem]) -> ChatSessionViewModel {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: Date(timeIntervalSince1970: 1_000),
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = items
        snapshot.transcriptRevision = 7
        return ChatSessionViewModel(projection: snapshot) { _, _ in .none }
    }

    private func request(_ source: ChatSessionViewModel, _ target: SessionRuntimeContentRequest.Target) -> SessionRuntimeContentRequest {
        .init(sessionID: source.id, executionID: source.executionID, target: target)
    }

    private func longSingleInput() -> [ChatItem] {
        [.userMessage(id: "input", text: "確認", timestamp: Date(timeIntervalSince1970: 1_000), attachments: [],
            turnEnd: .init(outcome: .completed, at: Date(timeIntervalSince1970: 1_300)))]
        + (1...125).map { number in
            .commandExecution(id: "work-\(number)", command: "Read file-\(number).swift", output: "内容",
                timestamp: Date(timeIntervalSince1970: 1_000 + Double(number)),
                completedAt: Date(timeIntervalSince1970: 1_001 + Double(number)))
        }
        + [.agentMessage(id: "answer", text: "確認しました", timestamp: Date(timeIntervalSince1970: 1_301))]
    }

    private func manyInputs() -> [ChatItem] {
        (1...85).map { number in
            .userMessage(id: "input-\(number)", text: "依頼\(number)",
                timestamp: Date(timeIntervalSince1970: 1_000 + Double(number)), attachments: [])
        }
    }
}
