// task-36（UX-12）の受け入れテスト。ナビゲーションと列挙の移設。
//
// ベースラインでの red 理由: `AgentConsoleNavigationModel` と、
// AgentConfigKit へ移設した public な `AgentConsoleAgent` /
// `AgentConsoleSection` は本タスクが新設・移設を要求する API で、
// baseline_commit の AgentConfigKit には存在しない
// （参照未解決でコンパイル不能＝red）。
//
// 契約: 既存 19 項目の case / rawValue / title / 順序をリテラルで固定し、
// allCases から期待値を生成しない。ファイル・CLI・UserDefaults は読まない。
// 状態要約（AgentConsoleStatusSummary）は task-37 の契約。

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

    private static let agentDisplayNames: [(agent: AgentConsoleAgent, name: String)] = [
        (.claude, "Claude Code"),
        (.codex, "Codex"),
        (.cursor, "Cursor"),
    ]

    private static var allPairIDs: [String] {
        (claudePairs + codexPairs + cursorPairs).map(\.id)
    }

    private static func pairs(for agent: AgentConsoleAgent) -> [(id: String, title: String)] {
        switch agent {
        case .claude: claudePairs
        case .codex: codexPairs
        case .cursor: cursorPairs
        }
    }

    private static func statusID(for agent: AgentConsoleAgent) -> String {
        switch agent {
        case .claude: "claudeStatus"
        case .codex: "codexStatus"
        case .cursor: "cursorStatus"
        }
    }

    private static func title(forSectionID id: String) -> String {
        (claudePairs + codexPairs + cursorPairs).first { $0.id == id }?.title ?? ""
    }

    private static func displayName(for agent: AgentConsoleAgent) -> String {
        agentDisplayNames.first { $0.agent == agent }?.name ?? ""
    }

    private static func expectedSelectedID(agent: AgentConsoleAgent, selection: AgentConsoleSection?) -> String {
        if let selection {
            let belonging = pairs(for: agent).map(\.id)
            if belonging.contains(selection.rawValue) {
                return selection.rawValue
            }
        }
        return statusID(for: agent)
    }

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

        #expect(claude.sections.map(\.rawValue) == Self.claudePairs.map(\.id))
        #expect(claude.sections.map(\.title) == Self.claudePairs.map(\.title))
        #expect(codex.sections.map(\.rawValue) == Self.codexPairs.map(\.id))
        #expect(codex.sections.map(\.title) == Self.codexPairs.map(\.title))
        #expect(cursor.sections.map(\.rawValue) == Self.cursorPairs.map(\.id))
        #expect(cursor.sections.map(\.title) == Self.cursorPairs.map(\.title))

        #expect(claude.sections.count == 8)
        #expect(codex.sections.count == 6)
        #expect(cursor.sections.count == 5)
    }

    @Test("19 項目の和集合は 19 件で重複なし")
    func nineteenSectionUnionIsUnique() {
        let ids = Self.allPairIDs
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

    @Test("section.agent の 19 組写像と allCases 順序を固定する")
    func sectionAgentMappingAndAllCasesOrder() {
        #expect(AgentConsoleSection.allCases.map(\.rawValue) == Self.allPairIDs)
        #expect(AgentConsoleSection.allCases.count == 19)

        for pair in Self.claudePairs {
            let section = AgentConsoleSection.allCases.first { $0.rawValue == pair.id }
            #expect(section != nil, pair.id)
            #expect(section?.agent == .claude, pair.id)
        }
        for pair in Self.codexPairs {
            let section = AgentConsoleSection.allCases.first { $0.rawValue == pair.id }
            #expect(section != nil, pair.id)
            #expect(section?.agent == .codex, pair.id)
        }
        for pair in Self.cursorPairs {
            let section = AgentConsoleSection.allCases.first { $0.rawValue == pair.id }
            #expect(section != nil, pair.id)
            #expect(section?.agent == .cursor, pair.id)
        }

        #expect(AgentConsoleSection.claudeStatus.agent == .claude)
        #expect(AgentConsoleSection.codexTrust.agent == .codex)
        #expect(AgentConsoleSection.cursorModel.agent == .cursor)
    }

    @Test("3 agent × (19 selection + nil) = 60 組で agent・sections・selectedSection・locationText を検査する")
    func sixtyAgentSelectionCombinations() {
        let agents: [AgentConsoleAgent] = [.claude, .codex, .cursor]
        let selections: [AgentConsoleSection?] = AgentConsoleSection.allCases.map { Optional($0) } + [nil]
        #expect(AgentConsoleSection.allCases.count == 19)
        #expect(agents.count * selections.count == 60)

        for agent in agents {
            let expectedPairs = Self.pairs(for: agent)
            for selection in selections {
                let model = AgentConsoleNavigationModel.make(agent: agent, selection: selection)
                #expect(model.agent == agent)
                #expect(model.sections.map(\.rawValue) == expectedPairs.map(\.id))
                #expect(model.sections.map(\.title) == expectedPairs.map(\.title))

                let expectedID = Self.expectedSelectedID(agent: agent, selection: selection)
                #expect(model.selectedSection.rawValue == expectedID)
                #expect(
                    model.locationText
                        == "\(Self.displayName(for: agent)) / \(Self.title(forSectionID: expectedID))"
                )
            }
        }
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

    @Test("NavigationModel・Agent・Section は Equatable & Sendable")
    func modelsAreEquatableAndSendable() {
        requireEquatable(AgentConsoleNavigationModel.self)
        requireEquatable(AgentConsoleAgent.self)
        requireEquatable(AgentConsoleSection.self)
    }
}

private func requireEquatable<T: Equatable & Sendable>(_: T.Type) {}
