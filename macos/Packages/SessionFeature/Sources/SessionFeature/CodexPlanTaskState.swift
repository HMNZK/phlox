import Observation
import CodexAppServerKit
import StructuredChatKit

/// Codex の plan 通知を、表示用のタスクリストとして保持する状態。
///
/// plan は thread/turn ごとのスナップショットなので、別の thread/turn の通知を
/// 現在の状態へ混ぜない。項目の status と id は既存の normalized 写像を使う。
@MainActor @Observable
public final class CodexPlanTaskState {
    /// この状態が受け付ける thread。空文字列は未束縛を表す。
    public private(set) var threadId: String
    /// この状態が受け付ける turn。空文字列は未束縛を表す。
    public private(set) var turnId: String
    public private(set) var tasks: [AgentTaskItem] = []
    public private(set) var explanation: String?

    public init(threadId: String = "", turnId: String = "") {
        self.threadId = threadId
        self.turnId = turnId
    }

    /// thread/turn 境界で、前の plan スナップショットを破棄する。
    ///
    /// plan 通知は turn 単位で届くため、次の turn を受け付ける前に
    /// identity と表示内容を一緒に更新する。
    public func reset(threadId: String = "", turnId: String = "") {
        self.threadId = threadId
        self.turnId = turnId
        tasks = []
        explanation = nil
    }

    /// plan event を適用する。対象外・不正な event は false を返し、状態を変えない。
    @discardableResult
    public func apply(_ event: ThreadEvent) -> Bool {
        guard case .planUpdated(let threadId, let turnId, let plan, let explanation) = event else {
            return false
        }
        return apply(
            threadId: threadId,
            turnId: turnId,
            plan: plan,
            explanation: explanation
        )
    }

    /// ラベル付きの event 適用窓口。非同期 event ループからも意図を明示できる。
    @discardableResult
    public func apply(event: ThreadEvent) -> Bool {
        apply(event)
    }

    /// typed plan のスナップショットを適用する。
    @discardableResult
    public func apply(
        threadId: String,
        turnId: String,
        plan: [TurnPlanStep],
        explanation: String? = nil
    ) -> Bool {
        guard isValidIdentity(threadId: threadId, turnId: turnId), accepts(threadId: threadId, turnId: turnId) else {
            return false
        }

        // AgentTaskItem は既知の3 statusしか表せないため、未知 status を含む
        // スナップショットは部分適用せず、直前の有効な状態を維持する。
        guard plan.allSatisfy({
            switch $0.status {
            case .pending, .inProgress, .completed:
                true
            case .unknown:
                false
            }
        }) else {
            return false
        }

        guard case .taskListUpdated(let tasks)? = CodexStructuredAgentClient.normalizedEvent(
            from: .planUpdated(
                threadId: threadId,
                turnId: turnId,
                plan: plan,
                explanation: explanation
            )
        ) else {
            return false
        }

        bindIfNeeded(threadId: threadId, turnId: turnId)
        self.tasks = tasks
        self.explanation = explanation
        return true
    }

    /// 既に既存型へ正規化された項目を、同じ identity で適用する。
    @discardableResult
    public func apply(
        threadId: String,
        turnId: String,
        tasks: [AgentTaskItem],
        explanation: String? = nil
    ) -> Bool {
        guard isValidIdentity(threadId: threadId, turnId: turnId), accepts(threadId: threadId, turnId: turnId) else {
            return false
        }

        bindIfNeeded(threadId: threadId, turnId: turnId)
        self.tasks = tasks
        self.explanation = explanation
        return true
    }

    private func isValidIdentity(threadId: String, turnId: String) -> Bool {
        !threadId.isEmpty && !turnId.isEmpty
    }

    private func accepts(threadId: String, turnId: String) -> Bool {
        (self.threadId.isEmpty || self.threadId == threadId)
            && (self.turnId.isEmpty || self.turnId == turnId)
    }

    private func bindIfNeeded(threadId: String, turnId: String) {
        if self.threadId.isEmpty {
            self.threadId = threadId
        }
        if self.turnId.isEmpty {
            self.turnId = turnId
        }
    }
}
