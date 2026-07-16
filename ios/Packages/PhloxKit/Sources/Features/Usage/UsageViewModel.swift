import SwiftUI
import PhloxCore

/// アカウント単位の CLI 使用量（Usageリミットタブ / task-8）。
@MainActor
@Observable
public final class UsageViewModel {
    public enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    private let api: PhloxAPI

    public private(set) var state: State = .idle
    public private(set) var agents: [CLIUsage] = []

    public init(api: PhloxAPI) {
        self.api = api
    }

    /// `.loaded` かつエージェント 0 件のとき true。
    public var isEmpty: Bool {
        state == .loaded && agents.isEmpty
    }

    /// `state == .unavailable` のエージェントのみ利用不可とみなす。
    public static func isUnavailable(_ usage: CLIUsage) -> Bool {
        usage.state == .unavailable
    }

    /// 0–100 にクランプし整数パーセント文字列へ丸める（表示用）。
    public nonisolated static func formattedUsedPercent(_ percent: Double) -> String {
        let clamped = min(100, max(0, percent))
        return "\(Int(clamped.rounded()))%"
    }

    /// リセット時刻の表示文言。nil は非表示。24 時間以内は相対、以降は絶対日時。
    public nonisolated static func resetsAtLabel(
        for date: Date?,
        now: Date,
        calendar: Calendar = .current,
        locale: Locale = Locale(identifier: "ja_JP")
    ) -> String? {
        guard let date else { return nil }
        let interval = date.timeIntervalSince(now)
        if interval <= 0 {
            return "リセット済み"
        }
        if interval < 86_400 {
            if interval < 60 {
                return "あと\(Int(interval.rounded()))秒"
            }
            if interval < 3600 {
                return "あと\(Int((interval / 60).rounded()))分"
            }
            return "あと\(Int((interval / 3600).rounded()))時間"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateFormat = "M/d HH:mm"
        return "リセット \(formatter.string(from: date))"
    }

    public func load() async {
        state = .loading
        do {
            agents = try await api.cliUsage()
            state = .loaded
        } catch {
            agents = []
            state = .failed
        }
    }
}
