import Foundation
import CodexAppServerKit
import StructuredChatKit

// Hidden secret: approval continuations are resumed exactly once across actor interleavings.
public actor ChatApprovalBroker {
    private struct Pending: Sendable {
        let kind: ChatApprovalKind
        let permissions: JSONValue?
        let continuation: CheckedContinuation<JSONValue, Error>
    }

    private struct PendingUserInput: Sendable {
        let continuation: CheckedContinuation<JSONValue, Error>
    }

    private var pending: [UUID: Pending] = [:]
    private var pendingUserInputs: [UUID: PendingUserInput] = [:]
    /// terminal 状態。cancelAll（terminate 由来）以降に到達した承認要求は pending に積まず
    /// 即時に否認で解決する（S1: close 進行中の遅延到達要求がリークするのを構造的に防ぐ）。
    private var isClosed = false
    private let continuation: AsyncStream<ChatApprovalRequest>.Continuation
    public let requests: AsyncStream<ChatApprovalRequest>

    /// Codex の `item/tool/requestUserInput`（質問）を流すストリーム。承認とは別経路。
    /// codex-full-access-approval task-0 で公開面を凍結し、task-2 で実装する。
    private let userInputContinuation: AsyncStream<ChatUserInputRequest>.Continuation
    public let userInputRequests: AsyncStream<ChatUserInputRequest>

    public init() {
        var continuation: AsyncStream<ChatApprovalRequest>.Continuation?
        self.requests = AsyncStream { continuation = $0 }
        self.continuation = continuation!

        var userInputContinuation: AsyncStream<ChatUserInputRequest>.Continuation?
        self.userInputRequests = AsyncStream { userInputContinuation = $0 }
        self.userInputContinuation = userInputContinuation!
    }

    /// 質問への回答を wire へ返す。
    /// `answers` のキーは `ChatUserQuestion.answerKey`（＝codex の `questions[].id`）。
    public func answerUserInput(id: UUID, answers: [String: [String]]) {
        guard let value = pendingUserInputs.removeValue(forKey: id) else { return }
        resolveUserInput(value, answers: answers)
    }

    /// 質問への回答を拒否し、wire を空回答で決着させる。
    /// ターンの中断そのものは呼び出し元（ViewModel）の責務。
    public func declineUserInput(id: UUID) {
        guard let value = pendingUserInputs.removeValue(forKey: id) else { return }
        resolveUserInput(value, answers: [:])
    }

    public nonisolated var serverRequestHandler: JSONRPCClient.ServerRequestHandler {
        { request in
            try await self.handle(request)
        }
    }

    public func respond(to id: UUID, decision: ApprovalDecision) {
        // 取り出してから resume（同一 actor 上でアトミック。cancelAll と競合しても二重 resume しない）。
        guard let value = pending.removeValue(forKey: id) else { return }
        resolve(value, decision: decision)
    }

    /// 承認待ちで await 中の continuation を「ちょうど1回ずつ」否認で解決し、broker を terminal に閉じる（S1）。
    /// terminate から呼ばれ、continuation リークを防ぐ。取り出し（removeAll）と resume の間に
    /// await を挟まないため、respond との競合でも同一 continuation を2回 resume しない・0回にもしない。
    /// isClosed を立てるので、この呼び出し以降に到達した承認要求は handle() が即時否認で解決する
    /// （close 進行中に遅延到達する要求のリークを防ぐ）。複数回呼ばれても2回目以降は冪等。
    public func cancelAll() {
        isClosed = true

        let drained = pending
        pending.removeAll()
        for (_, value) in drained {
            resolve(value, decision: .decline)
        }

        let drainedUserInputs = pendingUserInputs
        pendingUserInputs.removeAll()
        for (_, value) in drainedUserInputs {
            resolveUserInput(value, answers: [:])
        }
    }

    /// pending 1件を decision に応じた JSON で resume する（respond と cancelAll が共有）。
    private func resolve(_ value: Pending, decision: ApprovalDecision) {
        switch value.kind {
        case .command, .fileChange:
            value.continuation.resume(returning: .object(["decision": .string(decision.rawValue)]))
        case .permissions:
            if decision == .accept || decision == .acceptForSession {
                value.continuation.resume(returning: .object([
                    "permissions": value.permissions ?? .null,
                    "scope": .string(decision == .acceptForSession ? "session" : "turn"),
                ]))
            } else {
                value.continuation.resume(returning: .object(["decision": .string(decision.rawValue)]))
            }
        }
    }

    private func handle(_ request: ServerRequest) async throws -> JSONValue {
        switch request {
        case .commandExecutionApproval(let value):
            let approval = makeApproval(
                kind: .command,
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                prompt: value.reason ?? value.command ?? "Command approval requested"
            )
            return try await handleApproval(approval, permissions: nil)
        case .fileChangeApproval(let value):
            let approval = makeApproval(
                kind: .fileChange,
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                prompt: value.reason ?? "File change approval requested"
            )
            return try await handleApproval(approval, permissions: nil)
        case .permissionsApproval(let value):
            let approval = makeApproval(
                kind: .permissions,
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                prompt: value.reason ?? "Permission approval requested"
            )
            return try await handleApproval(approval, permissions: value.permissions)
        case .userInputRequest(let value):
            return try await handleUserInput(value)
        case .unknown(let method, _):
            throw JSONRPCClientError.unsupportedServerRequest(method)
        }
    }

    private func handleApproval(
        _ approval: ChatApprovalRequest,
        permissions: JSONValue?
    ) async throws -> JSONValue {
        // terminal 後に到達した要求は pending に積まず即時否認で解決する。isClosed の判定と
        // pending 登録の間に await が無い（continuation クロージャは同一 actor ジョブで同期実行される）
        // ため、cancelAll と handle の interleaving でも「積んだが drain されない」窓が生じない（S1）。
        if isClosed {
            return .object(["decision": .string(ApprovalDecision.decline.rawValue)])
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[approval.id] = Pending(
                kind: approval.kind,
                permissions: permissions,
                continuation: continuation
            )
            self.continuation.yield(approval)
        }
    }

    private func handleUserInput(_ request: ToolRequestUserInputRequest) async throws -> JSONValue {
        let userInput = makeUserInputRequest(from: request)
        // terminal 後に到達した質問は保留へ積まず即時に空回答で解決する。isClosed の判定と
        // pendingUserInputs 登録の間に await が無いため、cancelAll との interleaving でも
        // 「積んだが drain されない」窓が生じない。
        if isClosed {
            return userInputResponse(answers: [:])
        }
        return try await withCheckedThrowingContinuation { continuation in
            pendingUserInputs[userInput.id] = PendingUserInput(continuation: continuation)
            // 質問応答の continuation を保留へ登録してから yield するため、起動順序による取りこぼしを防ぐ。
            userInputContinuation.yield(userInput)
        }
    }

    private func makeApproval(
        kind: ChatApprovalKind,
        threadId: String,
        turnId: String,
        itemId: String,
        prompt: String
    ) -> ChatApprovalRequest {
        ChatApprovalRequest(
            id: UUID(),
            kind: kind,
            threadId: threadId,
            turnId: turnId,
            itemId: itemId,
            prompt: prompt
        )
    }

    private func makeUserInputRequest(from request: ToolRequestUserInputRequest) -> ChatUserInputRequest {
        ChatUserInputRequest(
            id: UUID(),
            threadId: request.threadId,
            turnId: request.turnId,
            itemId: request.itemId,
            questions: request.questions.map { question in
                ChatUserQuestion(
                    question: question.question,
                    header: question.header,
                    options: question.options?.map {
                        ChatUserQuestionOption(label: $0.label, description: $0.description)
                    } ?? [],
                    multiSelect: false,
                    id: question.id
                )
            }
        )
    }

    private func resolveUserInput(_ value: PendingUserInput, answers: [String: [String]]) {
        value.continuation.resume(returning: userInputResponse(answers: answers))
    }

    private func userInputResponse(answers: [String: [String]]) -> JSONValue {
        let entries = answers.reduce(into: [String: JSONValue]()) { result, answer in
            result[answer.key] = .object([
                "answers": .array(answer.value.map { .string($0) })
            ])
        }
        return .object(["answers": .object(entries)])
    }
}
