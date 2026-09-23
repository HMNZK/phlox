import Foundation

public enum SessionStatus: Sendable, Equatable {
    case starting
    case idle
    case running
    case awaitingApproval(prompt: String)
    /// AskUserQuestion の回答待ち（ask-question-ux task-1 契約。
    /// 受け入れテスト AcceptanceUserQuestionStatusTests / SessionStatusAttentionTests が凍結）。
    case awaitingUserQuestion
    case completed(exitCode: Int32)
    case error(message: String)
}

public extension SessionStatus {
    /// この状態へ「入った」こと自体が、未確認の停止（＝ユーザーの対応待ち）としてラッチ対象か。
    /// 承認待ち・完了(プロセス終了)・エラーは入った時点で常に要対応。
    /// 一方 idle（ターン完了して入力待ち）は「本物のターン完了」か「escape/interrupt による
    /// 中断キャンセル」かを入口では区別できないため、ここには含めず、完了通知経路
    /// （notifyCompletionIfNeeded: running→idle）でのみラッチする。起動直後の
    /// starting→idle（単に入力受付可能になっただけ）もラッチしない。
    var latchesUnseenAttentionOnEntry: Bool {
        switch self {
        case .awaitingApproval, .awaitingUserQuestion, .completed, .error:
            true
        case .starting, .idle, .running:
            false
        }
    }

    /// 付随値（承認待ちの prompt・エラー文・終了コード）を除いた状態の種類が同じか。
    /// 待ち時間の起点を、同じ状態のまま付随値だけが変わったときに動かさないために使う。
    func hasSameKind(as other: SessionStatus) -> Bool {
        switch (self, other) {
        case (.starting, .starting), (.idle, .idle), (.running, .running),
             (.awaitingApproval, .awaitingApproval), (.awaitingUserQuestion, .awaitingUserQuestion),
             (.completed, .completed), (.error, .error):
            true
        default:
            false
        }
    }
}

/// セッションが「ユーザーの対応待ちで赤表示を維持すべきか」の導出（ask-question-ux task-2 契約。
/// 受け入れテスト AcceptanceSessionAttentionPolicyTests が凍結。スタブ実装＝task-2 が本実装する）。
public enum SessionAttentionPolicy {
    public static func requiresAttention(status: SessionStatus, hasUnseenCompletion: Bool) -> Bool {
        if hasUnseenCompletion { return true }
        switch status {
        case .awaitingApproval, .awaitingUserQuestion:
            return true
        case .starting, .idle, .running, .completed, .error:
            return false
        }
    }
}
