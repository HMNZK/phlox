import AgentDomain
import Foundation
import Testing
@testable import SessionFeature

@Suite("Agent skill suggestions")
struct AgentSkillSuggestionTests {
    @Test("大量のスキルでも取得済み候補から部分一致で絞り込む")
    func cachedSearch() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let directory = fixture.home.appending(path: ".codex/skills")
        for index in 0..<200 { try fixture.skill("sample-\(index)", in: directory) }
        let clock = ContinuousClock()
        let coldStart = clock.now
        let all = ComposerSuggestionSources.slashCandidates(
            agentKind: .codex, homeDirectory: fixture.home, workingDirectory: fixture.workspace.path
        )
        let cold = coldStart.duration(to: clock.now)
        let warmStart = clock.now
        let warm = ComposerSuggestionSources.cachedSlashCandidates(
            agentKind: .codex, homeDirectory: fixture.home, workingDirectory: fixture.workspace.path, matching: "ple-199"
        )
        let warmDuration = warmStart.duration(to: clock.now)
        #expect(all.count == 200)
        #expect(warm?.map(\.insertionText) == ["$sample-199"])
        print("Skill suggestion scan: cold=\(milliseconds(cold)) ms, cached search=\(milliseconds(warmDuration)) ms")
    }

    @Test("Codex はリンク先と有効なプラグインの現行版だけを候補にする")
    func codexLocations() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let shared = fixture.root.appending(path: "shared")
        try fixture.skill("shared-tool", in: shared)
        try FileManager.default.createDirectory(at: shared.appending(path: "empty"), withIntermediateDirectories: true)
        let codex = fixture.home.appending(path: ".codex")
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: codex.appending(path: "skills"), withDestinationURL: shared)
        try "[plugins.\"pstack-codex@phlox-pstack\"]\nenabled = true\n[plugins.\"off@phlox-pstack\"]\nenabled = false\n".write(
            to: codex.appending(path: "config.toml"), atomically: true, encoding: .utf8
        )
        let cache = codex.appending(path: "plugins/cache/phlox-pstack")
        try fixture.skill("poteto-mode", in: cache.appending(path: "pstack-codex/1.0.0/skills"))
        try fixture.skill("new-mode", in: cache.appending(path: "pstack-codex/2.0.0/skills"))
        try fixture.skill("off-mode", in: cache.appending(path: "off/1.0.0/skills"))

        let candidates = ComposerSuggestionSources.slashCandidates(
            agentKind: .codex, homeDirectory: fixture.home, workingDirectory: fixture.workspace.path
        )
        #expect(candidates.contains { $0.insertionText == "$shared-tool" && $0.skillIdentity != nil })
        #expect(candidates.contains { $0.insertionText == "$pstack-codex:new-mode" && $0.skillIdentity != nil })
        #expect(!candidates.contains { $0.insertionText.contains("poteto-mode") || $0.insertionText.contains("off-mode") })
        #expect(!candidates.contains { $0.insertionText == "$empty" })
        #expect(!candidates.contains { $0.insertionText == "/config" })

        let middle = ComposerSuggestionSources.cachedSlashCandidates(
            agentKind: .codex, homeDirectory: fixture.home, workingDirectory: fixture.workspace.path, matching: "stack"
        )
        #expect(middle?.map(\.insertionText) == ["$pstack-codex:new-mode"])
    }

    @Test("Claude は有効なインストール記録だけを名前空間付きで候補にする")
    func claudePlugins() throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let plugins = fixture.home.appending(path: ".claude/plugins")
        try FileManager.default.createDirectory(at: plugins, withIntermediateDirectories: true)
        let active = plugins.appending(path: "cache/cursor-plugins/pstack/1.0")
        let inactive = plugins.appending(path: "cache/cursor-plugins/old/1.0")
        try fixture.skill("poteto-mode", in: active.appending(path: "skills"))
        try fixture.skill("unused", in: inactive.appending(path: "skills"))
        let registry: [String: Any] = ["plugins": [
            "pstack@cursor-plugins": [["installPath": active.path, "scope": "user"]],
            "old@cursor-plugins": [["installPath": inactive.path, "scope": "user"]],
        ]]
        try JSONSerialization.data(withJSONObject: registry).write(to: plugins.appending(path: "installed_plugins.json"))
        try JSONSerialization.data(withJSONObject: ["enabledPlugins": [
            "pstack@cursor-plugins": true, "old@cursor-plugins": false,
        ]]).write(to: fixture.home.appending(path: ".claude/settings.json"))

        let candidates = ComposerSuggestionSources.slashCandidates(
            agentKind: .claudeCode, homeDirectory: fixture.home, workingDirectory: fixture.workspace.path
        )
        #expect(candidates.contains { $0.insertionText == "/pstack:poteto-mode" })
        #expect(!candidates.contains { $0.insertionText.contains("unused") })
        let middle = ComposerSuggestionSources.cachedSlashCandidates(
            agentKind: .claudeCode, homeDirectory: fixture.home, workingDirectory: fixture.workspace.path, matching: "teto"
        )
        #expect(middle?.map(\.insertionText) == ["/pstack:poteto-mode"])
    }
}

private func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
}

private struct Fixture {
    let root: URL
    let home: URL
    let workspace: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "phlox-skill-suggestion-\(UUID().uuidString)")
        home = root.appending(path: "home")
        workspace = root.appending(path: "workspace")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    func skill(_ name: String, in directory: URL) throws {
        let skill = directory.appending(path: name)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try "---\nname: \(name)\ndescription: Example\n---\n".write(
            to: skill.appending(path: "SKILL.md"), atomically: true, encoding: .utf8
        )
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
