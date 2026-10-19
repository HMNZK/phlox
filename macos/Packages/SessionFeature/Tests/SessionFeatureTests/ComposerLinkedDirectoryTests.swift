import Foundation
import Testing
@testable import SessionFeature

@Suite("Composer linked directories")
struct ComposerLinkedDirectoryTests {
    @Test("ホームとプロジェクトのリンク先からスキル・コマンドを補完する",
          arguments: ["skills", "commands"], [false, true])
    func linkedDirectoryCandidates(kind: String, inProject: Bool) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("phlox-linked-commands-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let home = root.appendingPathComponent("home", isDirectory: true)
        let project = root.appendingPathComponent("project", isDirectory: true)
        let target = root.appendingPathComponent("shared", isDirectory: true)
        for directory in [home, project, target] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let parent = (inProject ? project : home).appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: parent.appendingPathComponent(kind, isDirectory: true),
            withDestinationURL: target
        )

        if kind == "skills" {
            let skill = target.appendingPathComponent("shared-skill", isDirectory: true)
            try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
            try "---\nname: shared-skill\ndescription: 共有スキルの説明\n---\n本文\n".write(
                to: skill.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8
            )
        } else {
            try "コマンド本文".write(
                to: target.appendingPathComponent("shared-command.md"), atomically: true, encoding: .utf8
            )
        }

        let name = kind == "skills" ? "shared-skill" : "shared-command"
        let candidates = ComposerSuggestionSources.slashCandidates(
            homeDirectory: home, workingDirectory: project.path
        )
        let candidate = try #require(candidates.first { $0.title == "/\(name)" })
        #expect(candidate.insertionText == "/\(name)")
        #expect(candidate.subtitle == (kind == "skills" ? "共有スキルの説明" : "Custom command"))
        #expect(candidate.origin == (kind == "skills" ? .skills : .commands))
        #expect(candidates.filter { $0.title == "/\(name)" }.count == 1)
    }
}
