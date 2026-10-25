import Testing
@testable import PhloxCore

struct SkillSuggestionQueryTests {
    let skill = AgentSkill(name: "poteto-mode", description: "説明", path: "/skills/poteto-mode/SKILL.md")

    @Test func detectsSlashAndFiltersCaseInsensitively() throws {
        let query = try #require(SkillSuggestionQuery.detect(text: "/POT", cursorUTF16: 4))
        #expect(query.matches(skill))
        #expect(SkillSuggestionQuery.detect(text: "https://example", cursorUTF16: 15) == nil)
        #expect(SkillSuggestionQuery.detect(text: "通常入力", cursorUTF16: 4) == nil)
        #expect(SkillSuggestionQuery.detect(text: "/", cursorUTF16: 1)?.matches(skill) == true)
    }

    @Test func replacesOnlyTokenAndKeepsUnicodeAndSuffix() throws {
        let text = "🍟を使って /pot 後続文"
        let prefix = "🍟を使って /pot"
        let query = try #require(SkillSuggestionQuery.detect(text: text, cursorUTF16: prefix.utf16.count))
        let result = query.inserting(skill, into: text, agent: .claudeCode)
        #expect(result.text == "🍟を使って /poteto-mode  後続文")
        #expect(result.cursorUTF16 == "🍟を使って /poteto-mode ".utf16.count)
        #expect(query.inserting(skill, into: text, agent: .codex).text == "🍟を使って $poteto-mode  後続文")
    }

    @Test func rejectsInvalidUTF16AndWhitespace() {
        for cursor in [-1, 0, 1, 100] {
            #expect(SkillSuggestionQuery.detect(text: "🍟 /", cursorUTF16: cursor) == nil)
        }
        #expect(SkillSuggestionQuery.detect(text: "/pot ", cursorUTF16: 5) == nil)
    }
}
