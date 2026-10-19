import XCTest
import AgentDomain
import PhloxCore
@testable import Features

final class ReplyApprovalTests: XCTestCase {
    func testCodexActionKindsUseMacLabelsAndUnknownKindsHaveNoLabel() {
        let date = Date(timeIntervalSince1970: 1_000)
        let command = ReplyApproval.codex(
            approval: Approval(id: "a1", sessionID: "s1", kind: .codex, prompt: "git push", actionKind: "command"),
            statusEnteredAt: date,
            chatMessages: []
        )
        let file = ReplyApproval.codex(
            approval: Approval(id: "a2", sessionID: "s1", kind: .codex, prompt: "edit", actionKind: "fileChange"),
            statusEnteredAt: date,
            chatMessages: []
        )
        let permissions = ReplyApproval.codex(
            approval: Approval(id: "a3", sessionID: "s1", kind: .codex, prompt: "permission", actionKind: "permissions"),
            statusEnteredAt: date,
            chatMessages: []
        )
        let unknown = ReplyApproval.codex(
            approval: Approval(id: "a4", sessionID: "s1", kind: .codex, prompt: "unknown", actionKind: "shell"),
            statusEnteredAt: date,
            chatMessages: []
        )
        let missing = ReplyApproval.codex(
            approval: Approval(id: "a5", sessionID: "s1", kind: .codex, prompt: "missing"),
            statusEnteredAt: date,
            chatMessages: []
        )

        XCTAssertEqual(command.kindLabel, "コマンドの実行")
        XCTAssertEqual(file.kindLabel, "ファイルの変更")
        XCTAssertEqual(permissions.kindLabel, "権限の変更")
        XCTAssertNil(unknown.kindLabel)
        XCTAssertNil(missing.kindLabel)
        XCTAssertEqual(unknown.compactTitle, "承認待ち")
        let codexDecisions: [ApprovalDecision] = [.accept, .acceptForSession, .decline, .cancel]
        XCTAssertEqual(command.buttonDecisions, codexDecisions)
        XCTAssertEqual(command.requestedAt, date)
    }

    func testCodexDiffIsAttachedOnlyWhenApprovalAndConversationIDsMatch() {
        let change = ChatFileChange(path: "ProxyRouter.swift", diff: "@@ -1 +1 @@\n-old\n+new", kind: "edit")
        let matchingMessage = ChatMessage.fileChange(id: "approval-1", changes: [change])
        let matching = ReplyApproval.codex(
            approval: Approval(id: "approval-1", sessionID: "s1", kind: .codex, prompt: "Edit", actionKind: "fileChange"),
            statusEnteredAt: Date(timeIntervalSince1970: 1_000),
            chatMessages: [matchingMessage]
        )
        let unmatched = ReplyApproval.codex(
            approval: Approval(id: "approval-2", sessionID: "s1", kind: .codex, prompt: "Edit", actionKind: "fileChange"),
            statusEnteredAt: Date(timeIntervalSince1970: 1_000),
            chatMessages: [matchingMessage]
        )

        XCTAssertEqual(matching.diffFiles, [change])
        XCTAssertTrue(unmatched.diffFiles.isEmpty)
    }

    func testClaudeToolNameSelectsKindAndSessionScopeDecision() {
        let date = Date(timeIntervalSince1970: 1_000)
        let bash = ReplyApproval.claudeToolPermission(
            requestID: "r1",
            question: makeToolQuestion(name: "Bash", detail: "git status", allowsSessionScope: true),
            statusEnteredAt: date
        )
        let edit = ReplyApproval.claudeToolPermission(
            requestID: "r2",
            question: makeToolQuestion(name: "Edit", detail: "Sources/App.swift", allowsSessionScope: false),
            statusEnteredAt: date
        )
        let unknownTool = ReplyApproval.claudeToolPermission(
            requestID: "r3",
            question: makeToolQuestion(name: "WebFetch", detail: "https://example.test", allowsSessionScope: false),
            statusEnteredAt: date
        )

        XCTAssertEqual(bash.kindLabel, "コマンドの実行")
        XCTAssertEqual(bash.subject, "git status")
        XCTAssertEqual(bash.explanation, "Bash を実行しますか？")
        XCTAssertEqual(bash.compactTitle, "承認待ち · Bash · git status")
        XCTAssertEqual(bash.compactAccessibilityLabel, "承認待ち · Bash、git status。表示するとキーボードを閉じます")
        let scopedDecisions: [ApprovalDecision] = [.accept, .acceptForSession, .decline, .cancel]
        let ordinaryDecisions: [ApprovalDecision] = [.accept, .decline, .cancel]
        XCTAssertEqual(bash.buttonDecisions, scopedDecisions)
        XCTAssertEqual(edit.kindLabel, "ファイルの変更")
        XCTAssertEqual(edit.buttonDecisions, ordinaryDecisions)
        XCTAssertEqual(unknownTool.kindLabel, "ツールの使用")
        XCTAssertEqual(unknownTool.requestedAt, date)
    }

    func testClaudePermissionClassificationMatchesMacSingleQuestionRule() {
        let permission = makeToolQuestion(name: "Bash", detail: "swift test", allowsSessionScope: false)
        let ordinary = UserQuestionItem(
            question: "どの案にしますか？", header: "選択", options: [UserQuestionOption(label: "A")], multiSelect: false
        )

        XCTAssertTrue(ReplyApproval.isClaudeToolPermissionQuestion([permission]))
        XCTAssertFalse(ReplyApproval.isClaudeToolPermissionQuestion([]))
        XCTAssertFalse(ReplyApproval.isClaudeToolPermissionQuestion([permission, ordinary]))
    }

    func testArmDelayAndMacApprovalElapsedText() {
        let now = Date(timeIntervalSince1970: 10_000)

        XCTAssertFalse(ReplyApprovalPolicy.isArmed(presentedAt: now, now: now.addingTimeInterval(0.599)))
        XCTAssertTrue(ReplyApprovalPolicy.isArmed(presentedAt: now, now: now.addingTimeInterval(0.6)))
        XCTAssertEqual(ReplyApprovalPolicy.sinceText(startedAt: now.addingTimeInterval(-59), now: now), "たった今から")
        XCTAssertEqual(ReplyApprovalPolicy.sinceText(startedAt: now.addingTimeInterval(-60), now: now), "1分前から")
        XCTAssertEqual(ReplyApprovalPolicy.sinceText(startedAt: now.addingTimeInterval(-121), now: now), "2分前から")
    }
}

@MainActor
final class SessionDetailReplyApprovalTests: XCTestCase {
    private let enteredAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testLoadFiltersCodexApprovalsBySessionAndAgent() async {
        let api = MockAPI(approvalsList: [
            Approval(id: "a1", sessionID: "s1", kind: .codex, prompt: "one", actionKind: "command"),
            Approval(id: "a2", sessionID: "s2", kind: .codex, prompt: "other session", actionKind: "command"),
            Approval(id: "a3", sessionID: "s1", kind: .claudeCode, prompt: "other agent", actionKind: "command"),
        ])
        let vm = SessionDetailViewModel(session: session(id: "s1", agent: .codex), api: api)

        await vm.loadApprovals()

        XCTAssertEqual(vm.replyApprovals.map(\.id), ["codex:a1"])
        XCTAssertEqual(vm.currentReplyApproval?.requestedAt, enteredAt)
        XCTAssertNil(vm.approvalLoadError)
    }

    func testCodexApprovalResponseRemovesOnlyAcceptedItemAndWaitsForNext() async throws {
        let api = MockAPI(approvalsList: [
            Approval(id: "a1", sessionID: "s1", kind: .codex, prompt: "first", actionKind: "command"),
            Approval(id: "a2", sessionID: "s1", kind: .codex, prompt: "second", actionKind: "fileChange"),
        ])
        let vm = SessionDetailViewModel(session: session(id: "s1", agent: .codex), api: api)
        await vm.loadApprovals()
        let first = try XCTUnwrap(vm.currentReplyApproval)

        await vm.respond(to: first, decision: .acceptForSession)

        let log = await api.respondLog
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.0, "a1")
        XCTAssertEqual(log.first?.1, .acceptForSession)
        XCTAssertEqual(vm.replyApprovals.map(\.id), ["codex:a2"])
        XCTAssertEqual(vm.replyApprovalResult, ReplyApprovalResult(actionLabel: "このセッション中は許可", remainingCount: 1, nextSessionName: "Rose"))
        XCTAssertNil(vm.replyApprovalError)
    }

    func testCodexRespondsEachDecisionThroughApprovalEndpoint() async throws {
        let decisions: [ApprovalDecision] = [.accept, .acceptForSession, .decline, .cancel]

        for (index, decision) in decisions.enumerated() {
            let approvalID = "a\(index + 1)"
            let api = MockAPI(approvalsList: [
                Approval(id: approvalID, sessionID: "s1", kind: .codex, prompt: "command", actionKind: "command"),
            ])
            let vm = SessionDetailViewModel(session: session(id: "s1", agent: .codex), api: api)
            await vm.loadApprovals()
            let approval = try XCTUnwrap(vm.currentReplyApproval)

            await vm.respond(to: approval, decision: decision)

            let log = await api.respondLog
            XCTAssertEqual(log.map(\.0), [approvalID])
            XCTAssertEqual(log.map(\.1), [decision])
            XCTAssertNil(vm.replyApprovalError)
        }
    }

    func testSentApprovalIncludesPendingQuestionAndNextRevealsIt() async throws {
        let question = ChatMessage.userQuestion(
            id: "q1", requestId: "r1",
            questions: [UserQuestionItem(question: "どちら？", header: "選択", options: [UserQuestionOption(label: "A")], multiSelect: false)],
            answers: nil, state: .pending
        )
        let api = MockAPI(
            approvalsList: [Approval(id: "a1", sessionID: "s1", kind: .codex, prompt: "command", actionKind: "command")],
            messagesOutcome: .success([question])
        )
        let vm = SessionDetailViewModel(session: session(id: "s1", agent: .codex), api: api)
        await vm.load()
        await vm.loadApprovals()
        let approval = try XCTUnwrap(vm.currentReplyApproval)

        await vm.respond(to: approval, decision: .accept)

        XCTAssertEqual(vm.replyApprovalResult?.remainingCount, 1)
        XCTAssertEqual(vm.replyApprovalResult?.nextSessionName, "Rose")
        XCTAssertEqual(vm.replyApprovalResult?.nextStatusLabel, "質問あり")
        vm.showNextReplyApproval()
        XCTAssertNil(vm.replyApprovalResult)
        XCTAssertEqual(vm.replyApprovalIndex, 0)
        XCTAssertTrue(vm.visibleMessages.contains(question))
    }

    func testCodexResponseFailureKeepsCardAndShowsFailureLine() async throws {
        let api = MockAPI(
            approvalsList: [Approval(id: "a1", sessionID: "s1", kind: .codex, prompt: "command", actionKind: "command")],
            respondError: .unreachable
        )
        let vm = SessionDetailViewModel(session: session(id: "s1", agent: .codex), api: api)
        await vm.loadApprovals()
        let approval = try XCTUnwrap(vm.currentReplyApproval)

        await vm.respond(to: approval, decision: .decline)

        XCTAssertEqual(vm.currentReplyApproval?.id, approval.id)
        XCTAssertEqual(
            vm.replyApprovalError,
            "応答を送れませんでした。「拒否」は Mac に届いていません。もう一度選んでください。応答の送信に失敗しました · Mac に接続できません"
        )
        XCTAssertNil(vm.replyApprovalResult)
    }

    func testClaudePermissionAllowMapsToQuestionAnswerAndStatus() async throws {
        let api = MockAPI(messagesOutcome: .success([pendingToolQuestion()]))
        let vm = SessionDetailViewModel(session: session(id: "s1", agent: .claudeCode, status: .awaitingUserQuestion), api: api)
        await vm.load()
        let approval = try XCTUnwrap(vm.currentReplyApproval)

        XCTAssertEqual(vm.presentationState.displayState, .approval)
        await vm.respond(to: approval, decision: .accept)

        let log = await api.respondToQuestionLog
        XCTAssertEqual(log.count, 1)
        XCTAssertEqual(log.first?.sessionID, "s1")
        XCTAssertEqual(log.first?.requestId, "r1")
        XCTAssertEqual(log.first?.answers, ["Bash を実行しますか？": ["Allow"]])
        XCTAssertEqual(vm.replyApprovalResult?.actionLabel, "許可")
        XCTAssertNil(vm.currentReplyApproval)
    }

    func testClaudePermissionScopeDeclineAndCancelUseTheirRoutes() async throws {
        let scopeAPI = MockAPI(messagesOutcome: .success([pendingToolQuestion(allowsSessionScope: true)]))
        let scopeVM = SessionDetailViewModel(session: session(id: "s1", agent: .claudeCode), api: scopeAPI)
        await scopeVM.load()
        await scopeVM.respond(to: try XCTUnwrap(scopeVM.currentReplyApproval), decision: .acceptForSession)
        let scopeLog = await scopeAPI.respondToQuestionLog
        XCTAssertEqual(scopeLog.first?.answers, ["Bash を実行しますか？": ["AllowForSession"]])

        let denyAPI = MockAPI(messagesOutcome: .success([pendingToolQuestion()]))
        let denyVM = SessionDetailViewModel(session: session(id: "s1", agent: .claudeCode), api: denyAPI)
        await denyVM.load()
        await denyVM.respond(to: try XCTUnwrap(denyVM.currentReplyApproval), decision: .decline)
        let denyLog = await denyAPI.respondToQuestionLog
        XCTAssertEqual(denyLog.first?.answers, ["Bash を実行しますか？": ["Deny"]])

        let cancelAPI = MockAPI(messagesOutcome: .success([pendingToolQuestion()]))
        let cancelVM = SessionDetailViewModel(session: session(id: "s1", agent: .claudeCode), api: cancelAPI)
        await cancelVM.load()
        await cancelVM.respond(to: try XCTUnwrap(cancelVM.currentReplyApproval), decision: .cancel)
        let interruptCount = await cancelAPI.interruptCount
        let cancelLog = await cancelAPI.respondToQuestionLog
        XCTAssertEqual(interruptCount, 1)
        XCTAssertTrue(cancelLog.isEmpty)
    }

    func testLegacyClaudeQuestionStaysAQuestionAndCursorHasNoApprovalState() async {
        let oldQuestion = ChatMessage.userQuestion(
            id: "legacy", requestId: "legacy-request",
            questions: [UserQuestionItem(question: "Allow Bash?", header: "Bash", options: [], multiSelect: false)],
            answers: nil, state: .pending
        )
        let claudeVM = SessionDetailViewModel(
            session: session(id: "s1", agent: .claudeCode, status: .awaitingUserQuestion),
            api: MockAPI(messagesOutcome: .success([oldQuestion]))
        )
        await claudeVM.load()
        XCTAssertTrue(claudeVM.replyApprovals.isEmpty)
        XCTAssertEqual(claudeVM.presentationState.displayState, .question)

        let cursor = session(id: "cursor", agent: .cursor, status: .awaitingApproval(prompt: "permission"))
        XCTAssertEqual(cursor.displayState, .idle)
        let cursorVM = SessionDetailViewModel(session: cursor, api: MockAPI(approvalsList: [
            Approval(id: "a1", sessionID: "cursor", kind: .codex, prompt: "permission", actionKind: "command"),
        ]))
        await cursorVM.loadApprovals()
        XCTAssertTrue(cursorVM.replyApprovals.isEmpty)
        XCTAssertNil(cursorVM.presentationState.displayState)
    }

    func testMixedClaudeToolAndOrdinaryQuestionsStayTogetherAsQuestionCard() async {
        let permission = makeToolQuestion(name: "Bash", detail: "swift test", allowsSessionScope: false)
        let ordinary = UserQuestionItem(
            question: "どの案にしますか？", header: "選択", options: [UserQuestionOption(label: "A")], multiSelect: false
        )
        let message = ChatMessage.userQuestion(
            id: "mixed", requestId: "mixed-request", questions: [permission, ordinary], answers: nil, state: .pending
        )
        let vm = SessionDetailViewModel(
            session: session(id: "s1", agent: .claudeCode, status: .awaitingUserQuestion),
            api: MockAPI(messagesOutcome: .success([message]))
        )

        await vm.load()

        XCTAssertTrue(vm.replyApprovals.isEmpty)
        XCTAssertEqual(vm.presentationState.displayState, .question)
    }

    func testNextAttentionUsesFreshQueueCountsErrorsAndStallsWithoutAutomaticNavigation() async throws {
        let current = session(id: "s1", agent: .codex)
        let question = attentionSession(id: "question", status: .awaitingUserQuestion, entered: 30)
        let error = attentionSession(id: "error", status: .error(message: "failed"), entered: 10)
        let stalled = attentionSession(id: "stalled", status: .running, entered: 20, stalled: true)
        let done = attentionSession(id: "done", status: .completed(exitCode: 0), entered: 0)
        let api = MockAPI(sessions: [question, done, current, stalled, error], approvalsList: [singleApproval])
        var opened: [Session] = []
        let vm = SessionDetailViewModel(
            session: current, api: api, attentionSessions: [current], onShowNextSession: { opened.append($0) }
        )
        await vm.loadApprovals()
        await vm.respond(to: try XCTUnwrap(vm.currentReplyApproval), decision: .accept)

        XCTAssertEqual(vm.replyApprovalResult?.remainingCount, 3)
        XCTAssertEqual(vm.replyApprovalResult?.nextName, "error")
        XCTAssertEqual(vm.replyApprovalResult?.nextStatusLabel, "エラー")
        XCTAssertTrue(opened.isEmpty)
        await vm.refresh()
        XCTAssertEqual(vm.replyApprovalResult?.actionLabel, "許可")
        XCTAssertTrue(vm.replyApprovals.isEmpty, "ポーリングが同じ承認を返しても再提示しない")
        XCTAssertTrue(opened.isEmpty)

        await vm.showNextAttention()
        XCTAssertEqual(opened.map(\.id), ["error"])
    }

    func testNextAttentionRevalidatesDisappearedCandidateAndItsStatus() async throws {
        let current = session(id: "s1", agent: .codex)
        let old = attentionSession(id: "old", status: .awaitingUserQuestion, entered: 10)
        let api = MockAPI(sessions: [current, old], approvalsList: [singleApproval])
        var opened: [Session] = []
        let vm = SessionDetailViewModel(session: current, api: api, onShowNextSession: { opened.append($0) })
        await vm.loadApprovals()
        await vm.respond(to: try XCTUnwrap(vm.currentReplyApproval), decision: .accept)
        XCTAssertEqual(vm.replyApprovalResult?.nextName, "old")
        XCTAssertEqual(vm.replyApprovalResult?.nextStatusLabel, "質問あり")

        let stalled = attentionSession(id: "new", status: .running, entered: 5, stalled: true)
        await api.setSessions([current, stalled])
        await vm.refresh()
        XCTAssertEqual(vm.replyApprovalResult?.nextName, "new")
        XCTAssertEqual(vm.replyApprovalResult?.nextStatusLabel, "無応答")
        XCTAssertTrue(opened.isEmpty)
        await vm.showNextAttention()
        XCTAssertEqual(opened.map(\.id), ["new"])
    }

    func testNextAttentionStaysOnSentCardWhenQueueEmpties() async throws {
        let current = session(id: "s1", agent: .codex)
        let next = attentionSession(id: "next", status: .awaitingUserQuestion, entered: 10)
        let api = MockAPI(sessions: [current, next], approvalsList: [singleApproval])
        var opened: [String] = []
        let vm = SessionDetailViewModel(session: current, api: api, onShowNextSession: { opened.append($0.id) })
        await vm.loadApprovals()
        await vm.respond(to: try XCTUnwrap(vm.currentReplyApproval), decision: .accept)
        await api.setSessions([current])

        await vm.showNextAttention()

        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(vm.replyApprovalResult?.remainingCount, 0)
        XCTAssertNil(vm.replyApprovalResult?.nextName)
        XCTAssertEqual(vm.replyApprovalResult?.actionLabel, "許可")
    }

    func testNextAttentionFailureKeepsSentResultAndAllowsRetry() async throws {
        let current = session(id: "s1", agent: .codex)
        let next = attentionSession(id: "next", status: .awaitingUserQuestion, entered: 10)
        let api = MockAPI(sessions: [current, next], approvalsList: [singleApproval])
        var opened: [String] = []
        let vm = SessionDetailViewModel(session: current, api: api, onShowNextSession: { opened.append($0.id) })
        await vm.loadApprovals()
        await vm.respond(to: try XCTUnwrap(vm.currentReplyApproval), decision: .accept)
        let sent = vm.replyApprovalResult
        await api.setListSessionsError(.unreachable)

        await vm.showNextAttention()

        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(vm.replyApprovalResult, sent)
        XCTAssertNotNil(vm.replyApprovalError)
        await api.setListSessionsError(nil)
        await vm.showNextAttention()
        XCTAssertEqual(opened, ["next"])
        XCTAssertNil(vm.replyApprovalError)
    }

    func testLocalApprovalsCountOneSessionAndTakePriorityOverOtherSessions() async throws {
        let current = session(id: "s1", agent: .codex)
        let next = attentionSession(id: "next", status: .awaitingUserQuestion, entered: 10)
        let api = MockAPI(sessions: [next, current], approvalsList: [
            singleApproval,
            Approval(id: "a2", sessionID: "s1", kind: .codex, prompt: "second", actionKind: "command"),
            Approval(id: "a3", sessionID: "s1", kind: .codex, prompt: "third", actionKind: "command"),
        ])
        var opened: [String] = []
        let vm = SessionDetailViewModel(session: current, api: api, onShowNextSession: { opened.append($0.id) })
        await vm.loadApprovals()
        await vm.respond(to: try XCTUnwrap(vm.currentReplyApproval), decision: .accept)

        XCTAssertEqual(vm.replyApprovalResult?.remainingCount, 2, "承認の数ではなく対応待ちセッション数")
        XCTAssertEqual(vm.replyApprovalResult?.nextName, "Rose")
        await vm.showNextAttention()
        XCTAssertNil(vm.replyApprovalResult)
        XCTAssertEqual(vm.currentReplyApproval?.id, "codex:a2")
        XCTAssertTrue(opened.isEmpty)
    }

    func testNextAttentionDoesNotNavigateWhenExistingTranscriptCannotRefresh() async throws {
        let current = session(id: "s1", agent: .codex)
        let next = attentionSession(id: "next", status: .awaitingUserQuestion, entered: 10)
        let api = MockAPI(
            sessions: [current, next], approvalsList: [singleApproval],
            messagesOutcome: .success([.fileChange(id: "history", changes: [])])
        )
        var opened: [String] = []
        let vm = SessionDetailViewModel(session: current, api: api, onShowNextSession: { opened.append($0.id) })
        await vm.load()
        await vm.loadApprovals()
        await vm.respond(to: try XCTUnwrap(vm.currentReplyApproval), decision: .accept)
        let sent = vm.replyApprovalResult
        await api.setMessagesOutcome(.failure(.unreachable))

        await vm.showNextAttention()

        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(vm.replyApprovalResult, sent)
        XCTAssertNotNil(vm.replyApprovalError)
        XCTAssertNil(vm.loadError, "履歴表示中の既存の非破壊エラー方針は維持")
    }

    func testLocalQuestionTakesPriorityOverAnotherSessionAfterRefresh() async throws {
        let current = session(id: "s1", agent: .codex)
        let next = attentionSession(id: "next", status: .error(message: "failed"), entered: 10)
        let api = MockAPI(sessions: [current, next], approvalsList: [singleApproval])
        var opened: [String] = []
        let vm = SessionDetailViewModel(session: current, api: api, onShowNextSession: { opened.append($0.id) })
        await vm.loadApprovals()
        await vm.respond(to: try XCTUnwrap(vm.currentReplyApproval), decision: .accept)
        let question = ChatMessage.userQuestion(
            id: "q-new", requestId: "r-new",
            questions: [UserQuestionItem(question: "どちら？", header: "選択", options: [], multiSelect: false)],
            answers: nil, state: .pending
        )
        await api.setMessagesOutcome(.success([question]))

        await vm.showNextAttention()

        XCTAssertTrue(opened.isEmpty)
        XCTAssertNil(vm.replyApprovalResult)
        XCTAssertTrue(vm.visibleMessages.contains(question))
    }

    private var singleApproval: Approval {
        Approval(id: "a1", sessionID: "s1", kind: .codex, prompt: "first", actionKind: "command")
    }

    #if DEBUG
    func testConfiguredFlowNextSnapshotSurvivesPolling() async {
        let vm = SessionDetailViewModel(session: session(id: "s1", agent: .codex), api: MockAPI())
        vm.configureReplySnapshot(.approvalResult(actionLabel: "許可", remainingCount: 2, nextSessionName: "Tulip", nextIsQuestion: true))

        await vm.refresh()

        XCTAssertEqual(vm.replyApprovalResult?.remainingCount, 2)
        XCTAssertEqual(vm.replyApprovalResult?.nextName, "Tulip")
        XCTAssertEqual(vm.replyApprovalResult?.nextStatusLabel, "質問あり")
    }
    #endif

    private func attentionSession(id: String, status: SessionStatus, entered: TimeInterval, stalled: Bool = false) -> Session {
        Session(
            id: id, name: id, agent: .codex, status: status, isStalled: stalled,
            statusEnteredAt: Date(timeIntervalSince1970: entered), updatedAt: enteredAt
        )
    }

    private func session(id: String, agent: AgentKind, status: SessionStatus = .awaitingApproval(prompt: "approval")) -> Session {
        Session(
            id: id, name: "Rose", agent: agent, status: status, statusEnteredAt: enteredAt,
            updatedAt: enteredAt
        )
    }

    private func pendingToolQuestion(allowsSessionScope: Bool = false) -> ChatMessage {
        .userQuestion(
            id: "question-r1", requestId: "r1",
            questions: [makeToolQuestion(name: "Bash", detail: "git rm ControlServer.swift", allowsSessionScope: allowsSessionScope)],
            answers: nil, state: .pending
        )
    }

}

private func makeToolQuestion(name: String, detail: String, allowsSessionScope: Bool) -> UserQuestionItem {
    UserQuestionItem(
        question: "\(name) を実行しますか？", header: name,
        options: [UserQuestionOption(label: "Allow"), UserQuestionOption(label: "Deny")],
        multiSelect: false, toolName: name, toolDetail: detail, allowsSessionScope: allowsSessionScope
    )
}
