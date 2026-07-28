import Foundation
import Testing
@testable import AgentConfigKit

@Test("ユーザーとプロジェクトのメモリを、未作成のものも含めて列挙する")
func memoryFiles_discoversUserAndProject() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-memory-\(UUID().uuidString)", isDirectory: true)
    let project = home.appendingPathComponent("proj", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(
        at: home.appendingPathComponent(".claude", isDirectory: true),
        withIntermediateDirectories: true
    )
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    try Data("user memory".utf8).write(to: home.appendingPathComponent(".claude/CLAUDE.md"))

    let paths = ClaudeConfigPaths(homeDirectory: home)
    let files = ClaudeMemoryFiles(paths: paths).discover(projectDirectory: project)

    #expect(files.count == 4)
    let userClaude = try #require(files.first { $0.displayPath == "~/.claude/CLAUDE.md" })
    #expect(userClaude.exists)
    let userAgents = try #require(files.first { $0.displayPath == "~/.claude/AGENTS.md" })
    #expect(userAgents.exists == false)
    #expect(files.contains { $0.scope == .project && $0.fileName == "CLAUDE.md" })
}

@Test("メモリの読み書きができ、無いファイルは空文字を返す")
func memoryFiles_readAndWrite() throws {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("claude-memory-rw-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

    let files = ClaudeMemoryFiles(paths: ClaudeConfigPaths(homeDirectory: home))
    let target = try #require(files.discover(projectDirectory: nil).first)

    #expect(try files.read(target) == "")
    try files.write("# メモ\n- ルール", to: target)
    #expect(try files.read(target) == "# メモ\n- ルール")
}

@Test("claude --version の出力から版番号だけ取り出す")
func statusBuilder_parsesVersion() {
    #expect(ClaudeEnvironmentStatusBuilder.parseVersion(from: "2.1.220 (Claude Code)\n") == "2.1.220")
    #expect(ClaudeEnvironmentStatusBuilder.parseVersion(from: "   ") == nil)
}

@Test("設定ファイルから状態の集計値を作る")
func statusBuilder_summarizesSettings() throws {
    let root = try JSONValueCoder.decode(Data("""
    {
      "model": "opusplan",
      "effortLevel": "high",
      "outputStyle": "Explanatory",
      "permissions": { "allow": ["Read", "Bash(ls)"], "deny": ["Bash(rm *)"] },
      "hooks": { "Stop": [ { "hooks": [ { "type": "command", "command": "a.sh" } ] } ] }
    }
    """.utf8))

    let status = ClaudeEnvironmentStatusBuilder.fromSettings(root)
    #expect(status.model == "opusplan")
    #expect(status.effortLevel == "high")
    #expect(status.outputStyle == "Explanatory")
    #expect(status.permissionRuleCount == 3)
    #expect(status.hookCount == 1)
}
