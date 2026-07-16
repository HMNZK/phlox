import Foundation

/// 一覧の更新時刻表示用の、決定論的なコンパクト相対時刻フォーマッタ（日本語）。
/// `RelativeDateTimeFormatter` はロケール/実行時刻でブレるためテストしづらい。ここでは
/// 「今 / N分前 / N時間前 / N日前」に丸める純粋関数として定義し、テストで固定する。
public enum DSRelativeTime {
    /// 一覧行用のコンパクト相対時刻（カンプ②準拠）。
    /// 5 秒未満は「今」、60 秒未満は秒表示、以降は分/時間/日前。
    public static func compact(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<5:
            return "今"
        case ..<60:
            return "\(Int(seconds))秒前"
        case ..<3600:
            return "\(Int(seconds / 60))分前"
        case ..<86_400:
            return "\(Int(seconds / 3600))時間前"
        default:
            return "\(Int(seconds / 86_400))日前"
        }
    }
}
