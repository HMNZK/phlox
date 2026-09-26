import Foundation

// task-6 契約の PM スタブ。API 表面は受け入れテスト
// ChatHangDetectionAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-6.md

/// 実行中ターンのハング評価結果。
struct ChatHangAssessment: Equatable {
    /// ターン開始からの経過秒。
    let elapsed: TimeInterval
    /// 最後のイベント（無ければターン開始）からの無応答秒。
    let silence: TimeInterval
    /// 無応答が閾値以上（警告＋中断ボタンを出す）。
    let isStalled: Bool
}

/// ハング判定の純関数（時刻は必ず引数で受け、内部で Date() を呼ばない）。
enum ChatHangPolicy {
    /// 30 分（ユーザー決定 2026-09-26。以前は 120 秒で、長いコマンドの実行中にも出ていた）。
    static let defaultWarnAfter: TimeInterval = 30 * 60

    static func assess(
        now: Date,
        turnStartedAt: Date,
        lastEventAt: Date?,
        warnAfter: TimeInterval = defaultWarnAfter
    ) -> ChatHangAssessment {
        let elapsed = max(0, now.timeIntervalSince(turnStartedAt))
        let silenceBase = max(turnStartedAt, lastEventAt ?? turnStartedAt)
        let silence = max(0, now.timeIntervalSince(silenceBase))
        return ChatHangAssessment(
            elapsed: elapsed,
            silence: silence,
            isStalled: silence >= warnAfter
        )
    }
}

/// 「無応答 2:14」の経過表記（会話・ヘッダ・サイドバー・対応待ちの一覧で共通。13 Review）。
public enum StallClock {
    public static func text(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}
