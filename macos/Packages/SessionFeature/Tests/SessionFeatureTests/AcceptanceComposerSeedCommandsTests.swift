import Foundation
import Testing
@testable import SessionFeature

// task-2 受け入れテスト（PM 著・不変）。
// acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-2.md
//   1. 静的フォールバックを実測済みの組み込みコマンドで拡充する（初回起動を救う）
//   2. seedCommands（前回セッションの一覧）を受け取り、init 未受領時の候補に混ぜる

/// 2026-07-28 の実測（docs/agent-output/measured-slash-commands-20260728.txt）で
/// claude セッションに存在を確認し、静的フォールバックへ追加するコマンド。
private let commandsAddedToFallback = [
    "/agents", "/code-review", "/deep-research", "/effort", "/fast", "/loop",
    "/recap", "/run", "/schedule", "/security-review", "/simplify", "/ultrareview",
]

/// 実測で存在しなかったため、拡充しても復活させてはならないコマンド。
private let commandsStillAbsent = [
    "/help", "/plugin", "/permissions", "/status", "/cost", "/memory",
    "/output-style", "/export", "/statusline", "/todos", "/rewind", "/resume", "/hooks",
]

private func makeEmptyWorkspace() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-seed-commands-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func writeSkill(named name: String, description: String, in workspace: URL) throws {
    let skillDirectory = workspace
        .appending(path: ".claude/skills/\(name)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
    let frontmatter = """
    ---
    name: \(name)
    description: \(description)
    ---

    本文
    """
    try frontmatter.write(
        to: skillDirectory.appending(path: "SKILL.md"),
        atomically: true,
        encoding: .utf8
    )
}

@Suite("Acceptance: init 未受領時のスラッシュ補完（task-2）")
struct AcceptanceComposerSeedCommandsTests {

    // MARK: - 静的フォールバックの拡充

    @Test("実測で存在を確認した組み込みコマンドを静的フォールバックに載せる")
    func fallbackIncludesMeasuredBuiltins() {
        let titles = Set(ComposerSuggestionSources.builtinSlashCommands.map(\.title))
        for command in commandsAddedToFallback {
            #expect(titles.contains(command), "\(command) を静的フォールバックに載せること")
        }
    }

    @Test("拡充しても、セッションに存在しないコマンドは復活させない")
    func fallbackStillExcludesAbsentCommands() {
        let titles = Set(ComposerSuggestionSources.builtinSlashCommands.map(\.title))
        for command in commandsStillAbsent {
            #expect(!titles.contains(command), "\(command) は実測で存在しないので載せないこと")
        }
    }

    @Test("静的フォールバックの各エントリは説明を持つ")
    func fallbackEntriesHaveSubtitles() {
        for candidate in ComposerSuggestionSources.builtinSlashCommands {
            #expect(candidate.subtitle?.isEmpty == false, "\(candidate.title) に説明があること")
        }
    }

    // MARK: - seedCommands の契約

    @Test("seed が nil なら従来どおり静的フォールバックを返す")
    func nilSeedFallsBackToStaticList() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: nil,
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        #expect(candidates.map(\.title) == ComposerSuggestionSources.builtinSlashCommands.map(\.title))
    }

    @Test("seed が空配列なら未受領と同じ扱いにする")
    func emptySeedIsTreatedAsUnreceived() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: [],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        #expect(candidates.map(\.title) == ComposerSuggestionSources.builtinSlashCommands.map(\.title))
    }

    @Test("seed があれば、その一覧と静的フォールバックの和集合を返す")
    func seedIsUnionedWithBuiltins() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let titles = Set(ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["seeded-only-command"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        ).map(\.title))

        #expect(titles.contains("/seeded-only-command"), "seed 由来の候補を出すこと")
        #expect(titles.contains("/clear"), "静的フォールバックの候補も残すこと")
        #expect(titles.contains("/ultrareview"), "1通も送る前に /ultrareview が出ること")
        #expect(titles.contains("/deep-research"), "1通も送る前に /deep-research が出ること")
    }

    @Test("seed に無いローカルスキルも、init 未受領時の候補に混ぜる")
    func seedIsUnionedWithLocalSkills() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try writeSkill(named: "local-only-skill", description: "ローカルのスキル", in: workspace)

        let titles = Set(ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["seeded-only-command"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        ).map(\.title))

        #expect(titles.contains("/local-only-skill"), "前回 init 後に足したスキルも出すこと")
        #expect(titles.contains("/seeded-only-command"))
    }

    @Test("内部コマンド（__ 始まり）は seed から除外する")
    func seedExcludesInternalCommands() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let titles = Set(ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["__remote-workflow", "visible-command"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        ).map(\.title))

        #expect(!titles.contains("/__remote-workflow"))
        #expect(titles.contains("/visible-command"))
    }

    @Test("一覧を受領済みなら seed は完全に無視する")
    func receivedListTakesPrecedenceOverSeed() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["only-this"],
            seedCommands: ["should-be-ignored"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        #expect(candidates.map(\.title) == ["/only-this"], "受領済み一覧だけを候補にすること")
    }

    @Test("同じ作業ディレクトリでも、seed が違えば違う候補を返す（キャッシュが混線しない）")
    func cacheIsKeyedBySeedCommands() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let first = Set(ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["seed-alpha"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        ).map(\.title))
        let second = Set(ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            seedCommands: ["seed-beta"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        ).map(\.title))

        #expect(first.contains("/seed-alpha"))
        #expect(!first.contains("/seed-beta"))
        #expect(second.contains("/seed-beta"))
        #expect(!second.contains("/seed-alpha"), "直前の seed のキャッシュを使い回さないこと")
    }
}
