import AgentDomain
import DesignSystem
import SwiftUI

enum UsageDisplay {
    /// サイドバーに表示する CLI を AgentKind.allCases の順で返す。
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

    /// 「残りわずか」として注意色で示す残量の境目（%）。
    static let lowRemainingThreshold: Double = 20

    /// 残量がしきい値を下回るか。
    static func isLowRemaining(usedPercent: Double) -> Bool {
        100 - max(0, min(100, usedPercent)) < lowRemainingThreshold
    }

    /// 下部バーに出す1ハーネス分。取得できない場合は buckets が nil。
    struct BottomBarGroup: Identifiable {
        let kind: AgentKind
        let buckets: [UsageBucket]?

        var id: AgentKind { kind }
    }

    enum BottomBarStage {
        case full, compact, percentageOnly
    }

    static func bottomBarStage(forWidth width: CGFloat) -> BottomBarStage {
        width >= 1_100 ? .full : width >= 600 ? .compact : .percentageOnly
    }

    /// 下部バーのハーネスと全バケットを AgentKind 順で返す。
    static func bottomBarGroups(
        usages: [AgentKind: CLIUsage]
    ) -> [BottomBarGroup] {
        AgentKind.allCases.compactMap { kind -> BottomBarGroup? in
            guard let usage = usages[kind] else {
                return BottomBarGroup(kind: kind, buckets: nil)
            }
            switch usage.state {
            case .unavailable:
                return BottomBarGroup(kind: kind, buckets: nil)
            case .ok(let buckets):
                return buckets.isEmpty ? nil : BottomBarGroup(kind: kind, buckets: buckets)
            }
        }
    }

    static func bottomBarUnavailableText(locale: Locale, bundle: Bundle = .main) -> String {
        AppLocalizedString.string("取得できません", locale: locale, bundle: bundle)
    }

    static func bottomBarBucketText(
        _ bucket: UsageBucket,
        showsLabel: Bool,
        showsReset: Bool,
        now: Date,
        locale: Locale
    ) -> String {
        let remaining = Int(round(100 - max(0, min(100, bucket.usedPercent))))
        var text = showsLabel ? "\(bucket.label) \(remaining)%" : "\(remaining)%"
        if showsReset, let reset = bottomBarResetText(for: bucket, now: now, locale: locale) {
            let isEnglish = locale.language.languageCode?.identifier == "en"
            text += isEnglish ? " (\(reset))" : "（\(reset)）"
        }
        return text
    }

    static func bottomBarResetText(for bucket: UsageBucket, now: Date, locale: Locale) -> String? {
        guard let resetsAt = bucket.resetsAt else { return nil }
        let isEnglish = locale.language.languageCode?.identifier == "en"
        let minutes = max(1, Int(ceil(resetsAt.timeIntervalSince(now) / 60)))
        if bucket.id == "weekly", minutes > 24 * 60 {
            let days = Int(ceil(Double(minutes) / (24 * 60)))
            return isEnglish ? "in \(days)d" : "\(days)日後"
        }
        if minutes >= 60 {
            let hours = Int(ceil(Double(minutes) / 60))
            return isEnglish ? "in \(hours)h" : "\(hours)時間後"
        }
        return isEnglish ? "in \(minutes)m" : "\(minutes)分後"
    }

    static func bottomBarAccessibilityLabel(groups: [BottomBarGroup], now: Date, locale: Locale, bundle: Bundle = .main) -> String {
        let details = groups.map { group -> String in
            guard let buckets = group.buckets else {
                return "\(group.kind.displayName)、\(bottomBarUnavailableText(locale: locale, bundle: bundle))"
            }
            let values = buckets.map { bucket -> String in
                let remaining = Int(round(100 - max(0, min(100, bucket.usedPercent))))
                var value = "\(bucket.label) \(String(format: AppLocalizedString.string("残り %lld%%", locale: locale, bundle: bundle), remaining))"
                if isLowRemaining(usedPercent: bucket.usedPercent) {
                    value += "、\(AppLocalizedString.string("残りわずか", locale: locale, bundle: bundle))"
                }
                if let reset = sidebarResetDisplay(for: bucket, now: now) {
                    value += "、\(String(format: AppLocalizedString.string("リセット %@", locale: locale, bundle: bundle), reset.text))"
                }
                return value
            }
            return "\(group.kind.displayName)、\(values.joined(separator: AppLocalizedString.string("、", locale: locale, bundle: bundle)))"
        }
        let joined = details.joined(separator: AppLocalizedString.string("、", locale: locale, bundle: bundle))
        return String(format: AppLocalizedString.string("使用量: %@。クリックで詳細", locale: locale, bundle: bundle), joined)
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

    // MARK: - 残量文字列（要約・詳細の唯一の生成点）

    /// 残量文字列「残りN%」を返す。usedPercent は 0…100 にクランプしてから 100 から引き、Int/round する。
    static func remainingPercentText(usedPercent: Double) -> String {
        let clamped = max(0, min(100, usedPercent))
        return "残り\(Int(round(100 - clamped)))%"
    }

}
