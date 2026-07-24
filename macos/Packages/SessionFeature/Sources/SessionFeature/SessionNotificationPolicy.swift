import Foundation
import AgentDomain

/// セッションの完了通知（Mac ローカル通知＋ iOS への APNs push）を発火すべき状態遷移かを
/// 一元判定する純ポリシー（tasks/task-4.md 契約。受け入れテスト
/// AcceptanceNotificationGapTests が凍結）。
///
/// スケルトン（フェーズ1 凍結公開面）: 現行挙動（running→idle のみ）を写しただけの仮実装。
/// task-4 が取りこぼし遷移（プロセス終了 completed/error、承認・質問待ち経由の完了）を実装する。
enum SessionCompletionNotificationPolicy {
    /// previous → next の遷移で「本物の完了」として通知すべきか。
    static func shouldNotifyCompletion(previous: SessionStatus, next: SessionStatus) -> Bool {
        previous == .running && next == .idle
    }
}
