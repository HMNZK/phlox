import Foundation

// task-13 契約の PM スタブ。API 表面は受け入れテスト
// WorkspaceSidebarPolicyAcceptanceTests が凍結している（シグネチャ変更禁止）。
// 実装契約の正本: tasks/task-13.md

/// サイドバーのセッション行右端に出す相対時刻ラベル。
enum SidebarRelativeTime {
    /// 60秒未満 "今" / 60分未満 "N分" / 24時間未満 "N時間" / 30日未満 "N日"
    /// / 365日未満 "Nか月" / それ以上 "N年"（切り捨て・未来時刻は "今"）。
    static func label(from: Date, to: Date) -> String {
        let elapsedSeconds = max(0, Int(to.timeIntervalSince(from)))
        if elapsedSeconds < 60 { return "今" }

        let elapsedMinutes = elapsedSeconds / 60
        if elapsedMinutes < 60 { return "\(elapsedMinutes)分" }

        let elapsedHours = elapsedMinutes / 60
        if elapsedHours < 24 { return "\(elapsedHours)時間" }

        let elapsedDays = elapsedHours / 24
        if elapsedDays < 30 { return "\(elapsedDays)日" }
        if elapsedDays < 365 { return "\(elapsedDays / 30)か月" }
        return "\(elapsedDays / 365)年"
    }
}

/// プロジェクト行左のアイコン表示規則（Q: デフォルト非表示・完了後未読のみ薄表示）。
enum ProjectIconPolicy {
    /// false → nil（アイコンを描画しない）/ true → 0.45（薄く表示）。
    static func opacity(hasUnseenCompletion: Bool) -> Double? {
        hasUnseenCompletion ? 0.45 : nil
    }
}
