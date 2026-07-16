import Foundation

/// `claude --settings` に渡す hooks 設定 JSON（辞書）を生成する。
/// 6 つの hook イベントすべてに dispatcher コマンドを割り当てる。
public enum ClaudeSettingsGenerator {
    private static let preToolUseTimeoutSeconds = 600

    public static func settings(
        defaultMode: String,
        dispatcher: String,
        statusLineCommand: String
    ) -> [String: Any] {
        let dispatcherQuoted = ShellQuoting.singleQuoted(dispatcher)
        return [
            "permissions": [
                "defaultMode": defaultMode,
            ],
            "statusLine": [
                "type": "command",
                "command": statusLineCommand,
            ],
            // dispatcher は単一引用符で囲む。`#filePath` 由来のビルド元パスがスペースを含む場合
            // （例: `.../Application Support/Phlox/workspace/...` の worktree）、未クォートだと
            // claude が `/bin/sh -c` 実行時にスペースで分割し「No such file or directory」で失敗するため。
            // ShellQuoting.singleQuoted でパス中のシングルクォートも安全にエスケープする（sh 注入対策）。
            "hooks": [
                "SessionStart": [["matcher": "", "hooks": [["type": "command", "command": "\(dispatcherQuoted) sessionStart"]]]],
                "Notification": [["matcher": "", "hooks": [["type": "command", "command": "\(dispatcherQuoted) notification"]]]],
                "Stop":         [["matcher": "", "hooks": [["type": "command", "command": "\(dispatcherQuoted) stop"]]]],
                "PreToolUse":   [["matcher": "", "hooks": [[
                    "type": "command",
                    "command": "\(dispatcherQuoted) preToolUse",
                    "timeout": preToolUseTimeoutSeconds,
                ]]]],
                "PostToolUse":  [["matcher": "", "hooks": [["type": "command", "command": "\(dispatcherQuoted) postToolUse"]]]],
                "UserPromptSubmit": [["matcher": "", "hooks": [["type": "command", "command": "\(dispatcherQuoted) userPromptSubmit"]]]],
            ]
        ]
    }
}
