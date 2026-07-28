import Foundation
import Testing
@testable import SessionFeature

// task-2 白箱テスト（実装者著）。受け入れテストが覆っていない
// 「subtitle の解決優先順」「並び順の決定論」「warm キャッシュのピーク」を固める。

private func makeWorkspace() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-seed-whitebox-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeSkill(named name: String, description: String, in workspace: URL) throws {
    let skillDirectory = workspace
        .appending(path: ".claude/skills/\(name)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    try """
    ---
    name: \(name)
    description: \(description)
    ---

    本文
    """.write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)
}

private func writeCustomCommand(named name: String, in workspace: URL) throws {
    let commandsDirectory = workspace
        .appending(path: ".claude/commands", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: commandsDirectory, withIntermediateDirectories: true)
    try "本文".write(
        to: commandsDirectory.appending(path: "\(name).md"),
        atomically: true,
        encoding: .utf8
    )
}

@Suite("Whitebox: seedCommands の候補生成（task-2）")
struct ComposerSeedCommandsWhiteboxTests {

    // MARK: - subtitle の解決優先順

    @Test("静的リストと同名の seed は、静的リストの説明を保ったまま1件になる")
    func seedMatchingBuiltinKeepsBuiltinSubtitle() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["clear"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let clears = candidates.filter { $0.title == "/clear" }
        #expect(clears.count == 1, "静的リストと seed で二重に出さないこと")
        #expect(clears.first?.subtitle == "Clear conversation history")
    }

    @Test("seed の名前がローカルスキルなら、SKILL.md の説明が付く")
    func seedMatchingLocalSkillUsesSkillDescription() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writeSkill(named: "shared-skill", description: "共有スキルの説明", in: workspace)

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["shared-skill"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let skill = try #require(candidates.first { $0.title == "/shared-skill" })
        #expect(skill.subtitle == "共有スキルの説明")
    }

    @Test("seed の名前がカスタムコマンドなら、カスタムコマンドの文言が付く")
    func seedMatchingCustomCommandUsesCustomSubtitle() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writeCustomCommand(named: "shared-command", in: workspace)

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["shared-command"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let command = try #require(candidates.first { $0.title == "/shared-command" })
        #expect(command.subtitle == "Custom command")
    }

    @Test("どこにも実体が無い seed は説明なしで出す")
    func seedOnlyCommandHasNoSubtitle() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["seeded-only-command"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let seeded = try #require(candidates.first { $0.title == "/seeded-only-command" })
        #expect(seeded.subtitle == nil)
        #expect(seeded.insertionText == "/seeded-only-command")
    }

    // MARK: - 並び順・重複

    @Test("seed があっても静的リストが先頭のまま並ぶ")
    func builtinsStayAtTheFront() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let titles = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["seed-one", "seed-two"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        ).map(\.title)

        let builtinTitles = ComposerSuggestionSources.builtinSlashCommands.map(\.title)
        #expect(Array(titles.prefix(builtinTitles.count)) == builtinTitles)
        #expect(titles.suffix(2) == ["/seed-one", "/seed-two"], "seed は受信順のまま末尾に足すこと")
    }

    @Test("seed 内の重複は一意化される")
    func duplicatedSeedNamesCollapse() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let titles = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["seed-dup", "seed-dup"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        ).map(\.title)

        #expect(titles.filter { $0 == "/seed-dup" }.count == 1)
    }

    // MARK: - warm キャッシュのピーク

    @Test("warm キャッシュのピークも seed をキーにする")
    func cachedPeekIsKeyedBySeedCommands() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        _ = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["seed-warm"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let sameSeed = ComposerSuggestionSources.cachedSlashCandidates(
            availableCommands: nil,
            seedCommands: ["seed-warm"],
            homeDirectory: workspace,
            workingDirectory: workspace.path,
            matching: "seed-"
        )
        let otherSeed = ComposerSuggestionSources.cachedSlashCandidates(
            availableCommands: nil,
            seedCommands: ["seed-other"],
            homeDirectory: workspace,
            workingDirectory: workspace.path,
            matching: "seed-"
        )

        #expect(sameSeed?.map(\.title) == ["/seed-warm"])
        #expect(otherSeed == nil, "別の seed のキャッシュを流用しないこと")
    }

    @Test("空配列の seed は、未受領で温めたキャッシュに当たる")
    func emptySeedSharesTheUnreceivedCacheEntry() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        _ = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: nil,
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let peeked = ComposerSuggestionSources.cachedSlashCandidates(
            availableCommands: nil,
            seedCommands: [],
            homeDirectory: workspace,
            workingDirectory: workspace.path,
            matching: "clea"
        )

        #expect(peeked?.map(\.title) == ["/clear"])
    }

    @Test("一覧を受領済みなら、warm ピークも seed を無視する")
    func cachedPeekIgnoresSeedWhenListIsReceived() throws {
        let workspace = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        _ = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["only-this"],
            seedCommands: ["seed-a"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let peeked = ComposerSuggestionSources.cachedSlashCandidates(
            availableCommands: ["only-this"],
            seedCommands: ["seed-b"],
            homeDirectory: workspace,
            workingDirectory: workspace.path,
            matching: ""
        )

        #expect(peeked?.map(\.title) == ["/only-this"], "seed 違いでキャッシュを分けないこと")
    }
}
