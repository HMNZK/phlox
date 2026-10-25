import Foundation

public struct SkillSuggestionQuery: Equatable, Sendable {
    public let range: Range<String.Index>
    public let term: String

    public static func detect(text: String, cursorUTF16: Int) -> Self? {
        guard cursorUTF16 > 0, cursorUTF16 <= text.utf16.count,
              let cursor = String.Index(text.utf16.index(text.utf16.startIndex, offsetBy: cursorUTF16), within: text)
        else { return nil }
        let prefix = text[..<cursor]
        let start = prefix.lastIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? text.startIndex
        guard start < cursor, text[start] == "/" else { return nil }
        return Self(range: start..<cursor, term: String(text[text.index(after: start)..<cursor]))
    }

    public func matches(_ skill: AgentSkill) -> Bool {
        term.isEmpty || skill.name.localizedCaseInsensitiveContains(term)
    }

    public func inserting(_ skill: AgentSkill, into text: String, agent: AgentKind) -> (text: String, cursorUTF16: Int) {
        let insertion = (agent == .codex ? "$" : "/") + skill.name + " "
        let offset = range.lowerBound.utf16Offset(in: text)
        return (text.replacingCharacters(in: range, with: insertion), offset + insertion.utf16.count)
    }
}
