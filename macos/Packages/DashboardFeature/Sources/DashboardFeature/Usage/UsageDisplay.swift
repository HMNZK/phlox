import AgentDomain
import SwiftUI

enum UsageDisplay {
    /// トップバー chip のブランドアイコンサイズ（DSFont.caption 行高相当、DSIconSize.m と同値）。
    static let topBarBrandIconSize: CGFloat = 12

    /// サイドバー/トップバーに表示する CLI を AgentKind.allCases の順で返す。
    /// showUnavailable = false のとき、usages に無い・unavailable の CLI を除外する。
    static func visibleKinds(
        usages: [AgentKind: CLIUsage],
        showUnavailable: Bool
    ) -> [AgentKind] {
        if showUnavailable {
            return AgentKind.allCases
        }
        return AgentKind.allCases.filter { kind in
            if kind == .claudeCode, usages[kind] != nil {
                return true
            }
            if case .ok = usages[kind]?.state {
                return true
            }
            return false
        }
    }

    /// トップバーに使用量チップ群を出してよいか。
    /// 「ヘッダーに使用量を表示」設定がオン、かつインスペクター非表示のときだけ true。
    static func showsTopBarUsage(showInHeader: Bool, inspectorVisible: Bool) -> Bool {
        showInHeader && !inspectorVisible
    }

    /// トップバーに出す1CLI分のチップ情報。
    struct TopBarChip: Identifiable {
        let kind: AgentKind
        let allBuckets: [UsageBucket]
        let shownBuckets: [UsageBucket]
        let unavailableReason: String?
        let staleNote: String?

        var id: AgentKind { kind }

        var isUnavailable: Bool { unavailableReason != nil }
    }

    /// トップバーに出すチップ列を構築する。並び順は AgentKind.allCases 順（visibleKinds と同じ規則）。
    /// - showUnavailable == false: .ok の CLI のみ。ただし Claude は .unavailable でも理由つきで残す(ADR 0039)。
    /// - showUnavailable == true: .unavailable の CLI も理由つきチップにする。
    /// - .ok でも表示バケットが空ならチップを作らない。
    /// - Claude の .ok かつ dataAsOf != nil のときだけ staleNote を付ける（ADR 0099: .ok 表示中は注記を重ねない）。
    static func topBarChips(
        usages: [AgentKind: CLIUsage],
        showUnavailable: Bool,
        now: Date
    ) -> [TopBarChip] {
        visibleKinds(usages: usages, showUnavailable: showUnavailable).compactMap { kind -> TopBarChip? in
            guard let usage = usages[kind] else { return nil }
            switch usage.state {
            case .unavailable(let reason):
                return TopBarChip(
                    kind: kind,
                    allBuckets: [],
                    shownBuckets: [],
                    unavailableReason: reason,
                    staleNote: nil
                )
            case .ok(let buckets):
                let shown = topBarBuckets(buckets)
                guard !shown.isEmpty else { return nil }
                let staleNote = (kind == .claudeCode && usage.dataAsOf != nil)
                    ? ClaudeUsageStaleness.note(now: now, dataAsOf: usage.dataAsOf)
                    : nil
                return TopBarChip(
                    kind: kind,
                    allBuckets: buckets,
                    shownBuckets: shown,
                    unavailableReason: nil,
                    staleNote: staleNote
                )
            }
        }
    }

    /// トップバーで表示するバケット列。5時間上限(id "5h")と週次(id "weekly")をこの順で返し、
    /// どちらも持たない CLI(Cursor 等)は全バケットを返す。空なら空配列。
    static func topBarBuckets(_ buckets: [UsageBucket]) -> [UsageBucket] {
        let preferred = ["5h", "weekly"].compactMap { id in buckets.first { $0.id == id } }
        if !preferred.isEmpty {
            return preferred
        }
        return buckets
    }

    /// トップバーの行頭に出す短縮ラベル。5時間→"5h"、週次→"7d"、それ以外は元のラベル。
    static func topBarShortLabel(for bucket: UsageBucket) -> String {
        switch bucket.id {
        case "5h": "5h"
        case "weekly": "7d"
        default: bucket.label
        }
    }

    /// 使用量に応じて緑→黄→赤へ段階変化（statusline の rate_color を移植）。
    static func usageColor(for usedPercent: Double) -> Color {
        let p = max(0, min(100, usedPercent))
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color {
            Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1)
        }
        switch p {
        case ..<40:
            return rgb(90, 200, 130)
        case ..<65:
            let t = (p - 40) / 25
            return rgb(90 + t * 150, 200 - t * 10, 130 - t * 50)
        case ..<85:
            let t = (p - 65) / 20
            return rgb(240, 190 - t * 110, 80 - t * 30)
        default:
            let t = min((p - 85) / 15, 1)
            return rgb(240, max(50, 80 - t * 30), 55)
        }
    }

    // MARK: - リセット残り時間

    /// リセット残りが「わずか」と判定する閾値（秒）。5時間枠は残り1時間、週次は残り1日。
    private static let urgentResetThresholds: [String: TimeInterval] = [
        "5h": 3600,
        "weekly": 86_400,
    ]

    /// リセットが残りわずか（5h≤1時間 / 週次≤1日）のときの警告色。
    /// 高使用率時の赤（usageColor の最終段 rgb(240,50,55)）と統一する。
    static let urgentResetColor = Color(.sRGB, red: 240 / 255, green: 50 / 255, blue: 55 / 255, opacity: 1)

    /// このバケットのリセットが残りわずかか。閾値はバケット種別ごと（5h:1時間 / weekly:1日）。
    /// resetsAt を持たない、または閾値定義のないバケット（Cursor 等）は常に false。
    static func isResetUrgent(for bucket: UsageBucket, now: Date) -> Bool {
        guard let resetsAt = bucket.resetsAt,
              let threshold = urgentResetThresholds[bucket.id] else { return false }
        return resetsAt.timeIntervalSince(now) <= threshold
    }

    /// 残り時間を "3h50m" / "45m"（1日以上は "5d3h"）形式に整形する。負値は 0 に丸める。
    static func remainingTimeText(until resetsAt: Date, now: Date) -> String {
        let totalMinutes = Int(max(0, resetsAt.timeIntervalSince(now)) / 60)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days > 0 { return "\(days)d\(hours)h" }
        if hours > 0 { return "\(hours)h\(minutes)m" }
        return "\(minutes)m"
    }

    private static let absoluteResetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// リセット絶対時刻を "MM/dd HH:mm"（例 "06/14 15:30"）で整形する。
    static func absoluteResetText(_ date: Date) -> String {
        absoluteResetFormatter.string(from: date)
    }

    /// サイドバーのリセット表示テキストと、それを赤で出すか。
    struct ResetDisplay: Equatable {
        let text: String
        let isUrgent: Bool
    }

    /// サイドバーのバケット行に出すリセット表示を返す。resetsAt が無ければ nil。
    /// - 5h: 常に残り時間（例 "3h50m"）。残り1時間以下で urgent（赤）。
    /// - weekly: 残り1日超は絶対時刻（例 "06/14 15:30"）、1日以下は残り時間（例 "20h30m"）で urgent（赤）。
    /// - その他（resetsAt を持つ Cursor 等）: 絶対時刻のみ。urgent なし。
    static func sidebarResetDisplay(for bucket: UsageBucket, now: Date) -> ResetDisplay? {
        guard let resetsAt = bucket.resetsAt else { return nil }
        let urgent = isResetUrgent(for: bucket, now: now)
        let usesRemaining: Bool
        switch bucket.id {
        case "5h": usesRemaining = true
        case "weekly": usesRemaining = urgent
        default: usesRemaining = false
        }
        let text = usesRemaining
            ? remainingTimeText(until: resetsAt, now: now)
            : absoluteResetText(resetsAt)
        return ResetDisplay(text: text, isUrgent: urgent)
    }
}
