import Testing
import Foundation
@testable import DashboardFeature
@testable import SessionFeature

// loopflow task-5（item 19）の凍結受け入れテスト（実装役は編集禁止）。
// 契約: スラッシュコマンドのサジェストで Skill 候補の subtitle には、その Skill の
// SKILL.md frontmatter の `description` を表示する。description が読めない場合のみ
// 従来どおり "Skill" にフォールバックする（tasks/task-5.md）。

private func makeTempDir() throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appending(path: "phlox-skill-desc-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    return base
}

@Test func skillSuggestion_subtitleUsesSkillMdDescription() throws {
    let home = try makeTempDir()
    let workspace = try makeTempDir()
    defer {
        try? FileManager.default.removeItem(at: home)
        try? FileManager.default.removeItem(at: workspace)
    }

    let skillDir = home.appending(path: ".claude/skills/my-skill", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)
    let skillMd = """
    ---
    name: my-skill
    description: Does a helpful thing
    ---
    # My Skill
    body
    """
    try skillMd.write(to: skillDir.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

    let candidates = ComposerSuggestionSources.slashCandidates(
        homeDirectory: home,
        workingDirectory: workspace.path
    )
    let skillCandidate = try #require(candidates.first { $0.insertionText == "/my-skill" })
    #expect(skillCandidate.subtitle == "Does a helpful thing")
}

@Test func skillSuggestion_subtitleFallsBackToSkillWhenNoDescription() throws {
    let home = try makeTempDir()
    let workspace = try makeTempDir()
    defer {
        try? FileManager.default.removeItem(at: home)
        try? FileManager.default.removeItem(at: workspace)
    }

    // SKILL.md を置かない Skill ディレクトリ → description 不明 → "Skill" フォールバック。
    let skillDir = home.appending(path: ".claude/skills/bare-skill", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDir, withIntermediateDirectories: true)

    let candidates = ComposerSuggestionSources.slashCandidates(
        homeDirectory: home,
        workingDirectory: workspace.path
    )
    let skillCandidate = try #require(candidates.first { $0.insertionText == "/bare-skill" })
    #expect(skillCandidate.subtitle == "Skill")
}
