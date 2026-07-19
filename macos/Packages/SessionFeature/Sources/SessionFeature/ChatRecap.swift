import Foundation
import AgentDomain

/// 実行中ターンの transcript から Thinking recap 文字列を導出する（純粋関数・task-3）。
enum ChatRecap {
    /// transcript 表示順（古い→新しい）から recap を導出する。
    /// - gate: `status != .running` または `turnStartedAt == nil` → nil
    /// - scope: 最後の `.userMessage` の次以降（無ければ全体）
    /// - 委譲: `ThinkingRecap.summary`
    static func derive(
        transcript: [ChatItem],
        status: SessionStatus,
        turnStartedAt: Date?,
        now: Date,
        threshold: TimeInterval = ThinkingRecap.defaultThreshold
    ) -> String? {
        guard status == .running, let turnStartedAt else { return nil }

        let scoped: ArraySlice<ChatItem>
        if let lastUserIndex = transcript.lastIndex(where: {
            if case .userMessage = $0 { return true }
            return false
        }) {
            scoped = transcript[(lastUserIndex + 1)...]
        } else {
            scoped = transcript[...]
        }

        var reasoningText: String?
        var activities: [RecapActivity] = []

        for item in scoped {
            switch item {
            case .reasoning(_, let text, _):
                reasoningText = text
            case .commandExecution(_, let command, _, _):
                activities.append(RecapActivity.fromCommand(command))
            case .fileChange(_, let changes, _):
                if let path = changes.first?.path {
                    activities.append(.editing(path))
                }
            default:
                break
            }
        }

        return ThinkingRecap.summary(
            reasoningText: reasoningText,
            recentActivity: activities,
            elapsed: now.timeIntervalSince(turnStartedAt),
            threshold: threshold
        )
    }
}
