import Foundation
import AgentDomain

/// セッションの完了通知（Mac ローカル通知＋ iOS への APNs push）を発火すべき状態遷移かを
/// 一元判定する純ポリシー（tasks/task-4.md 契約。受け入れテスト
/// AcceptanceNotificationGapTests が凍結）。
///
/// `running` からの停止と、実行中ターンが入力待ちへ移った後の停止を同じ規則で扱う。
enum SessionCompletionNotificationPolicy {
    /// previous → next の遷移で「本物の完了」として通知すべきか。
    static func shouldNotifyCompletion(previous: SessionStatus, next: SessionStatus) -> Bool {
        previous == .running && isTerminal(next)
    }

    /// Chat 型はターンの途中で approval / question 待ちへ移れる。復元リプレイなど、
    /// 実行中ターンを持たない待機状態からの終端化は通知しない。
    static func shouldNotifyCompletion(
        previous: SessionStatus,
        next: SessionStatus,
        hasActiveTurn: Bool
    ) -> Bool {
        guard hasActiveTurn, isTerminal(next) else { return false }
        switch previous {
        case .running, .awaitingApproval, .awaitingUserQuestion:
            return true
        default:
            return false
        }
    }

    private static func isTerminal(_ status: SessionStatus) -> Bool {
        switch status {
        case .idle, .completed, .error:
            return true
        default:
            return false
        }
    }
}
