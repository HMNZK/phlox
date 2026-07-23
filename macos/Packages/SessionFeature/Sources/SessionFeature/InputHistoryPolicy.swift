public struct InputHistoryEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

public enum InputHistoryPolicy {
    /// transcript からユーザー入力を入力順で抽出する。
    public static func entries(from transcript: [ChatItem]) -> [InputHistoryEntry] {
        transcript.compactMap { item in
            guard case let .userMessage(id, text, _, _) = item else { return nil }
            return InputHistoryEntry(id: id, text: text)
        }
    }

    /// スクラバーに表示する最新側の入力を、相対順序を維持して返す。
    public static func scrubberTicks(from entries: [InputHistoryEntry], cap: Int) -> [InputHistoryEntry] {
        guard cap > 0 else { return [] }
        guard entries.count > cap else { return entries }
        return Array(entries.suffix(cap))
    }
}
