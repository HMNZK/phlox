import Foundation
import Testing
@testable import AgentConfigKit

// MARK: - frontmatter

@Test("frontmatter から name と description を読める")
func skillFrontmatter_parsesNormalCase() {
    let markdown = """
    ---
    name: web-search
    description: Web を検索する
    allowed-tools: Bash, WebSearch
    ---

    # Web Search
    """
    let parsed = ClaudeSkillFrontmatterParsing.parse(from: markdown)

    #expect(parsed["name"] == "web-search")
    #expect(parsed["description"] == "Web を検索する")
    #expect(parsed["allowed-tools"] == "Bash, WebSearch")
}

@Test("frontmatter が無ければ空になる")
func skillFrontmatter_handlesMissingFrontmatter() {
    let markdown = "# Skill\n本文だけ"
    #expect(ClaudeSkillFrontmatterParsing.parse(from: markdown).isEmpty)
}

@Test("引用符付きの値を外して読める")
func skillFrontmatter_stripsQuotes() {
    let markdown = """
    ---
    name: "quoted-name"
    description: 'single quoted'
    ---
    """
    let parsed = ClaudeSkillFrontmatterParsing.parse(from: markdown)

    #expect(parsed["name"] == "quoted-name")
    #expect(parsed["description"] == "single quoted")
}

@Test("値にコロンが含まれても最初のコロンだけ区切りになる")
func skillFrontmatter_handlesColonInValue() {
    let markdown = """
    ---
    description: https://example.com:8080/path
    ---
    """
    #expect(ClaudeSkillFrontmatterParsing.parse(from: markdown)["description"] == "https://example.com:8080/path")
}

@Test("空ファイルでも壊れない")
func skillFrontmatter_handlesEmptyFile() {
    #expect(ClaudeSkillFrontmatterParsing.parse(from: "").isEmpty)
    #expect(ClaudeSkillFrontmatterParsing.parse(from: "   ").isEmpty)
}

// MARK: - 列挙

@Test("ユーザーとプロジェクトの skill を列挙できる")
func skillFiles_discoversUserAndProject() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-skills-\(UUID().uuidString)", isDirectory: true)
    let project = home.appendingPathComponent("proj", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }

    try makeSkillTree(
        at: home.appendingPathComponent(".claude/skills/user-skill", isDirectory: true),
        frontmatter: """
        ---
        name: User Skill
        description: ユーザー用
        ---
        """,
        body: "# User"
    )
    try makeSkillTree(
        at: project.appendingPathComponent(".claude/skills/project-skill", isDirectory: true),
        frontmatter: """
        ---
        name: Project Skill
        description: プロジェクト用
        ---
        """,
        body: "# Project"
    )

    let paths = ClaudeConfigPaths(homeDirectory: home)
    let skills = ClaudeSkillFiles(paths: paths).discover(projectDirectory: project)

    #expect(skills.count == 2)
    let user = try #require(skills.first { $0.scope == .user })
    #expect(user.directoryName == "user-skill")
    #expect(user.name == "User Skill")
    #expect(user.description == "ユーザー用")
    #expect(user.displayPath == "~/.claude/skills/user-skill/SKILL.md")

    let projectSkill = try #require(skills.first { $0.scope == .project })
    #expect(projectSkill.directoryName == "project-skill")
    #expect(projectSkill.name == "Project Skill")
    #expect(projectSkill.displayPath == "proj/.claude/skills/project-skill/SKILL.md")
}

@Test("SKILL.md が無いディレクトリは skip する")
func skillFiles_skipsDirectoryWithoutSkillFile() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-skills-skip-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }

    let valid = home.appendingPathComponent(".claude/skills/valid", isDirectory: true)
    let invalid = home.appendingPathComponent(".claude/skills/invalid", isDirectory: true)
    try FileManager.default.createDirectory(at: invalid, withIntermediateDirectories: true)
    try makeSkillTree(
        at: valid,
        frontmatter: """
        ---
        name: valid
        ---
        """,
        body: "# Valid"
    )

    let skills = ClaudeSkillFiles(paths: ClaudeConfigPaths(homeDirectory: home))
        .discover(projectDirectory: nil)

    #expect(skills.count == 1)
    #expect(skills[0].directoryName == "valid")
}

// MARK: - 読み書き

@Test("SKILL.md の本文を読み書きできる")
func skillFiles_readAndWrite() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-skills-rw-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }

    try makeSkillTree(
        at: home.appendingPathComponent(".claude/skills/demo", isDirectory: true),
        frontmatter: """
        ---
        name: demo
        description: 初期
        ---
        """,
        body: "# Demo"
    )

    let store = ClaudeSkillFiles(paths: ClaudeConfigPaths(homeDirectory: home))
    let skill = try #require(store.discover(projectDirectory: nil).first)

    #expect(try store.read(skill).contains("# Demo"))
    let updated = """
    ---
    name: demo
    description: 更新後
    ---

    # Demo Updated
    """
    try store.write(updated, to: skill)
    #expect(try store.read(skill) == updated)
}

// MARK: - helpers

private func makeSkillTree(at directory: URL, frontmatter: String, body: String) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let content = frontmatter + "\n" + body
    try Data(content.utf8).write(to: directory.appendingPathComponent("SKILL.md"))
}
