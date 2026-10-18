import Foundation
import PhloxCore

enum SessionDetailTranscriptPresentation {
    static let commandOutputLineLimit = 20

    struct CommandOutput: Equatable {
        let displayed: String
        let hiddenLineCount: Int

        var isTruncated: Bool { hiddenLineCount > 0 }
    }

    enum SubAgentStatus: Equatable {
        case running
        case completed
        case unknown

        var label: String {
            switch self {
            case .running: "実行中"
            case .completed: "完了"
            case .unknown: "状態不明"
            }
        }
    }

    struct SubAgent: Equatable {
        let taskName: String
        let status: SubAgentStatus
    }

    enum SettledQuestionDetail: Equatable {
        case option(label: String, description: String?)
        case input(String)
        case expired
    }

    struct SettledQuestion: Equatable {
        let statusLabel: String
        let isAnswered: Bool
    }

    static func messagesForTranscript(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages.filter { message in
            if case .userQuestion(_, _, _, _, .pending) = message { return false }
            return true
        }
    }

    static func visibleTranscriptRows(_ messages: [ChatMessage]) -> [ChatMessage] {
        messages
    }

    static func latestTurnCostID(in messages: [ChatMessage]) -> String? {
        messages.last(where: { if case .turnCost = $0 { return true }; return false })?.id
    }

    static func settledQuestion(state: UserQuestionState) -> SettledQuestion? {
        guard state != .pending else { return nil }
        return SettledQuestion(
            statusLabel: state == .answered ? "回答済み" : "期限切れ",
            isAnswered: state == .answered
        )
    }

    static func settledQuestionDetails(
        for question: UserQuestionItem,
        state: UserQuestionState,
        answers: [String: [String]]?
    ) -> [SettledQuestionDetail] {
        if state == .expired { return [.expired] }
        return (answers?[question.question] ?? []).map { answer in
            if let option = question.options.first(where: { $0.label == answer }) {
                return .option(label: answer, description: option.description)
            }
            return .input(answer)
        }
    }

    static func userText(_ text: String, hasAttachments: Bool) -> String {
        guard hasAttachments else { return text }
        let pattern = #"\[Image #\d+\]"#
        var result = text
        while true {
            let source = result as NSString
            let match = source.range(of: pattern, options: .regularExpression)
            guard match.location != NSNotFound else { break }
            result = source.replacingCharacters(in: match, with: "")
        }
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func commandOutput(_ output: String, expanded: Bool) -> CommandOutput {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false)
        let visible = expanded ? lines.count : min(lines.count, commandOutputLineLimit)
        return CommandOutput(
            displayed: expanded ? output : lines.prefix(commandOutputLineLimit).joined(separator: "\n"),
            hiddenLineCount: expanded ? 0 : max(0, lines.count - visible)
        )
    }

    static func exitCode(in output: String) -> Int? {
        for line in output.split(separator: "\n", omittingEmptySubsequences: true)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .filter({ !$0.isEmpty })
            .prefix(3) {
            guard line.hasPrefix("Exit code ") else { continue }
            let digits = line.dropFirst("Exit code ".count).prefix(while: \.isNumber)
            return Int(digits)
        }
        return nil
    }

    static func subAgent(from text: String) -> SubAgent {
        let prefix = "Sub-agent "
        guard text.hasPrefix(prefix) else {
            return SubAgent(taskName: text.isEmpty ? "タスク名不明" : text, status: .unknown)
        }
        let payload = text.dropFirst(prefix.count)
        guard let firstSpace = payload.firstIndex(of: " ") else {
            return SubAgent(taskName: "タスク名不明", status: .unknown)
        }
        let statusAndTask = payload[payload.index(after: firstSpace)...]
        guard let colon = statusAndTask.firstIndex(of: ":") else {
            let status = String(statusAndTask).trimmingCharacters(in: .whitespacesAndNewlines)
            return SubAgent(taskName: "タスク名不明", status: statusValue(status))
        }
        let status = String(statusAndTask[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
        let taskName = String(statusAndTask[statusAndTask.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SubAgent(
            taskName: taskName.isEmpty ? "タスク名不明" : taskName,
            status: statusValue(status)
        )
    }

    static func turnUsageLine(costUSD: Double?, usage: TurnUsage?) -> String? {
        var parts: [String] = []
        if let costUSD {
            parts.append(formatCost(costUSD))
        } else if let usageCost = usage?.costUSD {
            parts.append(formatCost(usageCost))
        }
        if let used = usage?.contextUsedTokens, let window = usage?.contextWindowTokens, window > 0 {
            let percent = Int((Double(used) / Double(window) * 100).rounded())
            parts.append("コンテキスト \(percent)%")
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func statusValue(_ rawValue: String) -> SubAgentStatus {
        switch rawValue {
        case "running": .running
        case "completed": .completed
        default: .unknown
        }
    }

    private static func formatCost(_ costUSD: Double) -> String {
        String(format: costUSD >= 0.01 || costUSD == 0 ? "$%.2f" : "$%.4f", costUSD)
    }
}
