import Foundation

/// 実行中エージェントが「いま何をしているか」の 6 状態（表示用の粒度）。
/// transcript の直近の項目とセッション状態から導出する（ThinkingRecap と同じく純粋関数）。
public enum AgentActivityState: String, CaseIterable, Sendable {
    /// 推論中（ツールを使っていない）。
    case thinking
    /// 読み取り系ツール（Read / Grep / Glob / WebSearch など）。
    case searching
    /// コマンド実行・サブエージェント。
    case running
    /// ファイル変更（Edit / Write など）。
    case editing
    /// 回答テキストを書き出している。
    case writing
    /// ユーザーの承認・回答待ち。
    case waiting
}

public enum AgentActivityClassifier {
    /// 読み取りとみなすツール名・コマンド名（先頭トークンの basename で判定）。
    /// エージェント側のツール名（Claude / Codex / Cursor の表示名）と素のシェルコマンドの両方を含む。
    private static let readNames: Set<String> = [
        // エージェントのツール名
        "Read", "Grep", "Glob", "Search", "WebSearch", "WebFetch", "NotebookRead", "LS", "List",
        // シェルコマンド
        "cat", "less", "head", "tail", "grep", "rg", "find", "ls",
        "bat", "fd", "cd", "pwd", "echo", "which", "stat", "wc",
    ]

    /// コマンド文字列（先頭にツール名が載る）を searching / running へ分類する。
    public static func state(forCommand command: String?) -> AgentActivityState {
        guard let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .running
        }
        let firstToken = command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return readNames.contains(basename(firstToken)) ? .searching : .running
    }

    /// セッション状態がユーザーの応答待ちなら .waiting。それ以外は nil（transcript 側で決める）。
    public static func waitingState(for status: SessionStatus) -> AgentActivityState? {
        switch status {
        case .awaitingApproval, .awaitingUserQuestion:
            return .waiting
        case .starting, .idle, .running, .completed, .error:
            return nil
        }
    }

    private static func basename(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }
}
