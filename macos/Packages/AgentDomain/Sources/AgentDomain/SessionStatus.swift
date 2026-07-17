import Foundation

public enum SessionStatus: Sendable, Equatable {
    case starting
    case idle
    case running
    case awaitingApproval(prompt: String)
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
        case .awaitingApproval, .completed, .error:
            true
        case .starting, .idle, .running:
            false
        }
    }
}
