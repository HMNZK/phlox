import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

@Suite @MainActor struct RuntimeChatProjectionTests {
    @Test func mobileFullTranscriptLoadsReadModelHistoryAndReusesUnchangedRevision() async throws {
        let items = (1...55).map { ChatItem.agentMessage(id: "mobile-\($0)", text: "回答 \($0)", timestamp: .distantPast) }
        let source = ChatSessionViewModel(projection: chatSnapshot(items: items)) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeSupportsChatReadModel = true
        var transcriptReads = 0
        projected.runtimeContentLoader = { request in
            switch request.target {
            case .chatTail, .chatTailChecking, .chatBefore: transcriptReads += 1
            default: break
            }
            return try await source.runtimeChatReadContent(for: request)
        }
        try await projected.loadAllRuntimeContent()
        #expect(projected.transcript.map(\.id) == items.map(\.id))
        #expect(projected.hasCompleteRuntimeTranscript)
        let reads = transcriptReads
        try await projected.loadAllRuntimeContent()
        #expect(transcriptReads == reads)
    }

    @Test func overviewShowsPendingApprovalWithoutAllowingAReplyBeforeDetailArrives() async throws {
        let approvalID = UUID(uuidString: "DAF84EF4-C6BC-407F-905A-C81D7540284B")!
        var snapshot = chatSnapshot(items: [
            .agentMessage(id: "answer", text: "準備中", timestamp: .distantPast),
        ])
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "approval-item",
            prompt: String(repeating: "許可対象 ", count: 300))]
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        var sent = false
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in
            sent = true
            return .none
        }

        let preview = try #require(projected.currentReplyApproval)
        projected.markApprovalPresented(preview, at: .distantPast)
        let accepted = await projected.respond(to: preview, decision: .accept, now: Date(timeIntervalSince1970: 1_000))

        #expect(!projected.hasLoadedRuntimeTranscript)
        #expect(projected.transcript.isEmpty)
        #expect(preview.requiresDetail)
        #expect(!accepted)
        #expect(!sent)
    }

    @Test func tailAndOlderPagesRestoreVisibleChatWithoutRequestingWholeSnapshot() async throws {
        let items = (1...55).map { number in
            ChatItem.agentMessage(id: "item-\(number)", text: "回答 \(number)", timestamp: .distantPast)
        }
        let snapshot = chatSnapshot(items: items)
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }

        try await projected.refreshRuntimeContent()
        let tailIDs = projected.transcript.map(\.id)
        try await projected.loadEarlierRuntimeContent()

        #expect(tailIDs.count == 50)
        #expect(tailIDs.first == "item-6")
        #expect(projected.hasLoadedRuntimeTranscript)
        #expect(projected.transcript.count == 55)
        #expect(projected.transcript.first?.id == "item-1")
        #expect(!projected.hasMoreRuntimeTranscript)
    }

    @Test func streamingTailEditKeepsVerifiedOlderPagesAndEarlierEditInvalidatesThem() async throws {
        let items = (1...55).map { number in
            ChatItem.agentMessage(id: "item-\(number)", text: "回答 \(number)", timestamp: .distantPast)
        }
        let snapshot = chatSnapshot(items: items)
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }
        try await projected.loadAllRuntimeContent()

        var streaming = snapshot
        streaming.transcript[54] = .agentMessage(id: "item-55", text: "生成中の回答", timestamp: .distantPast)
        streaming.transcriptRevision = 8
        let streamingSource = ChatSessionViewModel(projection: streaming) { _, _ in .none }
        projected.runtimeContentLoader = { try streamingSource.runtimeContent(for: $0) }
        try projected.applyRuntimeOverview(overviewWithNonAppendRevision(
            from: streamingSource.makeRuntimeOverview(), revision: 8))
        try await projected.refreshRuntimeContent()

        #expect(projected.transcript.count == 55)
        #expect(projected.transcript.first?.id == "item-1")
        #expect(agentText(projected.transcript.last) == "生成中の回答")
        #expect(!projected.hasMoreRuntimeTranscript)

        var appendedAndEdited = streaming
        appendedAndEdited.transcript[54] = .agentMessage(id: "item-55", text: "完成した回答", timestamp: .distantPast)
        appendedAndEdited.transcript.append(.agentMessage(id: "item-56", text: "次の項目", timestamp: .distantPast))
        appendedAndEdited.transcriptRevision = 9
        let appendedSource = ChatSessionViewModel(projection: appendedAndEdited) { _, _ in .none }
        projected.runtimeContentLoader = { try appendedSource.runtimeContent(for: $0) }
        try projected.applyRuntimeOverview(overviewWithNonAppendRevision(
            from: appendedSource.makeRuntimeOverview(), revision: 9))
        try await projected.refreshRuntimeContent()

        #expect(projected.transcript.count == 56)
        #expect(projected.transcript.first?.id == "item-1")
        #expect(agentText(projected.transcript[54]) == "完成した回答")
        #expect(projected.transcript.last?.id == "item-56")
        #expect(!projected.hasMoreRuntimeTranscript)

        var earlierEdit = appendedAndEdited
        earlierEdit.transcript[0] = .agentMessage(id: "item-1", text: "変更された過去", timestamp: .distantPast)
        earlierEdit.transcriptRevision = 10
        let earlierSource = ChatSessionViewModel(projection: earlierEdit) { _, _ in .none }
        projected.runtimeContentLoader = { try earlierSource.runtimeContent(for: $0) }
        try projected.applyRuntimeOverview(overviewWithNonAppendRevision(
            from: earlierSource.makeRuntimeOverview(), revision: 10))
        try await projected.refreshRuntimeContent()

        #expect(projected.transcript.count == 50)
        #expect(projected.transcript.first?.id == "item-7")
        #expect(projected.hasMoreRuntimeTranscript)
    }

    @Test func oldTailResponseCannotOverwriteNewerOverview() async throws {
        let snapshot = chatSnapshot(items: [.agentMessage(id: "old", text: "旧回答", timestamp: .distantPast)])
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        let oldPage = try source.runtimeContent(for: .init(sessionID: snapshot.id,
            executionID: snapshot.executionID, target: .chatTail))
        var newer = snapshot
        newer.transcript = [.agentMessage(id: "new", text: "新回答", timestamp: .distantPast)]
        newer.transcriptRevision = 12
        let newerSource = ChatSessionViewModel(projection: newer) { _, _ in .none }
        projected.runtimeContentLoader = { request in
            if case .chatTail = request.target {
                try projected.applyRuntimeOverview(newerSource.makeRuntimeOverview())
                return oldPage
            }
            return try source.runtimeContent(for: request)
        }

        try await projected.refreshRuntimeContent()

        #expect(projected.transcriptRevision == 12)
        #expect(projected.transcript.isEmpty)
        #expect(!projected.hasLoadedRuntimeTranscript)
    }

    @Test func appendOnlyOverviewKeepsPreviouslyVisibleMessageWhileTailRefreshes() async throws {
        let snapshot = chatSnapshot(items: [.agentMessage(id: "first", text: "以前の回答", timestamp: .distantPast)])
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }
        try await projected.refreshRuntimeContent()
        var appended = snapshot
        appended.transcript.append(.agentMessage(id: "second", text: "追加の回答", timestamp: .distantPast))
        appended.transcriptRevision = 8
        let appendedSource = ChatSessionViewModel(projection: appended) { _, _ in .none }
        let newOverview = overviewWithNonAppendRevision(from: appendedSource.makeRuntimeOverview(), revision: 7)
        projected.runtimeContentLoader = { try appendedSource.runtimeContent(for: $0) }

        try projected.applyRuntimeOverview(newOverview)
        let visibleDuringRefresh = projected.transcript.map(\.id)
        try await projected.refreshRuntimeContent()

        #expect(visibleDuringRefresh == ["first"])
        #expect(projected.transcript.map(\.id) == ["first", "second"])
        #expect(projected.hasLoadedRuntimeTranscript)
    }

    @Test func burstAppendFillsGapBeforeKeepingPreviouslyLoadedHistory() async throws {
        let snapshot = chatSnapshot(items: [.agentMessage(id: "first", text: "保存済み", timestamp: .distantPast)])
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }
        try await projected.refreshRuntimeContent()
        var appended = snapshot
        appended.transcript += (2...61).map { number in
            .agentMessage(id: "item-\(number)", text: "追加 \(number)", timestamp: .distantPast)
        }
        appended.transcriptRevision = 8
        let appendedSource = ChatSessionViewModel(projection: appended) { _, _ in .none }
        projected.runtimeContentLoader = { try appendedSource.runtimeContent(for: $0) }

        try projected.applyRuntimeOverview(overviewWithNonAppendRevision(
            from: appendedSource.makeRuntimeOverview(), revision: 7))
        try await projected.refreshRuntimeContent()

        #expect(projected.transcript.count == 61)
        #expect(projected.transcript.first?.id == "first")
        #expect(projected.transcript.last?.id == "item-61")
    }

    @Test func oversizedItemIsRestoredExactlyFromChunks() async throws {
        let output = String(repeating: "\\", count: 2_200_000)
        let snapshot = chatSnapshot(items: [
            .commandExecution(id: "large", command: "run", output: output, timestamp: .distantPast),
        ])
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }

        try await projected.refreshRuntimeContent()

        #expect(projected.hasLoadedRuntimeTranscript)
        #expect(projected.transcript.count == 1)
        guard case .commandExecution(_, _, let restored, _, _, _)? = projected.transcript.first else {
            Issue.record("巨大な項目が復元されませんでした")
            return
        }
        #expect(restored == output)
    }

    @Test func streamingEditKeepsVisibleAnswerUntilFreshTailArrives() async throws {
        let snapshot = chatSnapshot(items: [.agentMessage(id: "answer", text: "読める途中回答", timestamp: .distantPast)])
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }
        try await projected.refreshRuntimeContent()
        var updated = snapshot
        updated.transcript = [.agentMessage(id: "answer", text: "完成した回答", timestamp: .distantPast)]
        updated.transcriptRevision = 8
        let updatedSource = ChatSessionViewModel(projection: updated) { _, _ in .none }
        projected.runtimeContentLoader = { try updatedSource.runtimeContent(for: $0) }

        try projected.applyRuntimeOverview(overviewWithNonAppendRevision(
            from: updatedSource.makeRuntimeOverview(), revision: 8))
        let visibleWhileFetching = agentText(projected.transcript.first)
        try await projected.refreshRuntimeContent()

        #expect(visibleWhileFetching == "読める途中回答")
        #expect(agentText(projected.transcript.first) == "完成した回答")
        #expect(projected.hasLoadedRuntimeTranscript)
    }

    @Test func pendingApprovalDetailSurvivesUnrelatedTranscriptEdit() async throws {
        let approvalID = UUID(uuidString: "4B08D1A3-22AC-44D0-8D14-DF35E7C6006E")!
        var snapshot = chatSnapshot(items: [.agentMessage(id: "answer", text: "処理中", timestamp: .distantPast)])
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "command-item", prompt: "実行を許可しますか")]
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }
        try await projected.refreshRuntimeContent()
        var updated = snapshot
        updated.transcript = [.agentMessage(id: "answer", text: "処理中です", timestamp: .distantPast)]
        updated.transcriptRevision = 8
        let updatedSource = ChatSessionViewModel(projection: updated) { _, _ in .none }

        try projected.applyRuntimeOverview(overviewWithNonAppendRevision(
            from: updatedSource.makeRuntimeOverview(), revision: 8))

        #expect(projected.pendingApprovals.first?.id == approvalID)
        #expect(projected.currentReplyApproval?.requiresDetail == false)
        #expect(!projected.runtimePendingInteractionsNeedDetail)
    }

    @Test func changedApprovalPromptWithSameIDRequiresFreshDetail() async throws {
        let approvalID = UUID(uuidString: "3D80F04F-25EC-4786-AC0E-9549446A7F52")!
        var snapshot = chatSnapshot(items: [.agentMessage(id: "answer", text: "処理中", timestamp: .distantPast)])
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "command-item", prompt: "古い許可対象")]
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }
        try await projected.refreshRuntimeContent()
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "command-item", prompt: "新しい許可対象")]
        try source.applyRuntimeSnapshot(snapshot)

        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        let requiresDetailBeforeLoad = projected.currentReplyApproval?.requiresDetail
        try await projected.refreshRuntimeContent()

        #expect(requiresDetailBeforeLoad == true)
        #expect(projected.currentReplyApproval?.subject == "新しい許可対象")
        #expect(projected.currentReplyApproval?.requiresDetail == false)
    }

    @Test func approvalCannotBeAcceptedUntilHalfSecondAfterFullDetailAppears() async throws {
        let approvalID = UUID(uuidString: "70C87BAC-07A0-476A-95D1-112A81AA6637")!
        let shownAt = Date(timeIntervalSince1970: 1_000)
        var snapshot = chatSnapshot(items: [.agentMessage(id: "answer", text: "準備中", timestamp: .distantPast)])
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "command-item", prompt: "作業ディレクトリの変更を許可しますか")]
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        var sent = 0
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, command in
            if case .approval = command { sent += 1 }
            return .none
        }
        let preview = try #require(projected.currentReplyApproval)
        projected.markApprovalPresented(preview, at: shownAt.addingTimeInterval(-10))
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }

        try await projected.refreshRuntimeContent()
        let full = try #require(projected.currentReplyApproval)
        let beforeDisplay = await projected.respond(to: full, decision: .accept, now: shownAt)
        projected.markApprovalPresented(full, at: shownAt)
        let tooSoon = await projected.respond(to: full, decision: .accept,
            now: shownAt.addingTimeInterval(0.49))
        let accepted = await projected.respond(to: full, decision: .accept,
            now: shownAt.addingTimeInterval(0.5))

        #expect(preview.requiresDetail)
        #expect(!full.requiresDetail)
        #expect(!beforeDisplay)
        #expect(!tooSoon)
        #expect(accepted)
        #expect(sent == 1)
    }

    @Test func changedApprovalTextWithSameIDMustWaitAgain() async throws {
        let approvalID = UUID(uuidString: "DAEEA30F-AE08-4DCE-96FD-EE64766206D5")!
        let shownAt = Date(timeIntervalSince1970: 1_000)
        var snapshot = chatSnapshot(items: [.agentMessage(id: "answer", text: "準備中", timestamp: .distantPast)])
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "command-item", prompt: "古い実行対象")]
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        var sent = 0
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, command in
            if case .approval = command { sent += 1 }
            return .none
        }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }
        try await projected.refreshRuntimeContent()
        let old = try #require(projected.currentReplyApproval)
        projected.markApprovalPresented(old, at: shownAt.addingTimeInterval(-10))
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "command-item", prompt: "新しい実行対象")]
        try source.applyRuntimeSnapshot(snapshot)

        try projected.applyRuntimeOverview(source.makeRuntimeOverview())
        try await projected.refreshRuntimeContent()
        let changed = try #require(projected.currentReplyApproval)
        let tooSoon = await projected.respond(to: changed, decision: .accept, now: shownAt)
        projected.markApprovalPresented(changed, at: shownAt)
        let accepted = await projected.respond(to: changed, decision: .accept,
            now: shownAt.addingTimeInterval(0.5))

        #expect(old.id == changed.id)
        #expect(old.subject == "古い実行対象")
        #expect(changed.subject == "新しい実行対象")
        #expect(!tooSoon)
        #expect(accepted)
        #expect(sent == 1)
    }

    @Test func resolvedQuestionIsNotActionableWhileOlderTextRemainsVisible() async throws {
        var snapshot = chatSnapshot(items: [
            .userQuestion(id: "question-42", requestId: "request-42",
                questions: [ChatUserQuestion(question: "続けますか", header: "確認", options: [], multiSelect: false)],
                answers: nil, state: .pending, timestamp: .distantPast),
        ])
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try source.runtimeContent(for: $0) }
        try await projected.refreshRuntimeContent()
        snapshot.transcript = [
            .userQuestion(id: "question-42", requestId: "request-42",
                questions: [ChatUserQuestion(question: "続けますか", header: "確認", options: [], multiSelect: false)],
                answers: nil, state: .answered, timestamp: .distantPast),
        ]
        snapshot.transcriptRevision = 8
        let resolvedSource = ChatSessionViewModel(projection: snapshot) { _, _ in .none }

        try projected.applyRuntimeOverview(overviewWithNonAppendRevision(
            from: resolvedSource.makeRuntimeOverview(), revision: 8))

        #expect(projected.transcript.first?.id == "question-42")
        #expect(projected.replyItems.isEmpty)
        #expect(projected.currentReplyApproval == nil)
    }

    @Test func presentationFailureDoesNotBlockApprovalOrTranscript() async throws {
        let approvalID = UUID(uuidString: "F42320FA-B28D-4EE1-9567-F83C4DB8A8CB")!
        var snapshot = chatSnapshot(items: [.agentMessage(id: "answer", text: "回答", timestamp: .distantPast)])
        snapshot.pendingApprovals = [ChatApprovalRequest(id: approvalID, kind: .command,
            threadId: "thread", turnId: "turn", itemId: "command-item", prompt: "続ける")]
        let source = ChatSessionViewModel(projection: snapshot) { _, _ in .none }
        let projected = ChatSessionViewModel(projection: source.makeRuntimeOverview()) { _, _ in .none }
        projected.runtimeContentLoader = { try contentWithoutPresentation(source, request: $0) }

        try await projected.refreshRuntimeContent()

        #expect(agentText(projected.transcript.first) == "回答")
        #expect(projected.pendingApprovals.first?.id == approvalID)
        #expect(projected.currentReplyApproval?.requiresDetail == false)
        #expect(!projected.hasLoadedRuntimePresentation)
        #expect(projected.runtimeConnectionError != nil)
    }

    private func chatSnapshot(items: [ChatItem]) -> SessionRuntimeChatSnapshot {
        var snapshot = SessionRuntimeChatSnapshot(id: SessionID(), startedAt: .distantPast,
            agentRef: .builtin(.codex), workingDirectory: "/workspace")
        snapshot.transcript = items
        snapshot.transcriptRevision = 7
        return snapshot
    }

    private func agentText(_ item: ChatItem?) -> String? {
        guard case .agentMessage(_, let text, _) = item else { return nil }
        return text
    }

    private func contentWithoutPresentation(_ source: ChatSessionViewModel,
                                            request: SessionRuntimeContentRequest) throws -> SessionRuntimeContentResponse {
        if case .chatPresentation = request.target { throw SessionRuntimeContentError.invalidRequest }
        return try source.runtimeContent(for: request)
    }

    private func overviewWithNonAppendRevision(from overview: SessionRuntimeSessionOverview,
                                               revision: Int) -> SessionRuntimeSessionOverview {
        guard case .chat(let chat) = overview.kind else { preconditionFailure("Chat overview required") }
        return SessionRuntimeSessionOverview(id: overview.id, startedAt: overview.startedAt,
            agentRef: overview.agentRef, workingDirectory: overview.workingDirectory?.text,
            executionID: overview.executionID, title: overview.title.text,
            titleState: overview.titleState, projectID: overview.projectID,
            parentSessionID: overview.parentSessionID, launchContext: overview.launchContext,
            status: overview.status, displayStatus: overview.displayStatus,
            statusEnteredAt: overview.statusEnteredAt,
            displayStatusEnteredAt: overview.displayStatusEnteredAt,
            hasUnseenCompletion: overview.hasUnseenCompletion, lastOutputAt: overview.lastOutputAt,
            lastTurnCompletedAt: overview.lastTurnCompletedAt,
            kind: .chat(.init(transcriptRevision: chat.transcriptRevision,
                lastNonAppendRevision: revision,
                transcriptItemCount: chat.transcriptItemCount,
                pendingInteractionCount: chat.pendingInteractionCount,
                pendingInteractions: chat.pendingInteractions,
                pendingIdentity: chat.pendingIdentity, lastAgentText: chat.lastAgentText,
                processExit: chat.processExit, isStalled: chat.isStalled,
                stalledSince: chat.stalledSince, completedTurnSeq: chat.completedTurnSeq,
                draftRecoveryID: chat.draftRecoveryID, isProcessing: chat.isProcessing,
                controls: chat.controls)))
    }
}
