// task-36（UX-12）の受け入れテスト。
//
// ベースラインでの red 理由: `AgentConsoleNavigationModel` /
// `AgentConsoleStatusSummary` と、AgentConfigKit へ移設した public な
// `AgentConsoleAgent` / `AgentConsoleSection` は本タスクが新設・移設を
// 要求する API で、baseline_commit の AgentConfigKit には存在しない
// （参照未解決でコンパイル不能＝red）。
//
// 契約: 既存 19 項目の case / rawValue / title / 順序をリテラルで固定し、
// allCases から期待値を生成しない。ファイル・CLI・UserDefaults は読まない。

import AgentConfigKit
import Testing

@Suite("task-36: agent console navigation model")
struct AcceptanceAgentConsoleNavigationModelTests {
    private static let claudePairs: [(id: String, title: String)] = [
        ("claudeStatus", "状態"),
        ("claudePlugins", "プラグイン"),
        ("claudeSkills", "スキル"),
        ("claudePermissions", "権限"),
        ("claudeMemory", "メモリ"),
        ("claudeHooks", "フック"),
        ("claudeStatusLine", "ステータスライン"),
        ("claudeOutputStyle", "出力スタイル"),
    ]

    private static let codexPairs: [(id: String, title: String)] = [
        ("codexStatus", "状態"),
        ("codexSettings", "設定"),
        ("codexPlugins", "プラグイン"),
        ("codexMCP", "MCP"),
        ("codexMemory", "メモリ"),
        ("codexTrust", "信頼設定"),
    ]

    private static let cursorPairs: [(id: String, title: String)] = [
        ("cursorStatus", "状態"),
        ("cursorPermissions", "権限"),
        ("cursorModel", "モデル"),
        ("cursorMCP", "MCP"),
        ("cursorSettings", "設定"),
    ]

    private static let sectionMeta: [(id: String, title: String, detail: String, symbol: String)] = [
        ("claudeStatus", "状態", "/status", "info.circle"),
        ("claudePlugins", "プラグイン", "/plugin", "puzzlepiece.extension"),
        ("claudeSkills", "スキル", "skills", "books.vertical"),
        ("claudePermissions", "権限", "/permissions", "checkmark.shield"),
        ("claudeMemory", "メモリ", "/memory", "brain"),
        ("claudeHooks", "フック", "/hooks", "link"),
        ("claudeStatusLine", "ステータスライン", "/statusline", "text.line.first.and.arrowtriangle.forward"),
        ("claudeOutputStyle", "出力スタイル", "/output-style", "textformat"),
        ("codexStatus", "状態", "config.toml", "info.circle"),
        ("codexSettings", "設定", "model / sandbox", "slider.horizontal.3"),
        ("codexPlugins", "プラグイン", "codex plugin", "puzzlepiece.extension"),
        ("codexMCP", "MCP", "codex mcp", "server.rack"),
        ("codexMemory", "メモリ", "AGENTS.md", "brain"),
        ("codexTrust", "信頼設定", "[projects]", "folder.badge.person.crop"),
        ("cursorStatus", "状態", "cli-config.json", "info.circle"),
        ("cursorPermissions", "権限", "permissions", "checkmark.shield"),
        ("cursorModel", "モデル", "model", "cpu"),
        ("cursorMCP", "MCP", "mcp.json", "server.rack"),
        ("cursorSettings", "設定", "display / git", "slider.horizontal.3"),
    ]

    @Test("agent の rawValue と表示名を固定する")
    func agentRawValuesAndDisplayNames() {
        #expect(AgentConsoleAgent.allCases.map(\.rawValue) == ["claude", "codex", "cursor"])
        #expect(AgentConsoleAgent.allCases.map(\.displayName) == ["Claude Code", "Codex", "Cursor"])
        #expect(AgentConsoleAgent.claude.rawValue == "claude")
        #expect(AgentConsoleAgent.codex.rawValue == "codex")
        #expect(AgentConsoleAgent.cursor.rawValue == "cursor")
        #expect(AgentConsoleAgent.claude.displayName == "Claude Code")
        #expect(AgentConsoleAgent.codex.displayName == "Codex")
        #expect(AgentConsoleAgent.cursor.displayName == "Cursor")
    }

    @Test("3 対象の項目 ID・title・順序を 19 組のリテラル配列と比較する")
    func nineteenSectionIDsAndTitlesMatchLiterals() {
        let claude = AgentConsoleNavigationModel.make(agent: .claude, selection: nil)
        let codex = AgentConsoleNavigationModel.make(agent: .codex, selection: nil)
        let cursor = AgentConsoleNavigationModel.make(agent: .cursor, selection: nil)

        #expect(claude.sections.map { ($0.rawValue, $0.title) } == Self.claudePairs.map { ($0.id, $0.title) })
        #expect(codex.sections.map { ($0.rawValue, $0.title) } == Self.codexPairs.map { ($0.id, $0.title) })
        #expect(cursor.sections.map { ($0.rawValue, $0.title) } == Self.cursorPairs.map { ($0.id, $0.title) })

        #expect(claude.sections.count == 8)
        #expect(codex.sections.count == 6)
        #expect(cursor.sections.count == 5)
    }

    @Test("19 項目の和集合は 19 件で重複なし")
    func nineteenSectionUnionIsUnique() {
        let ids = (Self.claudePairs + Self.codexPairs + Self.cursorPairs).map(\.id)
        #expect(ids.count == 19)
        #expect(Set(ids).count == 19)

        let claude = AgentConsoleNavigationModel.make(agent: .claude, selection: nil)
        let codex = AgentConsoleNavigationModel.make(agent: .codex, selection: nil)
        let cursor = AgentConsoleNavigationModel.make(agent: .cursor, selection: nil)
        let got = claude.sections.map(\.rawValue)
            + codex.sections.map(\.rawValue)
            + cursor.sections.map(\.rawValue)
        #expect(got == ids)
        #expect(Set(got).count == 19)
    }

    @Test("selection=nil なら各 agent の状態項目になる")
    func nilSelectionResolvesToStatus() {
        let claude = AgentConsoleNavigationModel.make(agent: .claude, selection: nil)
        let codex = AgentConsoleNavigationModel.make(agent: .codex, selection: nil)
        let cursor = AgentConsoleNavigationModel.make(agent: .cursor, selection: nil)

        #expect(claude.selectedSection == .claudeStatus)
        #expect(codex.selectedSection == .codexStatus)
        #expect(cursor.selectedSection == .cursorStatus)
        #expect(claude.agent == .claude)
        #expect(codex.agent == .codex)
        #expect(cursor.agent == .cursor)
    }

    @Test("所属する各項目を渡すとそのまま保持する")
    func belongingSelectionIsKept() {
        let claudeKeep: [AgentConsoleSection] = [
            .claudeStatus, .claudePlugins, .claudeSkills, .claudePermissions,
            .claudeMemory, .claudeHooks, .claudeStatusLine, .claudeOutputStyle,
        ]
        let codexKeep: [AgentConsoleSection] = [
            .codexStatus, .codexSettings, .codexPlugins, .codexMCP, .codexMemory, .codexTrust,
        ]
        let cursorKeep: [AgentConsoleSection] = [
            .cursorStatus, .cursorPermissions, .cursorModel, .cursorMCP, .cursorSettings,
        ]

        for section in claudeKeep {
            let model = AgentConsoleNavigationModel.make(agent: .claude, selection: section)
            #expect(model.selectedSection == section)
            #expect(model.agent == .claude)
        }
        for section in codexKeep {
            let model = AgentConsoleNavigationModel.make(agent: .codex, selection: section)
            #expect(model.selectedSection == section)
            #expect(model.agent == .codex)
        }
        for section in cursorKeep {
            let model = AgentConsoleNavigationModel.make(agent: .cursor, selection: section)
            #expect(model.selectedSection == section)
            #expect(model.agent == .cursor)
        }
    }

    @Test("他 agent 所属の selection は状態へ戻る")
    func foreignSelectionResetsToStatus() {
        #expect(
            AgentConsoleNavigationModel.make(agent: .claude, selection: .codexTrust).selectedSection
                == .claudeStatus
        )
        #expect(
            AgentConsoleNavigationModel.make(agent: .claude, selection: .cursorModel).selectedSection
                == .claudeStatus
        )
        #expect(
            AgentConsoleNavigationModel.make(agent: .codex, selection: .claudePermissions).selectedSection
                == .codexStatus
        )
        #expect(
            AgentConsoleNavigationModel.make(agent: .codex, selection: .cursorSettings).selectedSection
                == .codexStatus
        )
        #expect(
            AgentConsoleNavigationModel.make(agent: .cursor, selection: .claudeOutputStyle).selectedSection
                == .cursorStatus
        )
        #expect(
            AgentConsoleNavigationModel.make(agent: .cursor, selection: .codexMCP).selectedSection
                == .cursorStatus
        )
    }

    @Test("locationText の例と Picker ラベルを固定する")
    func locationTextExamplesAndPickerLabel() {
        let permissions = AgentConsoleNavigationModel.make(agent: .claude, selection: .claudePermissions)
        #expect(permissions.locationText == "Claude Code / 権限")
        #expect(permissions.agentPickerLabel == "対象エージェント")

        let trust = AgentConsoleNavigationModel.make(agent: .codex, selection: .codexTrust)
        #expect(trust.locationText == "Codex / 信頼設定")
        #expect(trust.agentPickerLabel == "対象エージェント")

        let model = AgentConsoleNavigationModel.make(agent: .cursor, selection: .cursorModel)
        #expect(model.locationText == "Cursor / モデル")
        #expect(model.agentPickerLabel == "対象エージェント")

        let claudeStatus = AgentConsoleNavigationModel.make(agent: .claude, selection: nil)
        #expect(claudeStatus.locationText == "Claude Code / 状態")
        #expect(claudeStatus.agentPickerLabel == "対象エージェント")
    }

    @Test("configLocation・detail・symbolName を元コード由来のリテラル表で固定する")
    func configLocationDetailAndSymbolNames() {
        #expect(AgentConsoleAgent.claude.configLocation == "~/.claude/settings.json")
        #expect(AgentConsoleAgent.codex.configLocation == "~/.codex/config.toml")
        #expect(AgentConsoleAgent.cursor.configLocation == "~/.cursor/cli-config.json")

        #expect(AgentConsoleAgent.claude.symbolName == "sparkles")
        #expect(AgentConsoleAgent.codex.symbolName == "chevron.left.forwardslash.chevron.right")
        #expect(AgentConsoleAgent.cursor.symbolName == "cursorarrow.rays")

        let byID: [String: AgentConsoleSection] = Dictionary(
            uniqueKeysWithValues: AgentConsoleSection.allCases.map { ($0.rawValue, $0) }
        )
        #expect(byID.count == 19)

        for row in Self.sectionMeta {
            let section = byID[row.id]
            #expect(section != nil, row.id)
            #expect(section?.rawValue == row.id)
            #expect(section?.title == row.title, row.id)
            #expect(section?.detail == row.detail, row.id)
            #expect(section?.symbolName == row.symbol, row.id)
        }
    }

    @Test("StatusSummary の Bool 2 入力 4 組で 4 つの表示フィールドと CLI 詳細ラベルをリテラル比較する")
    func statusSummaryFourCombinations() {
        let bothTrue = AgentConsoleStatusSummary.make(isAvailable: true, configFileExists: true)
        #expect(bothTrue.availabilityText == "CLI を検出済み")
        #expect(bothTrue.availabilityDetail == "認証・通信の状態は未確認です")
        #expect(bothTrue.configurationText == "設定ファイルあり")
        #expect(bothTrue.configurationDetail == nil)
        #expect(bothTrue.cliDetailsTitle == "CLI の詳細")

        let cliOnly = AgentConsoleStatusSummary.make(isAvailable: true, configFileExists: false)
        #expect(cliOnly.availabilityText == "CLI を検出済み")
        #expect(cliOnly.availabilityDetail == "認証・通信の状態は未確認です")
        #expect(cliOnly.configurationText == "設定ファイル未作成")
        #expect(cliOnly.configurationDetail == "必要な設定は左の項目から変更できます")
        #expect(cliOnly.cliDetailsTitle == "CLI の詳細")

        let fileOnly = AgentConsoleStatusSummary.make(isAvailable: false, configFileExists: true)
        #expect(fileOnly.availabilityText == "CLI を検出できていません")
        #expect(fileOnly.availabilityDetail == "インストール先と PATH を確認してください")
        #expect(fileOnly.configurationText == "設定ファイルあり")
        #expect(fileOnly.configurationDetail == nil)
        #expect(fileOnly.cliDetailsTitle == "CLI の詳細")

        let bothFalse = AgentConsoleStatusSummary.make(isAvailable: false, configFileExists: false)
        #expect(bothFalse.availabilityText == "CLI を検出できていません")
        #expect(bothFalse.availabilityDetail == "インストール先と PATH を確認してください")
        #expect(bothFalse.configurationText == "設定ファイル未作成")
        #expect(bothFalse.configurationDetail == "必要な設定は左の項目から変更できます")
        #expect(bothFalse.cliDetailsTitle == "CLI の詳細")
    }
}
