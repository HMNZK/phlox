import Foundation

public enum SessionStatus: Sendable, Equatable {
    case starting
    case idle
    case running
    case awaitingApproval(prompt: String)
    case completed(exitCode: Int32)
    case error(message: String)
}
