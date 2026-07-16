import Foundation

// Hidden secret: escape double-tap detection and replay preamble formatting policy.
struct EscapeRevertPolicy {
    static let doubleEscapeWindow: TimeInterval = 1.5
    static let replayContextCharacterLimit = 12_000

    static func revertCandidates(from transcript: [ChatItem]) -> [ChatItem] {
        let userMessages = transcript.filter { item in
            if case .userMessage = item { return true }
            return false
        }
        return Array(userMessages.reversed())
    }

    static func isDoubleEscape(lastEscapeAt: Date?, now: Date) -> Bool {
        guard let lastEscapeAt else { return false }
        return now.timeIntervalSince(lastEscapeAt) <= doubleEscapeWindow
    }

    static func replayContext(from items: [ChatItem]) -> String? {
        let lines: [String] = items.compactMap { item in
            switch item {
            case .userMessage(_, let text, _, _):
                return "User: \(text)"
            case .agentMessage(_, let text, _):
                return "Assistant: \(text)"
            default:
                return nil
            }
        }
        guard !lines.isEmpty else { return nil }
        let joined = lines.joined(separator: "\n\n")
        if joined.count > replayContextCharacterLimit {
            return String(joined.suffix(replayContextCharacterLimit))
        }
        return joined
    }
}
