import Foundation

/// Claude Code の tool_use（名前と input）を会話に出す 1 行へ（「Read /path」「ls -la」）。
/// ライブの経路（ClaudeAgentKit）と保存済みサブエージェント記録の読み込み（SessionFeature）で共有する。
public enum ClaudeToolCommand {
    public static func describe(toolName: String, input: [String: Any]) -> String {
        switch toolName {
        case "Bash":
            return input["command"] as? String ?? "Bash"
        case "Read":
            return ["Read", input["file_path"] as? String].compactMap { $0 }.joined(separator: " ")
        case "Glob":
            return ["Glob", input["pattern"] as? String].compactMap { $0 }.joined(separator: " ")
        case "Grep":
            let pattern = input["pattern"] as? String
            let path = input["path"] as? String
            return ["Grep", pattern, path].compactMap { $0 }.joined(separator: " ")
        case "LS":
            return ["LS", input["path"] as? String].compactMap { $0 }.joined(separator: " ")
        default:
            if input.isEmpty {
                return toolName
            }
            let inputText = (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
                .flatMap { String(data: $0, encoding: .utf8) } ?? String(describing: input)
            return "\(toolName) \(inputText)"
        }
    }
}
