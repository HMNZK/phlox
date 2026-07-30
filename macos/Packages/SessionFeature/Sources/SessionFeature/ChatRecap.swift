import Foundation
import AgentDomain

/// 実行中ターンの transcript から Thinking recap 文字列を導出する（純粋関数・task-3）。
public enum ChatRecap {
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

    /// transcript とセッション状態から Thinking インジケータの活動状態を導出する（純粋関数）。
    /// - 承認・回答待ちなら `.waiting`
    /// - それ以外は、最後のユーザー入力以降で「最後に現れた」項目種別で決める
    /// - 該当が無ければ `.thinking`
    public static func deriveActivityState(
        transcript: [ChatItem],
        status: SessionStatus
    ) -> AgentActivityState {
        if let waiting = AgentActivityClassifier.waitingState(for: status) { return waiting }

        let scoped: ArraySlice<ChatItem>
        if let lastUserIndex = transcript.lastIndex(where: {
            if case .userMessage = $0 { return true }
            return false
        }) {
            scoped = transcript[(lastUserIndex + 1)...]
        } else {
            scoped = transcript[...]
        }

        var state = AgentActivityState.thinking
        for item in scoped {
            switch item {
            case .reasoning:
                state = .thinking
            case .commandExecution(_, let command, _, _):
                state = AgentActivityClassifier.state(forCommand: command)
            case .fileChange:
                state = .editing
            case .agentMessage:
                state = .writing
            default:
                break
            }
        }
        return state
    }
}

/// ツール実行グループのヘッダタイトルを導出する純粋関数。
enum CommandGroupTitle {
    static func derive(items: [ChatItem], isRunning: Bool, liveRecap: String?) -> String {
        if isRunning, let liveRecap {
            return liveRecap
        }

        guard let item = items.last(where: { item in
            guard case .commandExecution(_, let command, _, _) = item,
                  let command,
                  !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return true
        }), case let .commandExecution(_, command?, _, _) = item else {
            return "ツール実行 ×\(items.count)"
        }

        let normalizedCommand = command
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let label: String
        switch RecapActivity.fromCommand(command) {
        case .reading:
            label = "\(normalizedCommand) を読み込み"
        case .running:
            label = "\(normalizedCommand) を実行"
        case .editing:
            label = "\(normalizedCommand) を編集"
        }
        return ThinkingRecap.clamp(label)
    }
}
