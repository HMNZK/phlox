import Foundation
import AgentDomain
import ChatRenderKit

/// 実行中ターンの transcript から Thinking recap 文字列を導出する（純粋関数・task-3）。
public enum ChatRecap {
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
    static func derive(items: [ChatItem]) -> String {
        let commands = items.map { item -> String? in
            guard case .commandExecution(_, let command, _, _) = item else {
                return nil
            }
            return command
        }
        return ChatCommandGroupTitle.derive(commands: commands, itemCount: items.count)
    }
}
