public enum ApprovalDecision: String, Codable, CaseIterable, Sendable, Equatable {
    case accept
    case decline
    case acceptForSession
    case cancel
}
