// task-3 受け入れテスト（PM 著・不変）。
// アサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、
// PM に報告し承認を得たうえでハーネス部分に限り修理してよい。
//
// 契約の正本: tasks/task-3.md
//
// このファイルは 1.3.2 で凍結した同名の受け入れテストを **差し替える**。
// 旧契約は「/config・/plugin を含む組み込みコマンド一式を静的に載せる」だったが、
// 実測（claude CLI 2.1.220 の system/init が運ぶ slash_commands = 104 件）により
// 旧静的リスト 23 件のうち 13 件がセッションに存在しないことが判明したため、
// 契約を「セッションが実際に受け付ける一覧を正本にする」へ改める（decision-log 参照）。

import Foundation
import Testing
@testable import SessionFeature

/// 実測で claude セッションに **存在しなかった** コマンド（旧静的リストの誤り）。
private let commandsAbsentFromSession = [
    "/help", "/plugin", "/permissions", "/status", "/cost", "/memory",
    "/output-style", "/export", "/statusline", "/todos", "/rewind", "/resume", "/hooks",
]

/// 実測で claude セッションに存在したコマンド（旧静的リストと一致していた分）。
private let commandsPresentInSession = [
    "/compact", "/clear", "/model", "/init", "/config",
    "/mcp", "/context", "/usage", "/doctor", "/review",
]

private func makeEmptyWorkspace() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("phlox-slash-availability-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Suite("Acceptance: スラッシュコマンド補完をセッションの提供一覧に一致させる（task-3）")
struct AcceptanceBuiltinSlashCommandsTests {

    // MARK: - 静的フォールバックの是正

    @Test("フォールバックの静的リストに、セッションに存在しないコマンドを載せない")
    func fallbackDropsCommandsAbsentFromSession() {
        let titles = Set(ComposerSuggestionSources.builtinSlashCommands.map(\.title))

        for command in commandsAbsentFromSession {
            #expect(!titles.contains(command), "\(command) は実セッションに存在しないため候補に載せないこと")
        }
    }

    @Test("フォールバックの静的リストは、実在が確認できたコマンドを載せる")
    func fallbackKeepsCommandsPresentInSession() {
        let titles = Set(ComposerSuggestionSources.builtinSlashCommands.map(\.title))

        for command in commandsPresentInSession {
            #expect(titles.contains(command), "\(command) は実セッションに存在するため候補に残すこと")
        }
    }

    @Test("フォールバック候補は一意で、/ 始まりで、説明を持つ")
    func fallbackCandidatesAreWellFormed() {
        let candidates = ComposerSuggestionSources.builtinSlashCommands
        let titles = candidates.map(\.title)

        #expect(Set(titles).count == titles.count, "タイトルの重複禁止")
        for candidate in candidates {
            #expect(candidate.title.hasPrefix("/"), "\(candidate.title) は / 始まりであること")
            #expect(candidate.insertionText == candidate.title, "挿入テキストはタイトルと一致させること")
            #expect(candidate.subtitle?.isEmpty == false, "\(candidate.title) に説明を付けること")
        }
    }

    // MARK: - セッション由来の一覧を正本にする

    @Test("一覧を渡すと、その名前だけが順序どおり候補になる")
    func availableCommandsBecomeTheSourceOfTruth() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["clear", "compact", "recap"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        #expect(candidates.map(\.title) == ["/clear", "/compact", "/recap"])
        #expect(candidates.map(\.insertionText) == ["/clear", "/compact", "/recap"])
    }

    @Test("一覧に無いコマンドは、静的リストにあっても候補にしない")
    func commandsMissingFromAvailableListAreDropped() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["clear"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        #expect(candidates.map(\.title) == ["/clear"], "静的リストの /compact 等を混ぜ戻さないこと")
    }

    @Test("内部用コマンド（__ 始まり）は候補にしない")
    func internalCommandsAreHidden() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["__remote-workflow", "clear", "__internal"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        #expect(candidates.map(\.title) == ["/clear"], "__ 始まりの内部コマンドをユーザーへ露出しないこと")
    }

    @Test("同じ名前が重複して届いても候補は一意になる")
    func duplicatedNamesCollapse() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["clear", "clear", "compact"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        #expect(candidates.map(\.title) == ["/clear", "/compact"])
    }

    @Test("既知のコマンドには説明が付く")
    func knownCommandsCarryTheirSubtitle() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["compact"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let compact = try #require(candidates.first)
        #expect(compact.title == "/compact")
        #expect(compact.subtitle?.isEmpty == false, "静的リストが持つ説明を引き継ぐこと")
    }

    @Test("スキルの説明は SKILL.md から補われる")
    func skillDescriptionsAreCarriedOver() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }
        let skillDirectory = workspace.appending(path: ".claude/skills/demo-skill", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: skillDirectory, withIntermediateDirectories: true)
        try """
        ---
        name: demo-skill
        description: デモ用のスキル説明
        ---
        """.write(to: skillDirectory.appending(path: "SKILL.md"), atomically: true, encoding: .utf8)

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["demo-skill"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        let skill = try #require(candidates.first)
        #expect(skill.title == "/demo-skill")
        #expect(skill.subtitle == "デモ用のスキル説明", "SKILL.md の description を説明として使うこと")
    }

    // MARK: - 未受領時のフォールバック

    @Test("一覧が未受領（nil）なら静的フォールバックを返す")
    func nilAvailableCommandsFallsBackToStaticList() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let candidates = ComposerSuggestionSources.slashCandidates(
            availableCommands: nil,
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        #expect(candidates.map(\.title) == ComposerSuggestionSources.builtinSlashCommands.map(\.title))
    }

    @Test("同じ作業ディレクトリでも、一覧が違えば違う候補を返す（キャッシュが混線しない）")
    func cacheIsKeyedByAvailableCommands() throws {
        let workspace = try makeEmptyWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let first = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["clear"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )
        let second = ComposerSuggestionSources.slashCandidates(
            availableCommands: ["compact"],
            homeDirectory: workspace,
            workingDirectory: workspace.path
        )

        #expect(first.map(\.title) == ["/clear"])
        #expect(second.map(\.title) == ["/compact"], "直前の一覧のキャッシュを使い回さないこと")
    }
}
