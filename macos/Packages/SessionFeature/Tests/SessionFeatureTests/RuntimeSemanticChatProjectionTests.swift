import AgentDomain
import Foundation
import StructuredChatKit
import Testing
import os
@testable import SessionFeature

@Suite @MainActor struct RuntimeSemanticChatProjectionTests {
    @Test func waitingForCardDetailsDoesNotInvalidateTheDisplayedConversation() async throws {
        let source = source(items: [
            .userMessage(id: "input", text: "表示中の作業", timestamp: .distantPast, attachments: []),
            .commandExecution(id: "work", command: "printf result", output: "完了",
                timestamp: .distantPast, completedAt: .distantFuture, intent: nil),
        ])
        let projected = projection(source)
        try await projected.refreshRuntimeContent()
        let response = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .chatCardRows(inputID: "input", cursor: nil)))
        let held = HeldReadResponse()
        projected.runtimeContentLoader = { _ in try await held.response() }
        let changed = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            _ = projected.runtimeChatRead.page
        } onChange: {
            changed.withLock { $0 = true }
        }

        let loading = Task { try await projected.loadRuntimeCardRows("input") }
        await held.waitForRequest()
        let invalidatedWhileWaiting = changed.withLock { $0 }
        held.release(response)
        try await loading.value

        #expect(!invalidatedWhileWaiting)
        #expect(changed.withLock { $0 })
        #expect(projected.runtimeChatRead.cards["input"]?.rows.card.totalRowCount == 1)
    }

    @Test func aLongSingleInputRetainsItsCardWithoutLoadingTheRawTranscript() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let input = ChatItem.userMessage(id: "request", text: "長い作業", timestamp: start,
            attachments: [], turnEnd: ChatTurnEnd(outcome: .completed, at: start.addingTimeInterval(300)))
        let work = (0..<120).map { number in
            ChatItem.commandExecution(id: "work-\(number)", command: "echo \(number)", output: "終了",
                timestamp: start.addingTimeInterval(Double(number + 1)),
                completedAt: start.addingTimeInterval(Double(number + 2)), intent: nil)
        }
        let source = source(items: [input] + work)
        let projected = projection(source)

        try await projected.refreshRuntimeContent()
        let page = try #require(projected.runtimeChatRead.page)
        let cards = page.blocks.compactMap { block -> SessionRuntimeCardSummary? in
            if case .card(let summary) = block.content { summary } else { nil }
        }

        #expect(cards.map(\.id) == ["status-card-request"])
        #expect(cards.first?.header.state == .completed)
        #expect(projected.inputHistoryEntries.map(\.id) == ["request"])
        #expect(projected.transcript.isEmpty)
    }

    @Test func inputHistoryAndOldestJumpDoNotDependOnLoadedBodyPages() async throws {
        let source = source(items: (0..<128).map {
            .userMessage(id: "input-\($0)", text: "依頼 \($0)", timestamp: .distantPast, attachments: [])
        })
        let projected = projection(source)
        try await projected.refreshRuntimeContent()

        try await projected.loadRuntimeInputHistory(earlier: true)
        try await projected.loadRuntimeInputHistory(earlier: true)
        try await projected.loadRuntimeChatRead(target: .chatReadAround(inputID: "input-0"))

        #expect(projected.runtimeChatRead.history?.totalCount == 128)
        #expect(projected.runtimeChatRead.historyEntries.first?.id == "input-0")
        #expect(projected.runtimeChatRead.latestEntries.count == 12)
        #expect(projected.runtimeChatRead.latestEntries.first?.id == "input-116")
        #expect(projected.runtimeChatRead.latestEntries.last?.id == "input-127")
        #expect(projected.runtimeChatRead.page?.blocks.contains(where: { $0.id == "input-0" }) == true)
        #expect(projected.runtimeChatRead.page?.blocks.count ?? 0 <= 50)
        #expect(projected.transcript.isEmpty)
    }

    @Test func refreshingDuringAnOldestItemJumpKeepsTheRequestedInputInsteadOfReturningToTail() async throws {
        let source = source(items: (0..<128).map {
            .userMessage(id: "input-\($0)", text: "依頼 \($0)", timestamp: .distantPast, attachments: [])
        })
        let projected = projection(source)
        try await projected.refreshRuntimeContent()
        let reply = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .chatReadAroundItem(itemID: "input-0")))
        var finalSnapshot = source.makeRuntimeSnapshot()
        finalSnapshot.transcriptRevision = 8
        let final = ChatSessionViewModel(projection: finalSnapshot) { _, _ in .none }
        let held = HeldReadResponse()
        var holdsFirstJump = true
        projected.runtimeContentLoader = { request in
            if holdsFirstJump, case .chatReadAroundItem = request.target {
                holdsFirstJump = false
                return try await held.response()
            }
            return try await final.runtimeChatReadContent(for: request)
        }
        let jump = Task { try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0")) }
        await held.waitForRequest()
        try projected.applyRuntimeOverview(final.makeRuntimeOverview())

        // refresh starts while the direct jump is still waiting on the runtime reply.
        let release = Task { held.release(reply) }
        try await projected.refreshRuntimeChatRead()
        await release.value
        try await jump.value

        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-0")
        #expect(projected.runtimeChatRead.page?.blocks.contains(where: { $0.id == "input-127" }) == false)
        #expect(projected.runtimeChatRead.page?.revealTarget?.itemID == "input-0")
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func aMissingJumpKeepsTheCommittedPositionAndAllowsTheNextBackgroundUpdate() async throws {
        let source = source(items: (0..<128).map {
            .userMessage(id: "input-\($0)", text: "依頼 \($0)", timestamp: .distantPast, attachments: [])
        })
        let projected = projection(source)
        try await projected.refreshRuntimeContent()
        try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0"))
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[1] = .userMessage(id: "input-1", text: "更新後の依頼", timestamp: .distantPast, attachments: [])
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }

        await #expect(throws: SessionRuntimeContentError.notFound) {
            try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "missing-input"))
        }
        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-0")
        #expect(projected.runtimeChatRead.error != nil)
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await updated.runtimeChatReadContent(for: $0) }
        try await projected.refreshRuntimeChatRead()

        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-0")
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.page?.blocks.contains(where: {
            if case .item(.inline(.userMessage(_, let text, _, _, _))) = $0.content { text == "更新後の依頼" }
            else { false }
        }) == true)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func backgroundUpdateWaitsForAFailedNavigationAndRefreshesTheCommittedPage() async throws {
        let source = source(items: [
            .userMessage(id: "input", text: "元の依頼", timestamp: .distantPast, attachments: []),
            .agentMessage(id: "answer", text: "元の回答", timestamp: .distantPast),
        ])
        let projected = projection(source)
        try await projected.refreshRuntimeContent()
        var changed = source.makeRuntimeSnapshot()
        changed.transcript[1] = .agentMessage(id: "answer", text: "更新後の回答", timestamp: .distantPast)
        changed.transcriptRevision = 8
        let updated = ChatSessionViewModel(projection: changed) { _, _ in .none }
        let held = HeldReadResponse()
        var holdsFirstJump = true
        projected.runtimeContentLoader = { request in
            if case .chatReadAroundItem = request.target {
                guard holdsFirstJump else { throw URLError(.networkConnectionLost) }
                holdsFirstJump = false
                return try await held.response()
            }
            return try await updated.runtimeChatReadContent(for: request)
        }
        let jump = Task { try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "unreachable-input")) }
        await held.waitForRequest()
        try projected.applyRuntimeOverview(updated.makeRuntimeOverview())

        let release = Task { held.reject(URLError(.networkConnectionLost)) }
        try await projected.refreshRuntimeChatRead()
        await release.value
        await #expect(throws: URLError.self) { try await jump.value }

        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input")
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
        #expect(projected.runtimeChatRead.page?.blocks.contains(where: {
            if case .item(.inline(.agentMessage(_, let text, _))) = $0.content { text == "更新後の回答" }
            else { false }
        }) == true)
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func aLaterExplicitJumpWinsWhenAnEarlierJumpReplyIsStillPending() async throws {
        let source = source(items: (0..<128).map {
            .userMessage(id: "input-\($0)", text: "依頼 \($0)", timestamp: .distantPast, attachments: [])
        })
        let projected = projection(source)
        try await projected.refreshRuntimeContent()
        let reply = try await source.runtimeChatReadContent(for: .init(sessionID: source.id,
            executionID: source.executionID, target: .chatReadAroundItem(itemID: "input-0")))
        let held = HeldReadResponse()
        projected.runtimeContentLoader = { request in
            if case .chatReadAroundItem(let itemID) = request.target, itemID == "input-0" {
                return try await held.response()
            }
            return try await source.runtimeChatReadContent(for: request)
        }
        let earlierJump = Task { try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-0")) }
        await held.waitForRequest()

        let release = Task { held.release(reply) }
        try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "input-100"))
        await release.value
        try await earlierJump.value

        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "input-100")
        #expect(projected.runtimeChatRead.page?.revealTarget?.itemID == "input-100")
        #expect(projected.runtimeChatRead.error == nil)
    }

    @Test func giantInputRecallUsesTheOriginalTextInsteadOfItsPreview() async throws {
        let text = String(repeating: "省略してはいけない入力。", count: 2_000)
        let source = source(items: [.userMessage(id: "giant", text: text, timestamp: .distantPast, attachments: [])])
        let projected = projection(source)
        projected.draft = "書きかけ"
        try await projected.refreshRuntimeContent()
        let preview = try #require(projected.inputHistoryEntries.first?.text)

        let accepted = projected.recallInputHistory(.older)
        try await waitForRecall(projected)

        #expect(accepted)
        #expect(preview != text)
        #expect(projected.draft == text)
        #expect(projected.transcript.isEmpty)
    }

    @Test func anOldExecutionCannotPublishAReadPageAfterReconnection() async throws {
        let old = source(items: [.userMessage(id: "old", text: "以前の依頼", timestamp: .distantPast, attachments: [])])
        var currentSnapshot = SessionRuntimeChatSnapshot(id: old.id, startedAt: old.startedAt,
            agentRef: old.agentRef, workingDirectory: "/workspace")
        currentSnapshot.transcript = [.userMessage(id: "current", text: "現在の依頼", timestamp: .distantPast, attachments: [])]
        currentSnapshot.transcriptRevision = 8
        let current = ChatSessionViewModel(projection: currentSnapshot) { _, _ in .none }
        let projected = projection(old)
        projected.runtimeContentLoader = { request in
            let response = try await old.runtimeChatReadContent(for: request)
            try projected.applyRuntimeOverview(current.makeRuntimeOverview())
            return response
        }

        try await projected.loadRuntimeChatRead(target: .chatReadTail)

        #expect(projected.executionID == current.executionID)
        #expect(projected.runtimeChatRead.page == nil)
        #expect(projected.runtimeChatRead.cards.isEmpty)
    }

    @Test func sameExecutionLateReadCatchesUpToTheFinalCompletionWithoutAnotherNotification() async throws {
        let started = Date(timeIntervalSince1970: 1_800_000_000)
        let old = source(items: [
            .userMessage(id: "input", text: "依頼", timestamp: started, attachments: []),
            .commandExecution(id: "command", command: "echo done", output: "", timestamp: started),
        ])
        var completed = old.makeRuntimeSnapshot()
        completed.transcript = [
            .userMessage(id: "input", text: "依頼", timestamp: started, attachments: [],
                turnEnd: ChatTurnEnd(outcome: .completed, at: started.addingTimeInterval(9))),
            .commandExecution(id: "command", command: "echo done", output: "完了", timestamp: started,
                completedAt: started.addingTimeInterval(8), intent: nil),
        ]
        completed.transcriptRevision = 8
        let final = ChatSessionViewModel(projection: completed) { _, _ in .none }
        let projected = projection(old)
        var deliveredOverview = false
        projected.runtimeContentLoader = { request in
            if !deliveredOverview, case .chatReadTail = request.target {
                let response = try await old.runtimeChatReadContent(for: request)
                deliveredOverview = true
                try projected.applyRuntimeOverview(final.makeRuntimeOverview())
                return response
            }
            return try await final.runtimeChatReadContent(for: request)
        }

        try await projected.refreshRuntimeContent()
        try await waitForReadRevision(8, in: projected)
        let header = projected.runtimeChatRead.page?.blocks.compactMap { block -> AgentStatusHeader? in
            if case .card(let summary) = block.content { summary.header } else { nil }
        }.first

        #expect(projected.executionID == old.executionID)
        #expect(header?.state == .completed)
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
    }

    @Test func sameExecutionRewindRejectsTheLatePageAndCatchesUp() async throws {
        let old = source(items: [
            .userMessage(id: "retained", text: "残す依頼", timestamp: .distantPast, attachments: []),
            .userMessage(id: "removed", text: "取り消す依頼", timestamp: .distantPast, attachments: []),
        ])
        var rewound = old.makeRuntimeSnapshot()
        rewound.transcript = [.userMessage(id: "retained", text: "残す依頼", timestamp: .distantPast, attachments: [])]
        rewound.transcriptRevision = 8
        let final = ChatSessionViewModel(projection: rewound) { _, _ in .none }
        let projected = projection(old)
        var deliveredOverview = false
        projected.runtimeContentLoader = { request in
            if !deliveredOverview, case .chatReadTail = request.target {
                let response = try await old.runtimeChatReadContent(for: request)
                deliveredOverview = true
                try projected.applyRuntimeOverview(final.makeRuntimeOverview())
                return response
            }
            return try await final.runtimeChatReadContent(for: request)
        }

        try await projected.refreshRuntimeContent()
        try await waitForReadRevision(8, in: projected)

        #expect(projected.executionID == old.executionID)
        #expect(projected.runtimeChatRead.page?.blocks.map(\.id) == ["retained"])
        #expect(projected.inputHistoryEntries.map(\.id) == ["retained"])
    }

    @Test func browsingAnotherHistoryPageDoesNotMoveKeyboardRecall() async throws {
        let source = source(items: (0..<128).map {
            .userMessage(id: "input-\($0)", text: "依頼 \($0)", timestamp: .distantPast, attachments: [])
        })
        let projected = projection(source)
        projected.draft = "保存する下書き"
        try await projected.refreshRuntimeContent()
        _ = projected.recallInputHistory(.older)
        try await waitForRecall(projected)
        try await projected.loadRuntimeInputHistory(earlier: true)
        try await projected.loadRuntimeInputHistory(earlier: true)

        _ = projected.recallInputHistory(.older)
        try await waitForRecall(projected)

        #expect(projected.runtimeChatRead.historyEntries.first?.id == "input-0")
        #expect(projected.draft == "依頼 126")
    }

    @Test func aBoundedTimelineCanDropNewerPagesAndReadThemAgainWithoutGaps() async throws {
        let source = source(items: (0..<1_000).map {
            .agentMessage(id: "message-\($0)", text: "本文 \($0)", timestamp: .distantPast)
        })
        let projected = projection(source)
        try await projected.refreshRuntimeContent()
        try await readEightOlderPages(projected)
        let earlier = try #require(projected.runtimeChatRead.page)
        let cursor = try #require(earlier.newerCursor)

        try await projected.loadRuntimeChatRead(target: .chatReadAfter(cursor: cursor))

        #expect(earlier.blocks.count == 400)
        #expect(earlier.blocks.first?.id == "message-550")
        #expect(earlier.blocks.last?.id == "message-949")
        #expect(projected.runtimeChatRead.page?.blocks.count == 400)
        #expect(projected.runtimeChatRead.page?.blocks.first?.id == "message-600")
        #expect(projected.runtimeChatRead.page?.blocks.last?.id == "message-999")
    }

    @Test func aLiveTaskBeyondTheFirstPageOpensAtItsLatestActivities() async throws {
        let tasks = (0..<12).map { number in
            AgentTaskItem(id: "task-\(number)", title: "工程 \(number)", status: number == 11 ? .inProgress : .pending)
        }
        let work = (0..<120).map { number in
            ChatItem.commandExecution(id: "work-\(number)", command: "echo \(number)", output: "完了",
                timestamp: .distantPast, completedAt: .distantFuture, intent: nil)
        }
        let source = source(items: [
            .userMessage(id: "input", text: "多くの工程", timestamp: .distantPast, attachments: []),
            .taskList(id: "tasks", tasks: tasks, timestamp: .distantPast),
        ] + work, running: true)
        let projected = projection(source)
        try await projected.refreshRuntimeContent()

        try await projected.loadRuntimeCardRows("input")
        try await projected.loadRuntimeCardEntries("input", rowID: "task-task-11")
        let cache = try #require(projected.runtimeChatRead.cards["input"])
        let presentation = RuntimeStatusCardPresentation(inputID: "input", cache: cache, viewModel: projected)

        #expect(presentation.card.rows.first?.id == "task-task-11")
        #expect(cache.entries["task-task-11"]?.entries.first?.id == "work-70")
        #expect(cache.entries["task-task-11"]?.entries.last?.id == "work-119")
        #expect(cache.rows.card.totalRowCount == 12)
    }

    @Test func aRecallReplyFromBeforeASameExecutionRewindCannotReplaceTheDraft() async throws {
        let old = source(items: [
            .userMessage(id: "retained", text: "残す依頼", timestamp: .distantPast, attachments: []),
            .userMessage(id: "removed", text: "取り消された入力", timestamp: .distantPast, attachments: []),
        ])
        var rewound = old.makeRuntimeSnapshot()
        rewound.transcript = [.userMessage(id: "retained", text: "残す依頼", timestamp: .distantPast, attachments: [])]
        rewound.transcriptRevision = 8
        let final = ChatSessionViewModel(projection: rewound) { _, _ in .none }
        let projected = projection(old)
        projected.draft = "編集中の下書き"
        try await projected.refreshRuntimeContent()
        var deliveredOldReply = false
        projected.runtimeContentLoader = { request in
            if !deliveredOldReply, case .inputHistory = request.target {
                let response = try await old.runtimeChatReadContent(for: request)
                deliveredOldReply = true
                try projected.applyRuntimeOverview(final.makeRuntimeOverview())
                return response
            }
            return try await final.runtimeChatReadContent(for: request)
        }

        let operation = Task { await projected.recallRuntimeInputHistory(.older) }
        let accepted = await operation.value

        #expect(accepted)
        #expect(projected.executionID == old.executionID)
        #expect(projected.draft == "編集中の下書き")
    }

    @Test func aHeldHistoryReplyCannotResurrectInputsRemovedByASameExecutionRewind() async throws {
        let old = source(items: [
            .userMessage(id: "retained", text: "残す依頼", timestamp: .distantPast, attachments: []),
            .userMessage(id: "removed", text: "取り消された入力", timestamp: .distantPast, attachments: []),
        ])
        var rewound = old.makeRuntimeSnapshot()
        rewound.transcript = [.userMessage(id: "retained", text: "残す依頼", timestamp: .distantPast, attachments: [])]
        rewound.transcriptRevision = 8
        let final = ChatSessionViewModel(projection: rewound) { _, _ in .none }
        let projected = projection(old)
        try await projected.refreshRuntimeContent()
        let oldReply = try await old.runtimeChatReadContent(for: .init(sessionID: old.id,
            executionID: old.executionID, target: .inputHistory(before: nil)))
        let held = HeldReadResponse()
        projected.runtimeContentLoader = { request in
            if case .inputHistory = request.target { return try await held.response() }
            return try await old.runtimeChatReadContent(for: request)
        }
        let pending = Task { try await projected.loadRuntimeInputHistory() }
        await held.waitForRequest()
        try projected.applyRuntimeOverview(final.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await final.runtimeChatReadContent(for: $0) }
        try await projected.loadRuntimeInputHistory()

        held.release(oldReply)
        do { try await pending.value } catch SessionRuntimeContentError.staleContent { }

        #expect(projected.inputHistoryEntries.map(\.id) == ["retained"])
        #expect(projected.runtimeChatRead.latestEntries.map(\.id) == ["retained"])
        #expect(projected.runtimeChatRead.historyError == nil)
    }

    @Test func aReasoningJumpRevealsItsCardAndEntryInsteadOfAnUnloadedInputHeader() async throws {
        let reasoning = (0..<70).map { ChatItem.reasoning(id: "wide-reasoning-\($0)", text: "説明 \($0)", timestamp: .distantPast) }
        let source = source(items: [.userMessage(id: "input", text: "考えて実行", timestamp: .distantPast, attachments: [])]
            + reasoning + [.commandExecution(id: "work", command: "echo done", output: "結果", timestamp: .distantPast)], running: true)
        let projected = projection(source)
        try await projected.refreshRuntimeContent()

        try await projected.loadRuntimeChatRead(target: .chatReadAroundItem(itemID: "wide-reasoning-68"))
        let page = try #require(projected.runtimeChatRead.page)

        #expect(page.revealTarget?.scrollTargetID == "status-card-input")
        #expect(page.revealTarget?.entryID == "wide-reasoning-68")
        #expect(page.blocks.first?.id == "status-card-input")
        #expect(!page.blocks.contains { $0.id == "input" })
    }

    @Test func ordinaryStreamingRefreshDoesNotDiscardAnInFlightInputRecall() async throws {
        let old = source(items: [
            .userMessage(id: "input", text: "呼び戻す入力", timestamp: .distantPast, attachments: []),
            .agentMessage(id: "stream", text: "生成中の本文", timestamp: .distantPast),
        ])
        var streaming = old.makeRuntimeSnapshot()
        streaming.transcript[1] = .agentMessage(id: "stream", text: "さらに生成された本文", timestamp: .distantPast)
        streaming.transcriptRevision = 8
        let final = ChatSessionViewModel(projection: streaming) { _, _ in .none }
        let projected = projection(old)
        projected.draft = "編集中"
        try await projected.refreshRuntimeContent()
        let reply = try await old.runtimeChatReadContent(for: .init(sessionID: old.id, executionID: old.executionID,
            target: .inputHistory(before: nil)))
        let held = HeldReadResponse()
        projected.runtimeContentLoader = { request in
            if case .inputHistory = request.target { return try await held.response() }
            return try await final.runtimeChatReadContent(for: request)
        }
        let accepted = projected.recallInputHistory(.older)
        await held.waitForRequest()
        try projected.applyRuntimeOverview(final.makeRuntimeOverview())
        let refresh = Task { try await projected.loadRuntimeChatRead(target: .chatReadTail) }
        try await waitForReadLoading(projected)

        held.release(reply)
        try await refresh.value
        try await waitForRecall(projected)

        #expect(accepted)
        #expect(projected.draft == "呼び戻す入力")
        #expect(projected.runtimeChatRead.page?.transcriptRevision == 8)
    }

    private func waitForReadLoading(_ projected: ChatSessionViewModel) async throws {
        let deadline = ContinuousClock.now + .seconds(3)
        while !projected.runtimeChatRead.isLoading, ContinuousClock.now < deadline { await Task.yield() }
        try #require(projected.runtimeChatRead.isLoading)
    }

    @Test func heldCardMetadataCannotReenterTheCacheAfterASameExecutionRewind() async throws {
        let old = source(items: [
            .userMessage(id: "retained", text: "残す入力", timestamp: .distantPast, attachments: []),
            .userMessage(id: "removed", text: "取り消す入力", timestamp: .distantPast, attachments: []),
            .commandExecution(id: "removed-work", command: "echo removed", output: "実行結果", timestamp: .distantPast),
        ])
        var rewound = old.makeRuntimeSnapshot()
        rewound.transcript = [.userMessage(id: "retained", text: "残す入力", timestamp: .distantPast, attachments: [])]
        rewound.transcriptRevision = 8
        let final = ChatSessionViewModel(projection: rewound) { _, _ in .none }
        let projected = projection(old)
        try await projected.refreshRuntimeContent()
        let oldReply = try await old.runtimeChatReadContent(for: .init(sessionID: old.id, executionID: old.executionID,
            target: .chatCardRows(inputID: "removed", cursor: nil)))
        let held = HeldReadResponse()
        projected.runtimeContentLoader = { request in
            if case .chatCardRows = request.target { return try await held.response() }
            return try await old.runtimeChatReadContent(for: request)
        }
        let pending = Task { try await projected.loadRuntimeCardRows("removed") }
        await held.waitForRequest()
        try projected.applyRuntimeOverview(final.makeRuntimeOverview())
        projected.runtimeContentLoader = { try await final.runtimeChatReadContent(for: $0) }
        try await projected.refreshRuntimeContent()

        held.release(oldReply)
        do { try await pending.value } catch SessionRuntimeContentError.staleContent { }

        #expect(projected.runtimeChatRead.page?.blocks.map(\.id) == ["retained"])
        #expect(projected.runtimeChatRead.cards["removed"] == nil)
    }

    private func readEightOlderPages(_ projected: ChatSessionViewModel) async throws {
        for _ in 0..<8 {
            let cursor = try #require(projected.runtimeChatRead.page?.olderCursor)
            try await projected.loadRuntimeChatRead(target: .chatReadBefore(cursor: cursor))
        }
    }

    private func waitForReadRevision(_ revision: Int, in projected: ChatSessionViewModel) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while projected.runtimeChatRead.page?.transcriptRevision != revision, clock.now < deadline { await Task.yield() }
        try #require(projected.runtimeChatRead.page?.transcriptRevision == revision)
    }

    private func source(items: [ChatItem], running: Bool = false) -> ChatSessionViewModel {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = items
        if running { snapshot.status = .running }
        snapshot.transcriptRevision = 7
        return ChatSessionViewModel(projection: snapshot) { _, _ in .none }
    }

    private func projection(_ source: ChatSessionViewModel) -> ChatSessionViewModel {
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeSupportsChatReadModel = true
        projected.runtimeContentLoader = { request in
            if request.target.requiresChatReadModel { return try await source.runtimeChatReadContent(for: request) }
            return try source.runtimeContent(for: request)
        }
        return projected
    }

    private func waitForRecall(_ projected: ChatSessionViewModel) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while projected.runtimeChatRead.recall.isLoading, clock.now < deadline { await Task.yield() }
        try #require(!projected.runtimeChatRead.recall.isLoading, "入力の全文取得が完了すること")
    }
}

@MainActor private final class HeldReadResponse {
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
