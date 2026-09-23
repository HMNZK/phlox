import Foundation

// API 表面は受け入れテスト WorkspaceSidebarPolicyAcceptanceTests が凍結している（シグネチャ変更禁止）。
// DashboardFeature では `SidebarRelativeTime` の名前で使う。グリッドのタイル見出しでも使うためここに置く。

/// サイドバーのセッション行右端・グリッドのタイル見出しに出す相対時刻ラベル。
public enum SessionRelativeTime {
    /// 60秒未満 "今" / 60分未満 "N分" / 24時間未満 "N時間" / 30日未満 "N日"
    /// / 365日未満 "Nか月" / それ以上 "N年"（切り捨て・未来時刻は "今"）。
    public static func label(from: Date, to: Date) -> String {
        let (value, unit) = elapsed(from: from, to: to)
        switch unit {
        case .now: return "今"
        case .minute: return "\(value)分"
        case .hour: return "\(value)時間"
        case .day: return "\(value)日"
        case .month: return "\(value)か月"
        case .year: return "\(value)年"
        }
    }

    /// 表示言語に合わせた版。日本語以外は「now / 5m / 3h / 2d / 1mo / 1y」。
    public static func label(from: Date, to: Date, locale: Locale) -> String {
        guard locale.language.languageCode?.identifier != "ja" else { return label(from: from, to: to) }
        let (value, unit) = elapsed(from: from, to: to)
        switch unit {
        case .now: return "now"
        case .minute: return "\(value)m"
        case .hour: return "\(value)h"
        case .day: return "\(value)d"
        case .month: return "\(value)mo"
        case .year: return "\(value)y"
        }
    }

    private enum Unit { case now, minute, hour, day, month, year }

    private static func elapsed(from: Date, to: Date) -> (Int, Unit) {
        let elapsedSeconds = max(0, Int(to.timeIntervalSince(from)))
        if elapsedSeconds < 60 { return (0, .now) }

        let elapsedMinutes = elapsedSeconds / 60
        if elapsedMinutes < 60 { return (elapsedMinutes, .minute) }

        let elapsedHours = elapsedMinutes / 60
        if elapsedHours < 24 { return (elapsedHours, .hour) }

        let elapsedDays = elapsedHours / 24
        if elapsedDays < 30 { return (elapsedDays, .day) }
        if elapsedDays < 365 { return (elapsedDays / 30, .month) }
        return (elapsedDays / 365, .year)
    }
}
