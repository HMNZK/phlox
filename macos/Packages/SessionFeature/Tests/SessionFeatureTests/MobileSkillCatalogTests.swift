import AgentDomain
import Foundation
import Testing
@testable import SessionFeature

@Suite struct MobileSkillCatalogTests {
    @Test func catalogPreservesDescriptionsPathsAndCommandFiltering() throws {
        let project = (0..<6).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let root = project.appending(path: ".verification/mobile-skill-catalog-\(UUID().uuidString)")
        let home = root.appending(path: "home")
        let workspace = root.appending(path: "project")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "用途: スキル候補のテスト。作成: MobileSkillCatalogTests。PID: \(ProcessInfo.processInfo.processIdentifier)、実行: \(ProcessInfo.processInfo.arguments.first ?? "test-runner")。出力: \(root.path)".write(to: root.appending(path: "owner.txt"), atomically: true, encoding: .utf8)
        defer {
            do { try FileManager.default.removeItem(at: root) }
            catch { Issue.record("fixture cleanup failed: \(error)") }
        }
        for base in [home, workspace] {
            let directory = base.appending(path: ".claude/skills/review")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try "---\ndescription: Review this project\n---\n".write(to: directory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
        }
        let all = ComposerSkillSuggestions.skills(agentKind: .claudeCode, workingDirectory: workspace.path, homeDirectory: home)
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.name == "review" && $0.description == "Review this project" })
        #expect(Set(all.map(\.path)).count == 2)
        #expect(ComposerSkillSuggestions.skills(agentKind: .claudeCode, workingDirectory: workspace.path, availableCommands: [], homeDirectory: home).isEmpty)
        #expect(ComposerSkillSuggestions.skills(agentKind: .claudeCode, workingDirectory: workspace.path, availableCommands: ["review"], homeDirectory: home) == all)
    }
}
