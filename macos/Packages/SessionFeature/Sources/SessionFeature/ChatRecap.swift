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

        for item in transcript.reversed() {
            switch item {
            case .userMessage, .reasoning:
                return .thinking
            case .commandExecution(_, let command, _, _):
                return AgentActivityClassifier.state(forCommand: command)
            case .fileChange:
                return .editing
            case .agentMessage:
                return .writing
            default:
                break
            }
        }
        return .thinking
    }

    /// 思考中インジケータの下段に出す「いま何をしているか」（04 A1・B1）。最後のユーザー入力以降の
    /// コマンド・ファイル変更を優先し、無ければ推論の見出しを使う。規則は `ThinkingRecap.summary` と同じ
    /// （開始 5 秒未満は出さない）。文言は表示言語で組むため、活動そのものを返す。
    public static func summary(transcript: [ChatItem], elapsed: TimeInterval) -> Summary? {
        guard elapsed >= ThinkingRecap.defaultThreshold else { return nil }
        var reasoningText: String?
        for item in transcript.reversed() {
            switch item {
            case .userMessage:
                return ThinkingRecap.headline(from: reasoningText).map(Summary.headline)
            case .commandExecution(_, let command, _, _):
                return .activity(.fromCommand(command))
            case .fileChange(_, let changes, _):
                if let path = changes.last?.path {
                    return .activity(.editing((path as NSString).lastPathComponent))
                }
            case .reasoning(_, let text, _) where reasoningText == nil:
                reasoningText = text
            default:
                break
            }
        }
        return ThinkingRecap.headline(from: reasoningText).map(Summary.headline)
    }

    public enum Summary: Equatable {
        case activity(RecapActivity)
        case headline(String)
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
