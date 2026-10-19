import Foundation
import PhloxCore

struct ReplyApproval: Identifiable, Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case command
        case fileChange
        case permissions
        case tool

        var label: String {
            switch self {
            case .command: "コマンドの実行"
            case .fileChange: "ファイルの変更"
            case .permissions: "権限の変更"
            case .tool: "ツールの使用"
            }
        }
    }

    enum Source: Equatable, Sendable {
        case codex(approvalID: String)
        case claudeToolPermission(requestID: String, answerKey: String)
    }

    let id: String
    let source: Source
    let kind: Kind?
    let subject: String
    let explanation: String?
    let requestedAt: Date
    let toolName: String?
    let allowsSessionScope: Bool
    let diffFiles: [ChatFileChange]

    var kindLabel: String? { kind?.label }

    /// Mac と同じく、1 件だけのツール許可質問を承認カードへ移す。
    static func isClaudeToolPermissionQuestion(_ questions: [UserQuestionItem]) -> Bool {
        questions.count == 1 && questions.first?.isToolPermission == true
    }

    var compactTitle: String {
        guard let target = toolName ?? kindLabel else { return "承認待ち" }
        return "承認待ち · \(target) · \(subject)"
    }

    var compactAccessibilityLabel: String {
        let prefix = (toolName ?? kindLabel).map { "承認待ち · \($0)" } ?? "承認待ち"
        return "\(prefix)、\(subject)。表示するとキーボードを閉じます"
    }

    var buttonDecisions: [ApprovalDecision] {
        let scopeDecision: [ApprovalDecision] = allowsSessionScope ? [.acceptForSession] : []
        return [.accept] + scopeDecision + [.decline, .cancel]
    }

    var armKey: String {
        let sourceKey: String = switch source {
        case .codex(let approvalID): "codex:\(approvalID)"
        case .claudeToolPermission(let requestID, let answerKey): "question:\(requestID):\(answerKey)"
        }
        let files = diffFiles.map { "\($0.path):\($0.kind ?? ""): \($0.diff)" }.joined(separator: "\n")
        return [sourceKey, kind?.rawValue ?? "unknown", subject, explanation ?? "", toolName ?? "", String(allowsSessionScope), files]
            .joined(separator: "\u{1f}")
    }

    static func codex(
        approval: Approval,
        statusEnteredAt: Date,
        chatMessages: [ChatMessage]
    ) -> Self {
        let kind: Kind? = switch approval.actionKind {
        case "command": .command
        case "fileChange": .fileChange
        case "permissions": .permissions
        default: nil
        }
        let changes = chatMessages.first { $0.id == approval.id }.flatMap { message -> [ChatFileChange]? in
            guard case let .fileChange(_, changes) = message else { return nil }
            return changes
        } ?? []
        return Self(
            id: "codex:\(approval.id)",
            source: .codex(approvalID: approval.id),
            kind: kind,
            subject: approval.prompt,
            explanation: nil,
            requestedAt: statusEnteredAt,
            toolName: nil,
            allowsSessionScope: true,
            diffFiles: changes
        )
    }

    static func claudeToolPermission(
        requestID: String,
        question: UserQuestionItem,
        statusEnteredAt: Date
    ) -> Self {
        let toolName = question.toolName ?? ""
        let kind: Kind = switch toolName {
        case "Bash": .command
        case "Edit", "MultiEdit", "Write", "NotebookEdit": .fileChange
        default: .tool
        }
        let detail = question.toolDetail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = detail.flatMap { $0.isEmpty ? nil : $0 } ?? question.question
        return Self(
            id: "question:\(requestID):\(question.question)",
            source: .claudeToolPermission(requestID: requestID, answerKey: question.question),
            kind: kind,
            subject: subject,
            explanation: subject == question.question ? nil : question.question,
            requestedAt: statusEnteredAt,
            toolName: toolName,
            allowsSessionScope: question.allowsSessionScope,
            diffFiles: []
        )
    }
}

enum ReplyApprovalPolicy {
    static let armDelay: TimeInterval = 0.6

    static func isArmed(presentedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(presentedAt) >= armDelay
    }

    static func sinceText(startedAt: Date, now: Date) -> String {
        let minutes = Int(now.timeIntervalSince(startedAt) / 60)
        return minutes < 1 ? "たった今から" : "\(minutes)分前から"
    }
}

struct ReplyApprovalResult: Equatable {
    let actionLabel: String
    let remainingCount: Int
    var nextSessionName: String? = nil
    var nextIsQuestion: Bool = false
    var nextAttention: SessionNavigationState.AttentionItem? = nil

    var nextName: String? { nextAttention?.name ?? nextSessionName }

    var nextStatusLabel: String? {
        if let nextAttention { return nextAttention.statusLabel }
        guard nextSessionName != nil else { return nil }
        return nextIsQuestion ? "質問あり" : "承認待ち"
    }
}
