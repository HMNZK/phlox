import CodexAppServerKit
import Foundation
import Testing
@testable import SessionFeature

@Suite("Codex skill content freshness")
@MainActor
struct CodexSkillFingerprintTests {
    @Test("入れ子や独自の配置でもプラグイン全体の変更を検出する", arguments: ["skills/category/review", "custom-skills/review"])
    func alternateSkillLocations(directory: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let alternate = fixture.root.appendingPathComponent(directory).appendingPathComponent("SKILL.md")
        try FileManager.default.createDirectory(at: alternate.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture.skill, to: alternate)
        let before = try #require(CodexSkillFingerprint.read(skillPath: alternate.path))
        try "changed".write(to: fixture.root.appendingPathComponent("shared.md"), atomically: true, encoding: .utf8)
        #expect(CodexSkillFingerprint.read(skillPath: alternate.path) != before)
    }

    @Test("複数のmanifestでプラグインの範囲が曖昧なら選択を保持しない")
    func ambiguousPluginRootHasNoFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try "{}".write(to: fixture.skill.deletingLastPathComponent().appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        #expect(CodexSkillFingerprint.read(skillPath: fixture.skill.path) == nil)
    }

    @Test("内容が同じ更新通知では選択を保持し、native input を送れる")
    func unchangedBundleKeepsSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let state = CodexSkillSelectionState(client: fixture.client, sessionCWD: fixture.root.path)
        await state.refresh()
        #expect(state.select(try #require(state.skills.first)))
        state.invalidate()
        #expect(state.inputs(for: "$review 本文") == nil)
        await state.refresh()
        #expect(state.inputs(for: "$review 本文") == [.text("本文"), .skill(name: "review", path: fixture.skill.path)])
        #expect(!state.requiresReselection)
    }

    @Test("同じパスと説明でも共有の参照ファイルが変われば再選択を求める")
    func changedReferenceRejectsSelection() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let state = CodexSkillSelectionState(client: fixture.client, sessionCWD: fixture.root.path)
        await state.refresh()
        #expect(state.select(try #require(state.skills.first)))
        try "changed".write(to: fixture.root.appendingPathComponent("shared.md"), atomically: true, encoding: .utf8)
        state.invalidate()
        await state.refresh()
        #expect(state.requiresReselection)
        #expect(state.inputs(for: "$review 本文") == nil)
        #expect(state.select(try #require(state.skills.first)))
        #expect(state.canSendSelectedSkill)
    }

    @Test("シンボリックリンクや欠損からは同一性を推定しない")
    func unprovableBundleHasNoFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(CodexSkillFingerprint.read(skillPath: fixture.skill.path) != nil)
        try FileManager.default.createSymbolicLink(
            at: fixture.root.appendingPathComponent("alias.md"),
            withDestinationURL: fixture.root.appendingPathComponent("shared.md")
        )
        #expect(CodexSkillFingerprint.read(skillPath: fixture.skill.path) == nil)
        #expect(CodexSkillFingerprint.read(skillPath: fixture.root.appendingPathComponent("missing/SKILL.md").path) == nil)
    }

    @Test("実行属性の変更も同一のスキル一式とは扱わない")
    func executableChangeChangesFingerprint() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let before = try #require(CodexSkillFingerprint.read(skillPath: fixture.skill.path))
        let helper = fixture.root.appendingPathComponent("helper.sh")
        try "exit 0\n".write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: helper.path)
        let withHelper = try #require(CodexSkillFingerprint.read(skillPath: fixture.skill.path))
        #expect(before != withHelper)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: helper.path)
        #expect(CodexSkillFingerprint.read(skillPath: fixture.skill.path) != withHelper)
    }
}

private struct Fixture {
    let root: URL
    let skill: URL
    let client: FingerprintClient

    init() throws {
        var repository = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 { repository.deleteLastPathComponent() }
        root = repository.appendingPathComponent(".verification/pstack-codex/skill-fingerprint-tests/\(UUID().uuidString)")
        skill = root.appendingPathComponent("skills/review/SKILL.md")
        try FileManager.default.createDirectory(at: skill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "---\nname: review\ndescription: review\n---\nReview the target.\n".write(to: skill, atomically: true, encoding: .utf8)
        try "{}".write(to: root.appendingPathComponent("plugin.json"), atomically: true, encoding: .utf8)
        try "shared reference".write(to: root.appendingPathComponent("shared.md"), atomically: true, encoding: .utf8)
        client = FingerprintClient(cwd: root.path, path: skill.path)
    }

    func remove() {
        do { try FileManager.default.removeItem(at: root) }
        catch { Issue.record("Failed to clean owned fixture: \(error)") }
    }
}

private struct FingerprintClient: CodexSkillSelectionClient {
    let cwd: String
    let path: String
    var skillEvents: AsyncStream<ThreadEvent> { AsyncStream { $0.finish() } }

    func skillsList(_ params: SkillsListParams) async throws -> SkillsListResponse {
        SkillsListResponse(data: [SkillsListEntry(cwd: cwd, errors: [], skills: [
            SkillMetadata(description: "review", enabled: true, name: "review", path: path, scope: .user),
        ])])
    }
}
