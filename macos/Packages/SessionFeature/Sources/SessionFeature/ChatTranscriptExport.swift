import Foundation
import StructuredChatKit

/// 会話のエクスポート設定。`/export` 相当の機能で使う。
public struct ChatTranscriptExportOptions: Sendable, Equatable {
    /// 推論（Reasoning）を含めるか。既定は含めない（長くなりがちなため）。
    public var includesReasoning: Bool
    /// コマンド実行の出力を含めるか。
    public var includesCommandOutput: Bool
    /// 各発言に時刻を添えるか。
    public var includesTimestamps: Bool

    public init(
        includesReasoning: Bool = false,
        includesCommandOutput: Bool = true,
        includesTimestamps: Bool = true
    ) {
        self.includesReasoning = includesReasoning
        self.includesCommandOutput = includesCommandOutput
        self.includesTimestamps = includesTimestamps
    }
}

/// エクスポートの見出しに載せるセッション情報。
public struct ChatTranscriptExportMetadata: Sendable, Equatable {
    public var sessionTitle: String
    public var agentName: String
    public var projectName: String?
    public var workingDirectory: String?
    public var exportedAt: Date

    public init(
        sessionTitle: String,
        agentName: String,
        projectName: String? = nil,
        workingDirectory: String? = nil,
        exportedAt: Date
    ) {
        self.sessionTitle = sessionTitle
        self.agentName = agentName
        self.projectName = projectName
        self.workingDirectory = workingDirectory
        self.exportedAt = exportedAt
    }
}

/// transcript を Markdown 1枚へ落とす純関数群。
///
/// `/export` は Claude Code の対話 TUI 専用でセッションからは使えないため、
/// Phlox は自分が持っている transcript から同じものを作る。
public enum ChatTranscriptExporter {
    public static func markdown(
        items: [ChatItem],
        metadata: ChatTranscriptExportMetadata,
        options: ChatTranscriptExportOptions = ChatTranscriptExportOptions()
    ) -> String {
        var lines: [String] = []
        lines.append("# \(metadata.sessionTitle)")
        lines.append("")
        lines.append("- エージェント: \(metadata.agentName)")
        if let projectName = metadata.projectName {
            lines.append("- プロジェクト: \(projectName)")
        }
        if let workingDirectory = metadata.workingDirectory {
            lines.append("- 作業ディレクトリ: `\(workingDirectory)`")
        }
        lines.append("- 書き出し日時: \(absoluteFormatter.string(from: metadata.exportedAt))")
        lines.append("")

        for item in items {
            guard let block = block(for: item, options: options) else { continue }
            lines.append("---")
            lines.append("")
            lines.append(contentsOf: block)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// 保存ダイアログの既定ファイル名。パスに使えない文字は `-` に潰す。
    public static func suggestedFileName(
        sessionTitle: String,
        exportedAt: Date
    ) -> String {
        let sanitized = sessionTitle
            .components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = sanitized.isEmpty ? "chat" : sanitized
        return "\(base)-\(fileNameFormatter.string(from: exportedAt)).md"
    }

    // MARK: - 各項目

    private static func block(
        for item: ChatItem,
        options: ChatTranscriptExportOptions
    ) -> [String]? {
        switch item {
        case .userMessage(_, let text, let timestamp, let attachments):
            var lines = [heading("👤 ユーザー", timestamp: timestamp, options: options), "", text]
            if !attachments.isEmpty {
                lines.append("")
                let names = attachments.map { $0.filename ?? $0.mediaType }
                lines.append("添付: \(names.joined(separator: ", "))")
            }
            return lines

        case .agentMessage(_, let text, let timestamp):
            return [heading("🤖 アシスタント", timestamp: timestamp, options: options), "", text]

        case .reasoning(_, let text, let timestamp):
            guard options.includesReasoning else { return nil }
            let quoted = text.split(separator: "\n", omittingEmptySubsequences: false).map { "> \($0)" }
            return [heading("💭 思考", timestamp: timestamp, options: options), ""] + quoted

        case .commandExecution(_, let command, let output, let timestamp):
            var lines = [heading("⌘ コマンド実行", timestamp: timestamp, options: options), ""]
            if let command, !command.isEmpty {
                lines += ["```sh", command, "```"]
            }
            if options.includesCommandOutput, !output.isEmpty {
                lines += ["", "```", output, "```"]
            }
            return lines

        case .fileChange(_, let changes, let timestamp):
            var lines = [heading("📝 ファイル変更", timestamp: timestamp, options: options), ""]
            for change in changes {
                lines.append("- `\(change.path)`\(change.kind.map { "（\($0)）" } ?? "")")
            }
            return lines

        case .error(_, let message, let timestamp):
            return [heading("⚠️ エラー", timestamp: timestamp, options: options), "", "> \(message)"]

        case .subAgentMarker(_, let subagentType, let description, let status):
            return ["## 🧩 サブエージェント: \(subagentType)（\(statusLabel(status))）", "", description]

        case .turnCost(_, let costUSD, let timestamp):
            return [heading("💲 コスト", timestamp: timestamp, options: options), "", String(format: "$ %.4f", costUSD)]

        case .userQuestion(_, _, let questions, let answers, let state, let timestamp):
            var lines = [heading("❓ 確認", timestamp: timestamp, options: options), ""]
            for question in questions {
                lines.append("**\(question.header)** \(question.question)")
                for option in question.options {
                    lines.append("- \(option.label)\(option.description.map { " — \($0)" } ?? "")")
                }
                if let selected = answers?[question.question], !selected.isEmpty {
                    lines.append("")
                    lines.append("→ 回答: \(selected.joined(separator: " / "))")
                }
                lines.append("")
            }
            if state != .answered {
                lines.append("（\(state == .pending ? "未回答" : "失効")）")
            }
            return lines

        case .taskList(_, let tasks, let timestamp):
            var lines = [heading("☑︎ タスク", timestamp: timestamp, options: options), ""]
            for task in tasks {
                lines.append("- [\(task.status == .completed ? "x" : " ")] \(task.title)\(task.status == .inProgress ? "（作業中）" : "")")
            }
            return lines
        }
    }

    private static func heading(
        _ title: String,
        timestamp: Date,
        options: ChatTranscriptExportOptions
    ) -> String {
        guard options.includesTimestamps else { return "## \(title)" }
        return "## \(title) — \(timeFormatter.string(from: timestamp))"
    }

    private static func statusLabel(_ status: SubAgentStatus) -> String {
        switch status {
        case .running: return "実行中"
        case .completed: return "完了"
        case .failed: return "失敗"
        }
    }

    // MARK: - 書式

    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let fileNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmm"
        return formatter
    }()
}
