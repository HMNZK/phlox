import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite @MainActor struct RuntimeReadTransactionTests {
    @Test func theFirstPublishedCardAlreadyContainsItsTaskRowsWithoutReadingClosedDetails() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        var requestedClosedDetails = false
        projected.runtimeContentLoader = { request in
            switch request.target {
            case .chatRowEntries, .chatRowEntriesAround, .chatActionItems, .chatActionItemsFrom: requestedClosedDetails = true
            default: break
            }
            return try await source.runtimeChatReadContent(for: request)
        }

        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.blocks.map(\.id) == ["input", "status-card-input"])
        #expect(projected.runtimeChatRead.cards["input"]?.rows.rows.map(\.id) == ["task-stage"])
        #expect(projected.runtimeChatRead.cards["input"]?.entries.isEmpty == true)
        #expect(projected.runtimeChatRead.cards["input"]?.actions.isEmpty == true)
        #expect(!requestedClosedDetails)
    }

    @Test func backgroundRefreshRetainsBothEndsOfAnExpandedTimeline() async throws {
        let source = conversation(inputCount: 128)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let cursor = try #require(projected.runtimeChatRead.page?.olderCursor)
        try await projected.loadRuntimeChatRead(target: .chatReadBefore(cursor: cursor))
        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-78")
        #expect(projected.runtimeChatRead.page?.blocks.last?.id == "status-card-input-127")
        var changed = source.makeRuntimeSnapshot()
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }

        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.blocks.count == 100)
        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-78")
        #expect(projected.runtimeChatRead.page?.blocks.last?.id == "status-card-input-127")
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
    }

    @Test(arguments: [false, true])
    func backgroundRefreshPublishesUpdatedDetailsWithoutAnEmptyIntermediateWindow(bodyKeepsAdvancing: Bool) async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        let changed = changedSnapshot(source)
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        var exposedPartialPage = false
        var responseRevision = 8
        projected.runtimeContentLoader = { request in
            switch request.target {
            case .chatCardRows, .chatCardRowsAround, .chatRowEntries, .chatRowEntriesAround, .chatActionItems, .chatActionItemsFrom:
                exposedPartialPage = exposedPartialPage || projected.runtimeChatRead.page?.transcriptRevision != 7
                    || projected.runtimeChatRead.cards["input"]?.entries["task-stage"] == nil
                    || projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id != "command-50"
            default: break
            }
            var responseSnapshot = changed
            responseSnapshot.transcriptRevision = responseRevision
            if bodyKeepsAdvancing {
                responseSnapshot.transcript[121] = .commandExecution(id: "command-119", command: "Read file-119.txt",
                    output: "継続更新 \(responseRevision)", timestamp: .distantPast, completedAt: .distantFuture, intent: nil)
                responseRevision += 1
            }
            let current = ChatSessionViewModel(projection: responseSnapshot) { _, _ in .none }
            return try await current.runtimeChatReadContent(for: request)
        }

        try await projected.refreshRuntimeChatRead()

        let cache = try #require(projected.runtimeChatRead.cards["input"])
        #expect(!exposedPartialPage)
        #expect(cache.rows.card.contentRevision >= 8)
        #expect(cache.entries["task-stage"]?.entries.map(\.id) == ["command-0"])
        #expect(cache.actions["command-0"]?.items.first?.id == "command-50")
        #expect(cache.actions["command-0"]?.items.last?.id == "command-99")
        #expect(cache.actions["command-0"]?.items.contains(where: {
            if case .inline(.commandExecution("command-60", _, let output, _, _, _)) = $0 { output == "新しい実行結果" }
            else { false }
        }) == true)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func backgroundRefreshUpdatesAnOlderEntryWindowWithoutReturningItToTheTail() async throws {
        let reasoning: [ChatItem] = (0..<120).map {
            .reasoning(id: "reason-\($0)", text: "作業記録 \($0)", timestamp: .distantPast)
        }
        let source = source(items: [
            .userMessage(id: "input", text: "作業の記録", timestamp: .distantPast, attachments: []),
            .taskList(id: "tasks", tasks: [.init(id: "stage", title: "作業工程", status: .inProgress)], timestamp: .distantPast),
        ] + reasoning)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        try await projected.loadRuntimeCardRows("input")
        try await projected.loadRuntimeCardEntries("input", rowID: "task-stage")
        try await projected.loadRuntimeCardEntries("input", rowID: "task-stage", next: true)
        #expect(projected.runtimeChatRead.cards["input"]?.entries["task-stage"]?.entries.first?.id == "reason-20")
        #expect(projected.runtimeChatRead.cards["input"]?.entries["task-stage"]?.entries.last?.id == "reason-69")
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[62] = .reasoning(id: "reason-60", text: "更新後の作業記録", timestamp: .distantPast)
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }

        try await projected.refreshRuntimeChatRead()

        let entries = try #require(projected.runtimeChatRead.cards["input"]?.entries["task-stage"]?.entries)
        #expect(entries.first?.id == "reason-20")
        #expect(entries.last?.id == "reason-69")
        #expect(entries.contains(where: {
            if case .item(.inline(.reasoning("reason-60", let text, _))) = $0 { text == "更新後の作業記録" }
            else { false }
        }))
        #expect(projected.runtimeChatRead.cards["input"]?.entryIsLatest["task-stage"] == false)
    }

    @Test func aDetailFailureDoesNotPublishANewTimelineWithOldOrMissingDetails() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        let updated = ChatSessionViewModel(projection: changedSnapshot(source)) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        projected.runtimeContentLoader = { request in
            switch request.target {
            case .chatActionItems, .chatActionItemsFrom: throw URLError(.networkConnectionLost)
            default: break
            }
            return try await updated.runtimeChatReadContent(for: request)
        }

        await #expect(throws: URLError.self) { try await projected.refreshRuntimeChatRead() }

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 7)
        #expect(projected.runtimeChatRead.cards["input"]?.rows.card.contentRevision == 7)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-50")
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.contains(where: {
            if case .inline(.commandExecution("command-60", _, let output, _, _, _)) = $0 { output == "実行結果 60" }
            else { false }
        }) == true)
        #expect(projected.runtimeChatRead.error != nil)
    }

    @Test func oneRenderedOwnerRefreshesOnlyItsCompleteSlice() async throws {
        let pair = try await expandedConversation()
        pair.projected.runtimeChatRead.control.renderedSpans[UUID()] = span(pair.projected,
            first: "input-100", last: "status-card-input-123", count: 48)

        try await pair.projected.refreshRuntimeChatRead()

        #expect(pair.projected.runtimeChatRead.page?.blocks.count == 48)
        #expect(pair.projected.runtimeChatRead.page?.blocks.first?.id == "input-100")
        #expect(pair.projected.runtimeChatRead.page?.blocks.last?.id == "status-card-input-123")
        #expect(pair.projected.runtimeChatRead.cards["input-78"] == nil)
        #expect(pair.projected.runtimeChatRead.page?.olderCursor != nil)
        #expect(pair.projected.runtimeChatRead.page?.newerCursor != nil)
    }

    @Test func multipleRenderedOwnersKeepTheSharedBoundedWindow() async throws {
        let pair = try await expandedConversation()
        pair.projected.runtimeChatRead.control.renderedSpans[UUID()] = span(pair.projected,
            first: "input-100", last: "status-card-input-123", count: 48)
        pair.projected.runtimeChatRead.control.renderedSpans[UUID()] = span(pair.projected,
            first: "input-80", last: "status-card-input-90", count: 22)

        try await pair.projected.refreshRuntimeChatRead()

        #expect(pair.projected.runtimeChatRead.page?.blocks.count == 100)
        #expect(pair.projected.runtimeChatRead.page?.blocks.first?.id == "input-78")
        #expect(pair.projected.runtimeChatRead.page?.blocks.last?.id == "status-card-input-127")
    }

    @Test func removingAnOldOwnerCannotEraseTheReplacementControlSlice() async throws {
        let pair = try await expandedConversation()
        let owner = UUID()
        let oldControl = pair.projected.runtimeChatRead.control
        oldControl.renderedSpans[owner] = span(pair.projected,
            first: "input-100", last: "status-card-input-123", count: 48)
        pair.projected.runtimeSupportsChatReadModel = false
        pair.projected.runtimeSupportsChatReadModel = true
        try await pair.projected.loadRuntimeChatRead(target: .chatReadAround(inputID: "input-78"))
        pair.projected.runtimeChatRead.control.renderedSpans[owner] = span(pair.projected,
            first: "input-80", last: "status-card-input-90", count: 22)

        oldControl.renderedSpans.removeValue(forKey: owner)
        try await pair.projected.refreshRuntimeChatRead()

        #expect(pair.projected.runtimeChatRead.page?.blocks.count == 22)
        #expect(pair.projected.runtimeChatRead.page?.blocks.first?.id == "input-80")
        #expect(pair.projected.runtimeChatRead.page?.blocks.last?.id == "status-card-input-90")
    }

    @Test func aManualRowMoveWinsOverABackgroundTransactionThatIsStillReadingTheTimeline() async throws {
        let tasks = (0..<12).map {
            AgentTaskItem(id: "stage-\($0)", title: "工程 \($0)", status: $0 == 0 ? .inProgress : .pending)
        }
        let source = source(items: [
            .userMessage(id: "input", text: "工程を表示", timestamp: .distantPast, attachments: []),
            .taskList(id: "tasks", tasks: tasks, timestamp: .distantPast),
        ])
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        try await projected.loadRuntimeCardRows("input", navigation: .first)
        var changed = source.makeRuntimeSnapshot()
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        let reply = try await updated.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .chatReadTail))
        let held = HeldTransactionTimeline()
        var holdsFirstTail = true
        projected.runtimeContentLoader = { request in
            if holdsFirstTail, case .chatReadTail = request.target {
                holdsFirstTail = false
                return try await held.response()
            }
            return try await updated.runtimeChatReadContent(for: request)
        }
        let refreshing = Task { try await projected.refreshRuntimeChatRead() }
        await held.waitForRequest()

        let release = Task { held.release(reply) }
        try await projected.loadRuntimeCardRows("input", navigation: .next)
        await release.value
        try await refreshing.value
        let deadline = ContinuousClock.now + .seconds(3)
        while projected.runtimeChatRead.page?.transcriptRevision != 8, ContinuousClock.now < deadline { await Task.yield() }

        #expect(projected.runtimeChatRead.cards["input"]?.rows.rows.first?.id == "task-stage-8")
        #expect(projected.runtimeChatRead.cards["input"]?.isRowWindowManual == true)
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
    }

    @Test func aCancelledExplicitJumpHasNoAppliedTargetForTheViewToScrollTo() async throws {
        let pair = try await expandedConversation()
        let projected = pair.projected
        let previousApplied = projected.runtimeChatRead.appliedIntentToken
        let pending = RuntimeChatPendingJump(itemID: "input-0", epoch: projected.runtimeChatRead.epoch,
            intentToken: UUID())
        let reply = try await pair.source.runtimeChatReadContent(for: .init(sessionID: pair.source.id,
            executionID: pair.source.executionID, target: .chatReadAroundItem(itemID: "input-0")))
        let held = HeldTransactionTimeline()
        var holdsJump = true
        projected.runtimeContentLoader = { request in
            if holdsJump, case .chatReadAroundItem(let id) = request.target, id == "input-0" {
                holdsJump = false
                return try await held.response()
            }
            return try await pair.source.runtimeChatReadContent(for: request)
        }
        let jumping = Task { try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0"), intentToken: pending.intentToken) }
        await held.waitForRequest()

        let release = Task { held.release(reply) }
        try await projected.loadRuntimeCardRows("input-127", navigation: .first)
        await release.value
        try await jumping.value

        #expect(projected.runtimeChatRead.appliedIntentToken == previousApplied)
        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-78")
        #expect(pending.appliedTarget(in: projected.runtimeChatRead) == nil)
    }

    @Test func removedTaskDetailScopesDoNotPreventPublishingTheRemainingRows() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[1] = .taskList(id: "tasks", tasks: [.init(id: "replacement", title: "置き換えた工程", status: .inProgress)], timestamp: .distantPast)
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }

        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.cards["input"]?.rows.rows.map(\.id) == ["task-replacement"])
        #expect(projected.runtimeChatRead.cards["input"]?.entries["task-stage"] == nil)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"] == nil)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func removedActionsDoNotFreezeTheNewCardOrReviveTheOldOutput() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[2] = .commandExecution(id: "replacement-command", command: "Read replacement.txt", output: "置き換えた結果",
            timestamp: .distantPast, completedAt: .distantFuture, intent: nil)
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }

        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.cards["input"]?.entries["task-stage"]?.entries.map(\.id) == ["replacement-command"])
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"] == nil)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func insertingBeforeAnActionPageBoundaryKeepsTheSameManualItems() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        var changed = source.makeRuntimeSnapshot()
        changed.transcript.insert(.commandExecution(id: "inserted-command", command: "Read inserted.txt", output: "前へ挿入した結果",
            timestamp: .distantPast, completedAt: .distantFuture, intent: nil), at: 12)
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }

        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-50")
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.last?.id == "command-99")
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func rebasingAShortFinalActionPageKeepsItsFirstItemAndDoesNotAddOlderItems() async throws {
        let source = conversation(commandCount: 60)
        let projected = projection(source)
        try await prepareManualActionPage(projected, totalItems: 60)
        var changed = source.makeRuntimeSnapshot()
        changed.transcript.insert(.commandExecution(id: "inserted-command", command: "Read inserted.txt", output: "前へ挿入した結果",
            timestamp: .distantPast, completedAt: .distantFuture, intent: nil), at: 12)
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }

        try await projected.refreshRuntimeChatRead()

        let items = try #require(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items)
        #expect(items.count == 10)
        #expect(items.first?.id == "command-50")
        #expect(items.last?.id == "command-59")
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func followingTheTailMovesForwardAfterMoreThanAWindowOfNewBlocksArrives() async throws {
        let source = conversation(inputCount: 128)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let appended = conversation(inputCount: 640)
        var changed = source.makeRuntimeSnapshot()
        changed.transcript = appended.transcript
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }

        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.blocks.last?.id == "status-card-input-639")
        #expect(projected.runtimeChatRead.page?.blocks.count ?? 0 <= 400)
        #expect(projected.runtimeChatRead.page?.newerCursor == nil)
        #expect(projected.runtimeChatRead.followsTail)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func aChangedHistoryScopeReplacesTheOldManualPageWithoutRevivingRemovedInputs() async throws {
        let source = conversation(inputCount: 128)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        try await projected.loadRuntimeInputHistory(earlier: true)
        #expect(projected.runtimeChatRead.history?.entries.first?.id == "input-28")
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[128] = .userMessage(id: "replacement-64", text: "置き換えた依頼", timestamp: .distantPast, attachments: [])
        changed.transcript.swapAt(252, 254)
        changed.transcriptRevision = 8
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }

        try await projected.loadRuntimeInputHistory(refreshLatest: true)

        #expect(projected.runtimeChatRead.history?.revision == 2)
        #expect(projected.runtimeChatRead.history?.entries.first?.id == "input-78")
        #expect(projected.runtimeChatRead.history?.entries.last?.id == "input-126")
        #expect(projected.runtimeChatRead.history?.entries.contains(where: { $0.id == "input-64" }) == false)
        #expect(projected.runtimeChatRead.latestEntries.last?.id == "input-126")
        #expect(projected.runtimeChatRead.history?.totalCount == 128)
    }

    @Test func aFailedRepeatJumpIsNotConfirmedByTheOldTargetsBackgroundRefresh() async throws {
        let source = conversation(inputCount: 128)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let oldToken = UUID()
        try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0"), intentToken: oldToken)
        let pending = RuntimeChatPendingJump(itemID: "input-0", epoch: projected.runtimeChatRead.epoch, intentToken: UUID())
        projected.runtimeContentLoader = { _ in throw URLError(.networkConnectionLost) }

        await #expect(throws: URLError.self) {
            try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0"), intentToken: pending.intentToken)
        }
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }
        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.appliedIntentToken == oldToken)
        #expect(projected.runtimeChatRead.page?.revealTarget?.itemID == "input-0")
        #expect(pending.appliedTarget(in: projected.runtimeChatRead) == nil)
    }

    @Test func aSuccessfulJumpRemainsConfirmedWhenItsBackgroundRefreshPublishesFirst() async throws {
        let source = conversation(inputCount: 128)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let pending = RuntimeChatPendingJump(itemID: "input-0", epoch: projected.runtimeChatRead.epoch, intentToken: UUID())

        try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0"), intentToken: pending.intentToken)
        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.appliedIntentToken == pending.intentToken)
        #expect(pending.appliedTarget(in: projected.runtimeChatRead)?.itemID == "input-0")
    }

    @Test func aHintFromTheWaitingOldPageCannotCropTheNewlyCommittedNavigation() async throws {
        let pair = try await expandedConversation()
        let projected = pair.projected
        let reply = try await pair.source.runtimeChatReadContent(for: .init(sessionID: pair.source.id,
            executionID: pair.source.executionID, target: .chatReadAroundItem(itemID: "input-0")))
        let held = HeldTransactionTimeline()
        var holdsJump = true
        projected.runtimeContentLoader = { request in
            if holdsJump, case .chatReadAroundItem(let id) = request.target, id == "input-0" {
                holdsJump = false
                return try await held.response()
            }
            return try await pair.source.runtimeChatReadContent(for: request)
        }
        let token = UUID()
        let jumping = Task { try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0"), intentToken: token) }
        await held.waitForRequest()
        projected.runtimeChatRead.control.renderedSpans[UUID()] = span(projected,
            first: "input-100", last: "status-card-input-123", count: 48)
        held.release(reply)
        try await jumping.value

        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-0")
        #expect(projected.runtimeChatRead.appliedIntentToken == token)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test(arguments: [false, true])
    func cancelledEdgeOrLatestRequestsDoNotAuthorizeTheViewToMove(isLatest: Bool) async throws {
        let pair = try await expandedConversation()
        let projected = pair.projected
        let cursor = try #require(projected.runtimeChatRead.page?.olderCursor)
        let target: SessionRuntimeContentRequest.Target = isLatest ? .chatReadTail : .chatReadBefore(cursor: cursor)
        let reply = try await pair.source.runtimeChatReadContent(for: .init(sessionID: pair.source.id,
            executionID: pair.source.executionID, target: target))
        let held = HeldTransactionTimeline()
        var holdsFirst = true
        projected.runtimeContentLoader = { request in
            if holdsFirst { holdsFirst = false; return try await held.response() }
            return try await pair.source.runtimeChatReadContent(for: request)
        }
        let intent = RuntimeChatReadIntent(epoch: projected.runtimeChatRead.epoch, token: UUID())
        let moving = Task { try await projected.loadRuntimeChatRead(target: target, intentToken: intent.token) }
        await held.waitForRequest()

        let release = Task { held.release(reply) }
        try await projected.loadRuntimeCardRows("input-127", navigation: .first)
        await release.value
        try await moving.value

        #expect(!intent.isApplied(in: projected.runtimeChatRead))
        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-78")
    }

    @Test(arguments: [0, 1, 2])
    func deletingTheFirstRowOfAManualWindowRecoversToExistingRows(mode: Int) async throws {
        let tasks = (0..<12).map {
            AgentTaskItem(id: "stage-\($0)", title: "工程 \($0)", status: $0 == 0 ? .inProgress : .pending)
        }
        let source = source(items: [
            .userMessage(id: "input", text: "工程の更新", timestamp: .distantPast, attachments: []),
            .taskList(id: "tasks", tasks: tasks, timestamp: .distantPast),
        ])
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        switch mode {
        case 0: try await projected.loadRuntimeCardRows("input", navigation: .first)
        case 1: try await projected.loadRuntimeCardRows("input", navigation: .around("task-stage-8"))
        default:
            try await projected.loadRuntimeCardRows("input", navigation: .first)
            try await projected.loadRuntimeCardRows("input", navigation: .next)
        }
        let removed = mode == 0 ? "stage-0" : "stage-8"
        try await projected.loadRuntimeCardEntries("input", rowID: "task-" + removed)
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[1] = .taskList(id: "tasks", tasks: tasks.filter { $0.id != removed }, timestamp: .distantPast)
        changed.transcriptRevision = 8
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())

        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.cards["input"]?.rows.rows.first?.id == (mode == 0 ? "task-stage-1" : "task-stage-0"))
        #expect(projected.runtimeChatRead.cards["input"]?.entries["task-" + removed] == nil)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func theLastOverviewCatchesUpAfterAManualOperationCancelsItsBackgroundRead() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let tasks = (0..<12).map {
            AgentTaskItem(id: "stage-\($0)", title: "工程 \($0)", status: $0 == 8 ? .inProgress : .pending)
        }
        let source = source(items: [
            .userMessage(id: "input", text: "最後の更新", timestamp: started, attachments: []),
            .taskList(id: "tasks", tasks: tasks, timestamp: started),
        ])
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        try await projected.loadRuntimeCardRows("input", navigation: .around("task-stage-8"))
        var changed = source.makeRuntimeSnapshot()
        changed.transcript = [
            .userMessage(id: "input", text: "最後の更新", timestamp: started, attachments: [],
                turnEnd: .init(outcome: .completed, at: started.addingTimeInterval(10))),
            .taskList(id: "tasks", tasks: tasks.map { .init(id: $0.id, title: $0.title, status: .completed) }, timestamp: started),
        ]
        changed.transcriptRevision = 8
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        let response = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .chatReadTail))
        let held = HeldTransactionTimeline()
        var holdsFirstTail = true
        projected.runtimeContentLoader = { request in
            if holdsFirstTail, case .chatReadTail = request.target {
                holdsFirstTail = false
                return try await held.response()
            }
            if request.target.requiresChatReadModel { return try await source.runtimeChatReadContent(for: request) }
            return try source.runtimeContent(for: request)
        }
        let background = Task { try await projected.refreshRuntimeContent() }
        await held.waitForRequest()

        let release = Task { held.release(response) }
        await #expect(throws: SessionRuntimeContentError.staleContent) {
            try await projected.loadRuntimeCardRows("input", navigation: .around("task-stage-8"))
        }
        await release.value
        try await background.value
        let deadline = ContinuousClock.now + .seconds(3)
        while projected.runtimeChatRead.page?.transcriptRevision != 8, ContinuousClock.now < deadline { await Task.yield() }

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.cards["input"]?.rows.card.header.state == .completed)
        #expect(projected.runtimeChatRead.cards["input"]?.rows.rows.first?.id == "task-stage-8")
        #expect(projected.runtimeChatRead.cards["input"]?.isRowWindowManual == true)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func aFailedDetailRetryKeepsTheOldDetailsAndASuccessfulRetryClearsItsError() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        projected.runtimeContentLoader = { _ in throw URLError(.networkConnectionLost) }

        await #expect(throws: URLError.self) {
            try await projected.loadRuntimeActionItems("input", actionID: "command-0")
        }
        #expect(projected.runtimeChatRead.cards["input"]?.error != nil)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-50")
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }
        try await projected.loadRuntimeActionItems("input", actionID: "command-0")

        #expect(projected.runtimeChatRead.cards["input"]?.error == nil)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-0")
    }

    @Test func aSuccessfulRowReadDoesNotEraseTheFailedActionDetail() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        projected.runtimeContentLoader = { _ in throw URLError(.networkConnectionLost) }
        await #expect(throws: URLError.self) {
            try await projected.loadRuntimeActionItems("input", actionID: "command-0")
        }
        let failure = try #require(projected.runtimeChatRead.cards["input"]?.error)
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }

        try await projected.loadRuntimeCardRows("input", navigation: .first)
        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.cards["input"]?.error == failure)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-50")
    }

    @Test func aRetryStillPublishesWhileOnlyTheBodyRevisionAdvances() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        projected.runtimeContentLoader = { _ in throw URLError(.networkConnectionLost) }
        await #expect(throws: URLError.self) {
            try await projected.loadRuntimeActionItems("input", actionID: "command-0")
        }
        let reply = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .chatActionItems(inputID: "input", actionID: "command-0", cursor: nil)))
        let held = HeldTransactionTimeline()
        projected.runtimeContentLoader = { _ in try await held.response() }
        let retry = Task { try await projected.loadRuntimeActionItems("input", actionID: "command-0") }
        await held.waitForRequest()
        var changed = changedSnapshot(source)
        changed.transcriptRevision = 9
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        changed.transcriptRevision = 10
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        held.release(reply)
        try await retry.value

        #expect(projected.runtimeChatRead.cards["input"]?.error == nil)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-0")
    }

    @Test func aSessionDisappearingAfterAChild404DoesNotPublishAPartialCard() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        let updated = ChatSessionViewModel(projection: changedSnapshot(source)) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        var childDisappeared = false
        projected.runtimeContentLoader = { request in
            if childDisappeared { throw SessionRuntimeContentError.notFound }
            if case .chatRowEntries = request.target { childDisappeared = true; throw SessionRuntimeContentError.notFound }
            if case .chatRowEntriesAround = request.target { childDisappeared = true; throw SessionRuntimeContentError.notFound }
            return try await updated.runtimeChatReadContent(for: request)
        }

        await #expect(throws: SessionRuntimeContentError.notFound) { try await projected.refreshRuntimeChatRead() }

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 7)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-50")
        #expect(projected.runtimeChatRead.error != nil)
    }

    @Test func aRemovedWindowEndRefreshesFromTheSameInputInsteadOfRemainingStale() async throws {
        let source = conversation(inputCount: 128)
        let projected = projection(source)
        try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0"))
        #expect(projected.runtimeChatRead.page?.blocks.last?.id == "status-card-input-24")
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[49] = .agentMessage(id: "replacement-answer", text: "更新後の返答", timestamp: .distantPast)
        changed.transcriptRevision = 8
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())

        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-0")
        #expect(projected.runtimeChatRead.page?.blocks.last?.id == "replacement-answer")
        #expect(projected.runtimeChatRead.page?.blocks.count == 50)
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.anchorItemID == "input-0")
        #expect(!projected.runtimeChatRead.followsTail)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func aRemovedBackgroundAnchorReturnsToTheTailForTheFollowingRefreshToo() async throws {
        let source = conversation(inputCount: 128)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0"))
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[0] = .userMessage(id: "replacement-0", text: "置き換えた依頼", timestamp: .distantPast, attachments: [])
        changed.transcript[1] = .commandExecution(id: "replacement-work", command: "echo replacement", output: "置き換えた結果",
            timestamp: .distantPast, completedAt: .distantFuture, intent: nil)
        changed.transcriptRevision = 8
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())

        try await projected.refreshRuntimeChatRead()
        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.followsTail)
        #expect(projected.runtimeChatRead.anchorItemID == nil)
        #expect(projected.runtimeChatRead.anchorInputID == nil)
        #expect(projected.runtimeChatRead.page?.blocks.last?.id == "status-card-input-127")
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func anOlderSuccessCannotReplaceTheDetailsOrErrorOfANewerFailedRead() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        let held = HeldTransactionTimeline()
        let nextCursor = try #require(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.nextCursor)
        let reply = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .chatActionItems(inputID: "input", actionID: "command-0", cursor: nextCursor)))
        projected.runtimeContentLoader = { request in
            if case .chatActionItems(_, _, let cursor) = request.target, cursor != nil { return try await held.response() }
            throw URLError(.networkConnectionLost)
        }
        let older = Task { try await projected.loadRuntimeActionItems("input", actionID: "command-0", next: true) }
        await held.waitForRequest()
        let newer = Task { try await projected.loadRuntimeActionItems("input", actionID: "command-0") }
        let deadline = ContinuousClock.now + .seconds(3)
        while projected.runtimeChatRead.control.activeCardOperations < 2, ContinuousClock.now < deadline { await Task.yield() }
        held.release(reply)
        try await older.value
        await #expect(throws: URLError.self) { try await newer.value }

        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-50")
        #expect(projected.runtimeChatRead.cards["input"]?.error != nil)
    }

    @Test func anOlderFailureCannotReplaceTheSuccessfulDetailsOfANewerRead() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        let held = HeldTransactionTimeline()
        projected.runtimeContentLoader = { request in
            if case .chatActionItems(_, _, let cursor) = request.target, cursor != nil { return try await held.response() }
            return try await source.runtimeChatReadContent(for: request)
        }
        let older = Task { try await projected.loadRuntimeActionItems("input", actionID: "command-0", next: true) }
        await held.waitForRequest()
        let newer = Task { try await projected.loadRuntimeActionItems("input", actionID: "command-0") }
        let deadline = ContinuousClock.now + .seconds(3)
        while projected.runtimeChatRead.control.activeCardOperations < 2, ContinuousClock.now < deadline { await Task.yield() }
        held.reject(URLError(.networkConnectionLost))
        try await older.value
        try await newer.value

        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-0")
        #expect(projected.runtimeChatRead.cards["input"]?.error == nil)
    }

    @Test func anExplicitStaleReadRejoinsOneContentRefresh() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        let updated = ChatSessionViewModel(projection: changedSnapshot(source)) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        var tailReads = 0
        projected.runtimeContentLoader = { request in
            if case .chatActionItems(_, _, let cursor) = request.target, cursor != nil { throw SessionRuntimeContentError.staleContent }
            if case .chatReadTail = request.target { tailReads += 1 }
            if request.target.requiresChatReadModel { return try await updated.runtimeChatReadContent(for: request) }
            return try updated.runtimeContent(for: request)
        }

        await #expect(throws: SessionRuntimeContentError.staleContent) {
            try await projected.loadRuntimeActionItems("input", actionID: "command-0", next: true)
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while projected.runtimeChatRead.control.catchUpScheduled, ContinuousClock.now < deadline { await Task.yield() }

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-50")
        #expect(projected.runtimeChatRead.cards["input"]?.error == nil)
        #expect(projected.runtimeChatRead.error == nil)
        #expect(tailReads == 1)
    }

    @Test func aSecondStaleDuringRecoveryKeepsTheDisplayAndWaitsForTheNextNormalRefresh() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await prepareManualActionPage(projected)
        let updated = ChatSessionViewModel(projection: changedSnapshot(source)) { _, _ in .none }
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        var tailReads = 0
        projected.runtimeContentLoader = { request in
            switch request.target {
            case .chatActionItems, .chatActionItemsFrom: throw SessionRuntimeContentError.staleContent
            case .chatReadTail: tailReads += 1
            default: break
            }
            if request.target.requiresChatReadModel { return try await updated.runtimeChatReadContent(for: request) }
            return try updated.runtimeContent(for: request)
        }

        await #expect(throws: SessionRuntimeContentError.staleContent) {
            try await projected.loadRuntimeActionItems("input", actionID: "command-0", next: true)
        }
        let deadline = ContinuousClock.now + .seconds(3)
        while projected.runtimeChatRead.control.catchUpScheduled, ContinuousClock.now < deadline { await Task.yield() }
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 7)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-50")
        #expect(projected.runtimeChatRead.error == nil)
        #expect(tailReads == 1)
        projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }
        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func replacingARowClearsItsFailedFirstDetailReadAfterTheNewCardPublishes() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        projected.runtimeContentLoader = { _ in throw URLError(.networkConnectionLost) }
        await #expect(throws: URLError.self) {
            try await projected.loadRuntimeCardEntries("input", rowID: "task-stage")
        }
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[1] = .taskList(id: "tasks", tasks: [.init(id: "replacement", title: "置き換えた工程", status: .inProgress)], timestamp: .distantPast)
        changed.transcriptRevision = 8
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }

        try await projected.refreshRuntimeChatRead()
        try await projected.loadRuntimeCardEntries("input", rowID: "task-replacement")
        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.cards["input"]?.rows.rows.map(\.id) == ["task-replacement"])
        #expect(projected.runtimeChatRead.cards["input"]?.entries["task-stage"] == nil)
        #expect(projected.runtimeChatRead.cards["input"]?.error == nil)
    }

    @Test func replacingAnActionClearsItsFailedFirstDetailReadAfterTheNewCardPublishes() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        try await projected.loadRuntimeCardEntries("input", rowID: "task-stage")
        projected.runtimeContentLoader = { _ in throw URLError(.networkConnectionLost) }
        await #expect(throws: URLError.self) {
            try await projected.loadRuntimeActionItems("input", actionID: "command-0")
        }
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[2] = .commandExecution(id: "replacement-command", command: "Read replacement.txt", output: "置き換えた結果",
            timestamp: .distantPast, completedAt: .distantFuture, intent: nil)
        changed.transcriptRevision = 8
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await source.runtimeChatReadContent(for: $0) }

        try await projected.refreshRuntimeChatRead()
        try await projected.loadRuntimeCardEntries("input", rowID: "task-stage")
        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.cards["input"]?.entries["task-stage"]?.entries.map(\.id) == ["replacement-command"])
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"] == nil)
        #expect(projected.runtimeChatRead.cards["input"]?.error == nil)
    }

    @Test func aSurvivingRowWithAFailedFirstDetailReadKeepsItsErrorWhenReconfirmationFails() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        projected.runtimeContentLoader = { _ in throw URLError(.networkConnectionLost) }
        await #expect(throws: URLError.self) {
            try await projected.loadRuntimeCardEntries("input", rowID: "task-stage")
        }
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[1] = .taskList(id: "tasks", tasks: [.init(id: "stage", title: "更新した工程", status: .inProgress)], timestamp: .distantPast)
        changed.transcriptRevision = 8
        try source.applyRuntimeSnapshot(changed)
        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        projected.runtimeContentLoader = { request in
            if case .chatRowEntries = request.target { throw URLError(.networkConnectionLost) }
            return try await source.runtimeChatReadContent(for: request)
        }

        await #expect(throws: URLError.self) { try await projected.refreshRuntimeChatRead() }

        #expect(projected.runtimeChatRead.page?.transcriptRevision == 7)
        #expect(projected.runtimeChatRead.cards["input"]?.error == URLError(.networkConnectionLost).localizedDescription)
    }

    @Test func aLateParentVerificationFailureDoesNotReplaceANewerActionFailure() async throws {
        let source = conversation(commandCount: 120)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let held = HeldTransactionTimeline()
        projected.runtimeContentLoader = { request in
            switch request.target {
            case .chatRowEntries: return try await held.response()
            case .chatActionItems: throw URLError(.networkConnectionLost)
            case .chatReadTail: throw URLError(.notConnectedToInternet)
            default: return try await source.runtimeChatReadContent(for: request)
            }
        }
        let older = Task { try await projected.loadRuntimeCardEntries("input", rowID: "task-stage") }
        await held.waitForRequest()
        let newer = Task { try await projected.loadRuntimeActionItems("input", actionID: "command-0") }
        let deadline = ContinuousClock.now + .seconds(3)
        while projected.runtimeChatRead.control.activeCardOperations < 2, ContinuousClock.now < deadline { await Task.yield() }
        held.reject(SessionRuntimeContentError.notFound)
        await #expect(throws: URLError(.networkConnectionLost)) { try await newer.value }
        await #expect(throws: URLError(.notConnectedToInternet)) { try await older.value }

        #expect(projected.runtimeChatRead.cards["input"]?.failure?.target == .action("input", "command-0"))
        #expect(projected.runtimeChatRead.cards["input"]?.error == URLError(.networkConnectionLost).localizedDescription)
    }

    private func expandedConversation() async throws -> (source: ChatSessionViewModel, projected: ChatSessionViewModel) {
        let source = conversation(inputCount: 128)
        let projected = projection(source)
        try await projected.refreshRuntimeChatRead()
        let cursor = try #require(projected.runtimeChatRead.page?.olderCursor)
        try await projected.loadRuntimeChatRead(target: .chatReadBefore(cursor: cursor))
        return (source, projected)
    }

    private func span(_ projected: ChatSessionViewModel, first: String, last: String, count: Int) -> RuntimeChatRenderedSpan {
        RuntimeChatRenderedSpan(executionID: projected.executionID, epoch: projected.runtimeChatRead.epoch,
            intentToken: projected.runtimeChatRead.appliedIntentToken, firstID: first, lastID: last, count: count)
    }

    private func prepareManualActionPage(_ projected: ChatSessionViewModel, totalItems: Int = 120) async throws {
        try await projected.refreshRuntimeChatRead()
        try await projected.loadRuntimeCardRows("input")
        try await projected.loadRuntimeCardEntries("input", rowID: "task-stage")
        let action = try #require(projected.runtimeChatRead.cards["input"]?.entries["task-stage"]?.entries.first)
        guard case .action(let summary) = action else { Issue.record("読み取り作業の集約がありません"); return }
        try #require(summary.id == "command-0")
        try #require(summary.totalItemCount == totalItems)
        try await projected.loadRuntimeActionItems("input", actionID: "command-0")
        try await projected.loadRuntimeActionItems("input", actionID: "command-0", next: true)
        #expect(projected.runtimeChatRead.cards["input"]?.actions["command-0"]?.items.first?.id == "command-50")
    }

    private func changedSnapshot(_ source: ChatSessionViewModel) -> SessionRuntimeChatSnapshot {
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[62] = .commandExecution(id: "command-60", command: "Read file-60.txt", output: "新しい実行結果",
            timestamp: .distantPast, completedAt: .distantFuture, intent: nil)
        changed.transcriptRevision = 8
        return changed
    }

    private func conversation(commandCount: Int) -> ChatSessionViewModel {
        let commands: [ChatItem] = (0..<commandCount).map {
            .commandExecution(id: "command-\($0)", command: "Read file-\($0).txt", output: "実行結果 \($0)",
                timestamp: .distantPast, completedAt: .distantFuture, intent: nil)
        }
        return source(items: [
            .userMessage(id: "input", text: "作業を実行", timestamp: .distantPast, attachments: []),
            .taskList(id: "tasks", tasks: [.init(id: "stage", title: "作業工程", status: .inProgress)], timestamp: .distantPast),
        ] + commands)
    }

    private func conversation(inputCount: Int) -> ChatSessionViewModel {
        source(items: (0..<inputCount).flatMap { index -> [ChatItem] in
            [.userMessage(id: "input-\(index)", text: "依頼 \(index)", timestamp: .distantPast, attachments: []),
             .commandExecution(id: "work-\(index)", command: "echo \(index)", output: "実行結果",
                timestamp: .distantPast, completedAt: .distantFuture, intent: nil)]
        })
    }

    private func source(items: [ChatItem]) -> ChatSessionViewModel {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = items
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

@MainActor private final class HeldTransactionTimeline {
    private var request: CheckedContinuation<SessionRuntimeContentResponse, Error>?
    private var waiter: CheckedContinuation<Void, Never>?

    func response() async throws -> SessionRuntimeContentResponse {
        try await withCheckedThrowingContinuation { continuation in
            request = continuation
            waiter?.resume()
            waiter = nil
        }
    }

    func waitForRequest() async {
        if request != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func reject(_ error: Error) {
        request?.resume(throwing: error)
        request = nil
    }

    func release(_ response: SessionRuntimeContentResponse) {
        request?.resume(returning: response)
        request = nil
    }
}
