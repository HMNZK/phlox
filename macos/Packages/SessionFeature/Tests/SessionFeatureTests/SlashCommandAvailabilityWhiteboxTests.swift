import Foundation
import Testing
@testable import SessionFeature

@Suite("Whitebox: セッション由来スラッシュコマンド候補（task-3）")
struct SlashCommandAvailabilityWhiteboxTests {

    @Test("同一キャッシュキーは TTL 内に再走査しない")
    func sameKeyUsesCachedCandidates() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let skill = workspace.appending(path: ".claude/skills/custom", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\ndescription: 最初の説明\n---".write(
            to: skill.appending(path: "SKILL.md"), atomically: true, encoding: .utf8
        )

        let first = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["custom"], homeDirectory: workspace, workingDirectory: workspace.path
        )
        try "---\ndescription: 変更後の説明\n---".write(
            to: skill.appending(path: "SKILL.md"), atomically: true, encoding: .utf8
        )
        let second = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["custom"], homeDirectory: workspace, workingDirectory: workspace.path
        )

        #expect(first.first?.subtitle == "最初の説明")
        #expect(second == first)
    }

    @Test("コロンを含む名前をそのまま候補にする")
    func colonInCommandNameIsPreserved() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["claude-security:scan"], homeDirectory: workspace, workingDirectory: workspace.path
        )

        #expect(candidates.map(\.title) == ["/claude-security:scan"])
        #expect(candidates.map(\.insertionText) == ["/claude-security:scan"])
    }

    private func makeWorkspace() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-slash-whitebox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
