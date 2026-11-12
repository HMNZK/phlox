import Foundation

public enum ChatDurationFormat {
    /// 見出しとタスク: m:ss、1 時間以上は h:mm:ss。60 秒未満も 0:09。
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let hours = total / 3600, minutes = total % 3600 / 60, rest = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest)
            : String(format: "%d:%02d", minutes, rest)
    }

    /// 作業の行: 10 秒未満は 1.9s、60 秒未満は 14s、それ以上は m:ss。
    public static func action(_ seconds: TimeInterval) -> String {
        if seconds < 0.1 { return "<0.1s" }
        if seconds < 10 { return String(format: "%.1fs", max(0, seconds)) }
        if seconds < 60 { return "\(Int(seconds))s" }
        return clock(seconds)
    }
}
