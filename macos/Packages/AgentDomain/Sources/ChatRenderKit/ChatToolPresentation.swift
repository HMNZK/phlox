import Foundation
import AgentDomain

public enum ChatCommandToolLabel {
    private static let knownTools: Set<String> = [
        "Read", "Write", "Edit", "Glob", "Grep", "LS", "Task", "Skill", "WebFetch", "WebSearch", "NotebookEdit", "TodoWrite",
    ]

    /// 先頭トークンが既知ツール名と完全一致すれば (ツール名, 残り) を返す。
    public static func derive(command: String?) -> (label: String, body: String) {
        guard let command, !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ("Bash", "")
        }
        let parts = command.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard let first = parts.first, knownTools.contains(String(first)) else {
            return ("Bash", command)
        }
        let body = parts.dropFirst().first.map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        return (String(first), body)
    }
}

public struct ChatReasoningPresentation: Equatable, Sendable {
    public let headline: String
    public let trimmedText: String

    public init(text: String) {
        trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        headline = ThinkingRecap.headline(from: text) ?? "Reasoning"
    }

    public var usesDisclosure: Bool { trimmedText != headline }
}

public enum ChatCommandGroupTitle {
    /// 末尾から最初に見つかる非空コマンドを空白正規化し、60 字で切る。
    public static func derive(commands: [String?], itemCount: Int) -> String {
        guard let command = commands.reversed()
            .compactMap({ $0 })
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            return "ツール実行 ×\(itemCount)"
        }

        let normalizedCommand = command
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        return ThinkingRecap.clamp(normalizedCommand)
    }
}
