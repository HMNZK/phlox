import Foundation

// task-16 契約の PM スタブ。API 表面は受け入れテスト
// ClaudeUsageVisibilityAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-16.md

/// Claude Usage データの鮮度注記。statusLine はターミナルセッションでしか発火しない
/// （チャットモードでは供給が止まる）ため、stale/未取得を理由つきで可視化する。
enum ClaudeUsageStaleness {
    static let staleAfter: TimeInterval = 30 * 60
    private static let hourInterval: TimeInterval = 60 * 60
    private static let dayInterval: TimeInterval = 24 * hourInterval

    /// nil = 新鮮（注記なし）。それ以外は行に添える注記テキスト。
    static func note(now: Date, dataAsOf: Date?) -> String? {
        guard let dataAsOf else {
            return "未取得（ターミナルの Claude セッション実行時に更新されます）"
        }

        let elapsed = now.timeIntervalSince(dataAsOf)
        guard elapsed >= staleAfter else { return nil }

        if elapsed < hourInterval {
            let minutes = Int(elapsed / 60)
            return "\(minutes)分前の値"
        }
        if elapsed < dayInterval {
            let hours = Int(elapsed / hourInterval)
            return "\(hours)時間前の値"
        }
        let days = Int(elapsed / dayInterval)
        return "\(days)日前の値"
    }
}
