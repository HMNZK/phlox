import Foundation
import AgentDomain
import PhloxCore

public struct UsageRingBucket: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let ringLabel: String?
    public let value: UsageBucket?

    public var remainingPercent: Int? {
        value.map { UsageRingPresentation.remainingPercent(usedPercent: $0.usedPercent) }
    }

    public var remainingFraction: Double? {
        value.map { UsageRingPresentation.remainingFraction(usedPercent: $0.usedPercent) }
    }

    public var isLow: Bool {
        guard let value else { return false }
        return UsageRingPresentation.isLowRemaining(usedPercent: value.usedPercent)
    }
}

public struct UsageRingAgent: Identifiable, Equatable, Sendable {
    public let kind: AgentKind
    public let isUnavailable: Bool
    public let buckets: [UsageRingBucket]

    public var id: AgentKind { kind }
}

/// 使用量リング、吹き出し、VoiceOver で共有する値の規則。
public enum UsageRingPresentation {
    public static let minimumRingFraction = 0.02
    public static let lowRemainingThreshold = 20.0
    public static let popoverColumnHeaders = ["枠", "残り", "リセット"]
    public static let unavailableText = "取得できません"
    public static let rowAccessibilityHint = "使用量の詳細を表示"

    private struct BucketSlot {
        let id: String
        let label: String
        let ringLabel: String?
    }

    public static func agents(from usages: [CLIUsage]) -> [UsageRingAgent] {
        var byKind: [AgentKind: CLIUsage] = [:]
        for usage in usages where byKind[usage.kind] == nil {
            byKind[usage.kind] = usage
        }

        return [AgentKind.claudeCode, .codex, .cursor].compactMap { kind in
            guard let usage = byKind[kind], usage.state == .ok else { return nil }
            let buckets = slots(for: kind).compactMap { slot -> UsageRingBucket? in
                guard let value = usage.buckets.first(where: { $0.id == slot.id }) else { return nil }
                return UsageRingBucket(id: slot.id, label: value.label, ringLabel: slot.ringLabel, value: value)
            }
            guard !buckets.isEmpty else { return nil }
            return UsageRingAgent(kind: kind, isUnavailable: false, buckets: buckets)
        }
    }

    public static func remainingPercent(usedPercent: Double) -> Int {
        Int(remainingValue(usedPercent: usedPercent).rounded())
    }

    public static func remainingFraction(usedPercent: Double) -> Double {
        max(minimumRingFraction, remainingValue(usedPercent: usedPercent) / 100)
    }

    public static func isLowRemaining(usedPercent: Double) -> Bool {
        remainingValue(usedPercent: usedPercent) < lowRemainingThreshold
    }

    public static func valueText(for bucket: UsageRingBucket) -> String {
        guard let remaining = bucket.remainingPercent else { return "値なし" }
        return "残り \(remaining)%"
    }

    public static func resetText(
        for bucket: UsageRingBucket,
        agent: AgentKind,
        now: Date,
        timeZone: TimeZone = .current
    ) -> String? {
        guard agent != .cursor,
              let value = bucket.value,
              let reset = value.resetsAt else { return nil }
        if bucket.id == "5h" {
            let minutes = Int(max(0, reset.timeIntervalSince(now)) / 60)
            return String(format: "%02d:%02d", minutes / 60, minutes % 60)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: reset)
    }

    public static func statusText(
        isRefreshing: Bool,
        isStale: Bool,
        asOf: Date?,
        timeZone: TimeZone = .current
    ) -> String? {
        if isRefreshing { return "更新中…" }
        guard isStale, let asOf else { return nil }
        return "\(time(asOf, format: "HH:mm", timeZone: timeZone)) 時点"
    }

    public static func staleNotice(asOf: Date, timeZone: TimeZone = .current) -> String {
        "\(time(asOf, format: "HH:mm", timeZone: timeZone)) 時点の値です。更新できませんでした。一覧を引っ張ると取り直します"
    }

    public static func accessibilityLabel(
        agents: [UsageRingAgent],
        isRefreshing: Bool,
        isStale: Bool,
        asOf: Date?,
        timeZone: TimeZone = .current
    ) -> String {
        var prefix = ""
        if isRefreshing {
            prefix = "更新中。"
        } else if isStale, let asOf {
            prefix = "\(time(asOf, format: "H時mm分", timeZone: timeZone))時点の値。更新できませんでした。"
        }

        let details = agents.map { agent -> String in
            let name = accessibilityName(for: agent.kind)
            guard !agent.isUnavailable else { return "\(name) \(unavailableText)" }
            let buckets = agent.buckets.map { bucket -> String in
                guard let remaining = bucket.remainingPercent else { return "\(bucket.label) 値なし" }
                let caution = bucket.isLow ? "、残りわずか" : ""
                return "\(bucket.label) 残り \(remaining)%\(caution)"
            }
            return "\(name) \(buckets.joined(separator: "、"))"
        }
        return "\(prefix)使用量。\(details.joined(separator: "。"))。"
    }

    private static func remainingValue(usedPercent: Double) -> Double {
        100 - min(100, max(0, usedPercent))
    }

    private static func slots(for kind: AgentKind) -> [BucketSlot] {
        switch kind {
        case .claudeCode:
            [BucketSlot(id: "5h", label: "5時間", ringLabel: "5h"),
             BucketSlot(id: "weekly", label: "週次", ringLabel: "7d")]
        case .codex:
            [BucketSlot(id: "5h", label: "5時間", ringLabel: nil),
             BucketSlot(id: "weekly", label: "週次", ringLabel: nil)]
        case .cursor:
            [BucketSlot(id: "auto", label: "Auto", ringLabel: nil),
             BucketSlot(id: "api", label: "API", ringLabel: nil)]
        @unknown default:
            []
        }
    }

    private static func accessibilityName(for kind: AgentKind) -> String {
        switch kind {
        case .claudeCode: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        @unknown default: kind.displayName
        }
    }

    private static func time(_ date: Date, format: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
