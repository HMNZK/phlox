import Foundation

private let approvalPatterns = ["allow", "approve", "permission", "do you want", "y/n"]

private func isApprovalRequest(_ message: String) -> Bool {
    let lowercased = message.lowercased()
    return approvalPatterns.contains { lowercased.contains($0) }
}

/// Pure 関数: 現在のステータスとフックイベントから次のステータスを返す。
public func reduce(_ status: SessionStatus, applying event: HookEvent) -> SessionStatus {
    switch (status, event) {
    case (.completed(let exitCode), _):
        return .completed(exitCode: exitCode)
    case (.error(let message), _):
        return .error(message: message)

    case (.awaitingApproval(let prompt), .stop):
        return .awaitingApproval(prompt: prompt)

    case (_, .sessionStart):
        return .idle
    case (_, .userPromptSubmit):
        return .running
    case (_, .preToolUse(let toolName)):
        // ExitPlanMode はプラン承認待ち。ユーザー応答までブロックするため awaitingApproval にする。
        if toolName == "ExitPlanMode" {
            return .awaitingApproval(prompt: "Plan approval requested")
        }
        return .running
    case (_, .postToolUse):
        return .running
    case (_, .stop):
        return .idle
    case (_, .notification(let message)):
        if isApprovalRequest(message) {
            return .awaitingApproval(prompt: message)
        }
        return status
    }
}
