import AgentDomain
import Foundation
import StructuredChatKit
import Testing
@testable import SessionFeature

// 05 返答エリア: 承認カード（Codex の承認要求と Claude のツール使用許可を同じ形に）・0.5 秒の誤押下防止・送信失敗の通知。

private final class ReplyFakeClient: StructuredAgentClient, @unchecked Sendable {
    let events: AsyncStream<NormalizedChatEvent>
    private let continuation: AsyncStream<NormalizedChatEvent>.Continuation
    private(set) var answers: [[String: [String]]] = []
    var failTurnStart = false
    var holdTurnStart = false
    private var heldTurnStart: CheckedContinuation<Void, Never>?

    init() {
        var continuation: AsyncStream<NormalizedChatEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func start() async {}
    func turnStart(_ input: [ChatInput]) async throws {
        if holdTurnStart { await withCheckedContinuation { heldTurnStart = $0 } }
        if failTurnStart { throw ReplyFakeError.connectionLost }
    }
    var isHoldingTurnStart: Bool { heldTurnStart != nil }
    func releaseTurnStart() { heldTurnStart?.resume(); heldTurnStart = nil }
    func resume(sessionRef: String) async throws {}
    func interrupt() async throws {}
    func close() async { continuation.finish() }
    func respondToUserQuestion(requestId: String, answers: [String: [String]]) async {
        self.answers.append(answers)
    }

    func yield(_ event: NormalizedChatEvent) { continuation.yield(event) }
}

private enum ReplyFakeError: LocalizedError {
    case connectionLost
    var errorDescription: String? { "app-server との接続が切れました\n詳細" }
}

@MainActor
private func makeVM(_ client: ReplyFakeClient) async throws -> ChatSessionViewModel {
    let vm = ChatSessionViewModel(
        id: SessionID(),
        agentRef: .builtin(.claudeCode),
        client: client,
        approvalBroker: ChatApprovalBroker(),
        workingDirectory: "/tmp/work"
    )
    try await vm.startNew(approvalPolicy: .named("on-request"), sandbox: .named("workspace-write"))
    return vm
}

private func permissionQuestion(tool: String, detail: String) -> ChatUserQuestion {
    ChatUserQuestion(
        question: "Allow \(tool)? \(detail)",
        header: tool,
        options: [ChatUserQuestionOption(label: "Allow"), ChatUserQuestionOption(label: "Deny")],
        multiSelect: false,
        permission: ChatToolPermission(toolName: tool, detail: detail)
    )
}

@Test @MainActor
func replyApproval_claudeToolPermission_becomesApprovalCardNotQuestionCard() async throws {
    let client = ReplyFakeClient()
    let vm = try await makeVM(client)
    client.yield(.userQuestionRequested(requestId: "p1", questions: [permissionQuestion(tool: "Bash", detail: "swift test --filter X")]))
    client.yield(.userQuestionRequested(requestId: "q1", questions: [
        ChatUserQuestion(question: "どちら?", header: "選択", options: [ChatUserQuestionOption(label: "A")], multiSelect: false),
    ]))
    try await waitUntil { vm.transcript.count >= 2 }

    let approvals = vm.replyApprovals
    #expect(approvals.count == 1)
    #expect(approvals.first?.kind == .command)
    #expect(approvals.first?.subject == "swift test --filter X")
    #expect(approvals.first?.supportsSessionScope == false)
}

@Test @MainActor
func replyApproval_ignoresPressWithinHalfSecond_thenSendsAllow() async throws {
    let client = ReplyFakeClient()
    let vm = try await makeVM(client)
    client.yield(.userQuestionRequested(requestId: "p1", questions: [permissionQuestion(tool: "WebFetch", detail: "https://example.com")]))
    try await waitUntil { vm.currentReplyApproval != nil }
    let approval = try #require(vm.currentReplyApproval)
    #expect(approval.kind == .tool)

    let shownAt = Date()
    vm.markApprovalPresented(approval.id, at: shownAt)
    // 出た直後（0.3 秒）の押下は無視する。
    #expect(await vm.respond(to: approval, decision: .accept, now: shownAt.addingTimeInterval(0.3)) == false)
    #expect(client.answers.isEmpty)

    #expect(await vm.respond(to: approval, decision: .accept, now: shownAt.addingTimeInterval(0.6)))
    #expect(client.answers == [[approval.toolPermissionAnswerKey: ["Allow"]]])
    #expect(vm.replyApprovals.isEmpty)
}

@Test @MainActor
func replyApproval_notYetShown_isNotArmed() async throws {
    let client = ReplyFakeClient()
    let vm = try await makeVM(client)
    client.yield(.userQuestionRequested(requestId: "p1", questions: [permissionQuestion(tool: "Edit", detail: "/tmp/work/a.swift")]))
    try await waitUntil { vm.currentReplyApproval != nil }
    let approval = try #require(vm.currentReplyApproval)
    #expect(approval.kind == .fileChange)
    #expect(approval.files.map(\.path) == ["/tmp/work/a.swift"])
    // 画面に出ていない要求はメニューのキーでも返せない。
    await vm.respondToCurrentApproval(.decline)
    #expect(client.answers.isEmpty)
}

@Test
func replyApproval_lineCountsIgnoreDiffHeaders() {
    let diff = """
    --- a/x
    +++ b/x
    @@ -1,2 +1,3 @@
     keep
    -old
    +new
    +added
    """
    let counts = ReplyApproval.lineCounts(diff: diff)
    #expect(counts?.added == 2)
    #expect(counts?.removed == 1)
    #expect(ReplyApproval.lineCounts(diff: "") == nil)
}

@Test @MainActor
func sendFailure_restoresDraftAndShowsFirstLineOfReason() async throws {
    let client = ReplyFakeClient()
    client.failTurnStart = true
    let vm = try await makeVM(client)
    vm.draft = "DTO にも expiresAt を足して"
    let text = try #require(vm.consumeDraftForSend())
    try? await vm.sendText(text, submit: true)

    #expect(vm.draft == "DTO にも expiresAt を足して")
    #expect(vm.sendFailure == .init(reason: "app-server との接続が切れました", restoredDraft: true))
    #expect(vm.inFlightText == nil)


    client.failTurnStart = false
    let retry = try #require(vm.consumeDraftForSend())
    try await vm.sendText(retry, submit: true)
    #expect(vm.sendFailure == nil)
}

@Test @MainActor
func sendFailure_whileSending_composerCannotSubmitAgainAndFailedTextComesBack() async throws {
    let client = ReplyFakeClient()
    client.holdTurnStart = true
    client.failTurnStart = true
    let vm = try await makeVM(client)
    vm.draft = "A"
    let text = try #require(vm.consumeDraftForSend())
    let send = Task { try? await vm.sendText(text, submit: true) }
    try await waitUntil { client.isHoldingTurnStart }
    #expect(vm.inFlightText == "A")
    // 送信中は二重送信しない（入力欄も書けない）。
    #expect(vm.consumeDraftForSend() == nil)
    client.releaseTurnStart()
    await send.value
    #expect(vm.draft == "A")
    #expect(vm.sendFailure?.restoredDraft == true)
}

private extension ReplyApproval {
    var toolPermissionAnswerKey: String {
        if case .toolPermission(_, let key) = source { return key }
        return ""
    }
}
