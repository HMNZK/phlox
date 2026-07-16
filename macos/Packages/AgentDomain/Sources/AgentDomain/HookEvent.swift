import Foundation

public enum HookEvent: Sendable, Equatable {
    case sessionStart
    case notification(message: String)
    case stop(turnId: String?)
    case preToolUse(toolName: String)
    case postToolUse(toolName: String)
    case userPromptSubmit(turnId: String?)
}
