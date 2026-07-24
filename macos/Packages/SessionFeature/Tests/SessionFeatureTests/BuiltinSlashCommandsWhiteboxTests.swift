import Testing
@testable import SessionFeature

@Suite("組み込みスラッシュコマンド（task-3）")
struct BuiltinSlashCommandsWhiteboxTests {
    @Test("主要な Claude Code 組み込み管理コマンドを提供する")
    func includesBuiltinManagementCommands() {
        let titles = Set(ComposerSuggestionSources.builtinSlashCommands.map(\.title))

        for command in [
            "/config", "/plugin", "/mcp", "/permissions",
            "/status", "/context", "/cost", "/usage", "/doctor",
            "/memory", "/output-style", "/export", "/review", "/hooks",
        ] {
            #expect(titles.contains(command), "\(command) を組み込み候補に含めること")
        }
    }

    @Test("端末対話専用・削除済みコマンドは候補に含めない")
    func excludesUnsupportedCommands() {
        let titles = Set(ComposerSuggestionSources.builtinSlashCommands.map(\.title))

        #expect(!titles.contains("/vim"))
        #expect(!titles.contains("/terminal-setup"))
        #expect(!titles.contains("/agents"))
    }

    @Test("実行内容に合った説明を提供する")
    func describesCommandsAccurately() {
        let subtitles = Dictionary(
            uniqueKeysWithValues: ComposerSuggestionSources.builtinSlashCommands.map { ($0.title, $0.subtitle) }
        )

        #expect(subtitles["/todos"] == "Clear todo list")
        #expect(subtitles["/review"] == "Review a GitHub pull request")
    }
}
