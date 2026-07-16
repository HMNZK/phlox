import Foundation
import CodexAppServerKit

// Hidden secret: approval continuations are resumed exactly once across actor interleavings.
public actor ChatApprovalBroker {
    private struct Pending: Sendable {
        let kind: ChatApprovalKind
        let permissions: JSONValue?
        let continuation: CheckedContinuation<JSONValue, Error>
    }

    private var pending: [UUID: Pending] = [:]
    /// terminal 状態。cancelAll（terminate 由来）以降に到達した承認要求は pending に積まず
    /// 即時に否認で解決する（S1: close 進行中の遅延到達要求がリークするのを構造的に防ぐ）。
    private var isClosed = false
    private let continuation: AsyncStream<ChatApprovalRequest>.Continuation
    public let requests: AsyncStream<ChatApprovalRequest>

    public init() {
        var continuation: AsyncStream<ChatApprovalRequest>.Continuation?
        self.requests = AsyncStream { continuation = $0 }
        self.continuation = continuation!
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
        guard !pending.isEmpty else { return }
        let drained = pending
        pending.removeAll()
        for (_, value) in drained {
            resolve(value, decision: .decline)
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
        let approval = makeApproval(from: request)
        // terminal 後に到達した要求は pending に積まず即時否認で解決する。isClosed の判定と
        // pending 登録の間に await が無い（continuation クロージャは同一 actor ジョブで同期実行される）
        // ため、cancelAll と handle の interleaving でも「積んだが drain されない」窓が生じない（S1）。
        if isClosed {
            return .object(["decision": .string(ApprovalDecision.decline.rawValue)])
        }
        return try await withCheckedThrowingContinuation { continuation in
            pending[approval.id] = Pending(
                kind: approval.kind,
                permissions: permissions(from: request),
                continuation: continuation
            )
            self.continuation.yield(approval)
        }
    }

    private func makeApproval(from request: ServerRequest) -> ChatApprovalRequest {
        switch request {
        case .commandExecutionApproval(let value):
            ChatApprovalRequest(
                id: UUID(),
                kind: .command,
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                prompt: value.reason ?? value.command ?? "Command approval requested"
            )
        case .fileChangeApproval(let value):
            ChatApprovalRequest(
                id: UUID(),
                kind: .fileChange,
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                prompt: value.reason ?? "File change approval requested"
            )
        case .permissionsApproval(let value):
            ChatApprovalRequest(
                id: UUID(),
                kind: .permissions,
                threadId: value.threadId,
                turnId: value.turnId,
                itemId: value.itemId,
                prompt: value.reason ?? "Permission approval requested"
            )
        case .unknown(let method, _):
            ChatApprovalRequest(
                id: UUID(),
                kind: .permissions,
                threadId: "",
                turnId: "",
                itemId: "",
                prompt: "Unsupported server request: \(method)"
            )
        }
    }

    private func permissions(from request: ServerRequest) -> JSONValue? {
        if case .permissionsApproval(let value) = request {
            value.permissions
        } else {
            nil
        }
    }
}

