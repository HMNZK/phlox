import Foundation

/// アゴラ討論の設定（task-6 契約・AcceptanceAgoraSettingsTests が凍結）。
/// @AppStorage キーの正本。テストは suite 注入で共有 UserDefaults に触れない（L-34）。
/// セマンティクスの正本は tasks/task-6.md。
public struct AgoraDiscussionSettings {
    public static let maxUtterancesKey = "phlox.agora.maxUtterances"
    public static let maxAgentsKey = "phlox.agora.maxAgents"
    public static let turnTimeoutSecondsKey = "phlox.agora.turnTimeoutSeconds"
    public static let schedulerKey = "phlox.agora.scheduler"

    private static let defaultMaxUtterances = 30
    private static let defaultMaxAgents = 5
    private static let defaultTurnTimeoutSeconds = 180
    private static let defaultConsecutiveSpeakLimit = 2
    private static let defaultStallPassRounds = 2
    private static let defaultWarningRemaining = 5
    private static let defaultScheduler = AgoraSchedulerKind.freeSpeech

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 保存値（不正値は既定へクランプ）から討論 config を組み立てる。
    public var config: AgoraDiscussionConfig {
        let maxUtterances = positiveInt(forKey: Self.maxUtterancesKey, default: Self.defaultMaxUtterances)
        let maxAgents = positiveInt(forKey: Self.maxAgentsKey, default: Self.defaultMaxAgents)
        let turnTimeoutSeconds = TimeInterval(
            positiveInt(forKey: Self.turnTimeoutSecondsKey, default: Self.defaultTurnTimeoutSeconds)
        )
        let scheduler = defaults.string(forKey: Self.schedulerKey)
            .flatMap { AgoraSchedulerKind(rawValue: $0) }
            ?? Self.defaultScheduler

        return AgoraDiscussionConfig(
            maxUtterances: maxUtterances,
            maxAgents: maxAgents,
            turnTimeoutSeconds: turnTimeoutSeconds,
            consecutiveSpeakLimit: Self.defaultConsecutiveSpeakLimit,
            stallPassRounds: Self.defaultStallPassRounds,
            warningRemaining: Self.defaultWarningRemaining,
            scheduler: scheduler
        )
    }

    private func positiveInt(forKey key: String, default defaultValue: Int) -> Int {
        let stored = defaults.integer(forKey: key)
        return stored > 0 ? stored : defaultValue
    }
}
