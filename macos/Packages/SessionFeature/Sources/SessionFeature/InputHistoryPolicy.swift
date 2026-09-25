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

/// 入力欄の ↑↓ で過去の入力を呼び戻す位置（05 R2「↑ 入力履歴（候補がないとき）」）。
/// ↑ で古い方へ、↓ で新しい方へ。最新より先へ進むと呼び戻す前の下書きに戻る。呼び戻した文を書き換えたら最初から。
public struct InputHistoryCursor: Equatable, Sendable {
    public enum Direction: Sendable { case older, newer }

    private var index: Int?
    private var savedDraft = ""
    private var recalledText: String?

    public init() {}

    /// 呼び戻す文。動けない（履歴が無い・端にいる・呼び戻していない）ときは nil。
    public mutating func recall(_ direction: Direction, entries: [String], currentText: String) -> String? {
        if let recalledText, recalledText != currentText { self = InputHistoryCursor() }
        switch direction {
        case .older:
            let next: Int
            if let index {
                guard index > 0 else { return nil }
                next = index - 1
            } else {
                guard !entries.isEmpty else { return nil }
                savedDraft = currentText
                next = entries.count - 1
            }
            index = next
            recalledText = entries[next]
            return entries[next]
        case .newer:
            guard let index else { return nil }
            guard index + 1 < entries.count else {
                let draft = savedDraft
                self = InputHistoryCursor()
                return draft
            }
            self.index = index + 1
            recalledText = entries[index + 1]
            return entries[index + 1]
        }
    }
}
