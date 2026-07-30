import Foundation
import PhloxCore

/// 実行中ターンの ChatMessage 列から Thinking recap 文字列を導出する（純粋関数・task-4）。
enum ChatRecapIOS {
    /// messages 表示順（古い→新しい）から recap を導出する。
    /// - gate: `status != .running` → nil
    /// - scope: 最後の `.user` の次以降（無ければ全体）
    /// - 委譲: `ThinkingRecap.summary`（elapsed / threshold は引数のみ。Date を内部生成しない）
    static func derive(
        messages: [ChatMessage],
        status: SessionStatus,
        elapsed: TimeInterval,
        threshold: TimeInterval = ThinkingRecap.defaultThreshold
    ) -> String? {
        guard status == .running else { return nil }

        let scoped: ArraySlice<ChatMessage>
        if let lastUserIndex = messages.lastIndex(where: {
            if case .user = $0 { return true }
            return false
        }) {
            scoped = messages[(lastUserIndex + 1)...]
        } else {
            scoped = messages[...]
        }

        var reasoningText: String?
        var activities: [RecapActivity] = []

        for message in scoped {
            switch message {
            case .reasoning(_, let text):
                reasoningText = text
            case .command(_, let command, _):
                activities.append(RecapActivity.fromCommand(command))
            case .fileChange(_, let changes):
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
            elapsed: elapsed,
            threshold: threshold
        )
    }

    /// messages とセッション状態から Thinking インジケータの活動状態を導出する（純粋関数）。
    /// macOS の `ChatRecap.deriveActivityState` と同一の規則。
    static func deriveActivityState(
        messages: [ChatMessage],
        status: SessionStatus
    ) -> AgentActivityState {
        if let waiting = AgentActivityClassifier.waitingState(for: status) { return waiting }

        let scoped: ArraySlice<ChatMessage>
        if let lastUserIndex = messages.lastIndex(where: {
            if case .user = $0 { return true }
            return false
        }) {
            scoped = messages[(lastUserIndex + 1)...]
        } else {
            scoped = messages[...]
        }

        var state = AgentActivityState.thinking
        for message in scoped {
            switch message {
            case .reasoning:
                state = .thinking
            case .command(_, let command, _):
                state = AgentActivityClassifier.state(forCommand: command)
            case .fileChange:
                state = .editing
            case .agent:
                state = .writing
            default:
                break
            }
        }
        return state
    }
}
