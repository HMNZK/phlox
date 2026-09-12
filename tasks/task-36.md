---
id: task-36
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/AgentConfigKit/Tests/AgentConfigKitTests/Acceptance/AcceptanceAgentConsoleNavigationModelTests.swift
baseline_commit: 18bbcc4
contract_tests: []
allowed_paths:
  - macos/Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleNavigationModel.swift
  - macos/App/AgentConsole/AgentConsoleSection.swift
  - macos/App/AgentConsole/AgentConsoleWindowView.swift
  - macos/App/AgentConsole/Claude/ClaudeStatusPane.swift
  - macos/App/AgentConsole/Codex/CodexStatusPane.swift
  - macos/App/AgentConsole/Cursor/CursorStatusPane.swift
---

## 目的

UX-12。「エージェント管理」で対象エージェントを選び、その対象の項目だけを表示する。
対象名と現在の設定箇所を常時示し、状態ペインではCLIの検出状況と設定ファイルの有無を先に見せる。
バージョン・実行ファイルパスは初回表示で折りたたみ、必要時に確認できるようにする。
既存19項目と設定の編集経路は失わない。

仕様の観察・改善案・完了条件は `macos/docs/specs/ui-ux-improvement-backlog.md:136`。
対象はSettingsViewではなく、help「エージェント管理」のボタン
（`macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardTopBarControls.swift:39`）が開く
`macos/App/PhloxApp.swift:131` の `AgentConsoleWindowView`。
現在の全対象同時表示は `macos/App/AgentConsole/AgentConsoleWindowView.swift:78`、
19項目の宣言と分類は `macos/App/AgentConsole/AgentConsoleSection.swift:48,74,146`。

## 入出力契約

- 既存の列挙を再利用するための限定的な移設:
  - `AgentConsoleAgent` と `AgentConsoleSection` のSwiftUI非依存部分を、新設 `AgentConsoleNavigationModel.swift` に移す。
  - AgentConfigKitからAppへ公開するため、両enumと利用されるプロパティ・関数をpublicにする。Equatable・Hashable・Sendableとして扱える値型とする。
  - case、rawValue、allCasesの順序、agentへの写像、displayName、configLocation、title、detail、symbolName、sections(for:)は保持する。
  - Colorを返す `AgentConsoleAgent.tint` だけを、元のApp側ファイルのextensionに残す。既存の3色は変更しない。
  - App側に同名enumや別の項目一覧を残さない。文字列IDから元のenumへ戻す変換表も作らない。

- 新設 `AgentConsoleNavigationModel`（public struct、Equatable、Sendable、SwiftUI・AppKit非依存）:
  - `public static func make(agent: AgentConsoleAgent, selection: AgentConsoleSection?) -> AgentConsoleNavigationModel`
  - `agent: AgentConsoleAgent` = 入力agent。
  - `sections: [AgentConsoleSection]` = 既存 `AgentConsoleSection.sections(for: agent)`。CLI未検出でも項目を減らさない。
  - `selectedSection: AgentConsoleSection`:
    - selectionが入力agent所属なら、そのselection。
    - nilまたは他agent所属なら、そのagentの状態項目。
  - `locationText: String` = `"\(agent.displayName) / \(selectedSection.title)"`。区切りは半角スペース・ASCIIスラッシュ・半角スペース。
  - `agentPickerLabel: String` = `"対象エージェント"`。
  - ファイルアクセス、CLI呼び出し、UserDefaults、状態保存を行わない。

- 凍結する項目集合と順序:
  - Claude Code:
    - claudeStatus / 状態
    - claudePlugins / プラグイン
    - claudeSkills / スキル
    - claudePermissions / 権限
    - claudeMemory / メモリ
    - claudeHooks / フック
    - claudeStatusLine / ステータスライン
    - claudeOutputStyle / 出力スタイル
  - Codex:
    - codexStatus / 状態
    - codexSettings / 設定
    - codexPlugins / プラグイン
    - codexMCP / MCP
    - codexMemory / メモリ
    - codexTrust / 信頼設定
  - Cursor:
    - cursorStatus / 状態
    - cursorPermissions / 権限
    - cursorModel / モデル
    - cursorMCP / MCP
    - cursorSettings / 設定
  - 根拠は `macos/App/AgentConsole/AgentConsoleSection.swift:48,86`。8+6+5の19件を固定し、期待値をallCasesから生成しない。

- 同じ新設ファイルに `AgentConsoleStatusSummary`（public struct、Equatable、Sendable、SwiftUI・AppKit非依存）:
  - `public static func make(isAvailable: Bool, configFileExists: Bool) -> AgentConsoleStatusSummary`
  - `availabilityText: String`:
    - true = `"CLI を検出済み"`。
    - false = `"CLI を検出できていません"`。
  - `availabilityDetail: String`:
    - true = `"認証・通信の状態は未確認です"`。
    - false = `"インストール先と PATH を確認してください"`。
  - `configurationText: String`:
    - true = `"設定ファイルあり"`。
    - false = `"設定ファイル未作成"`。
  - `configurationDetail: String?`:
    - true = nil。
    - false = `"必要な設定は左の項目から変更できます"`。
  - `cliDetailsTitle: String` = `"CLI の詳細"`。
  - CLIパスが見つかっただけで「認証済み」「利用可能」と断定しない。設定ファイル未作成だけで異常・編集不可にしない。

- ナビゲーションの配線（`AgentConsoleWindowView`）:
  - 既存の `selection: AgentConsoleSection?` を選択状態の正本として残す。永続化や、独立したselectedAgent状態は追加しない。
  - `navigation` は `AgentConsoleNavigationModel.make(agent: selection?.agent ?? .claude, selection: selection)`。
  - サイドバー上部に標準のmenu形式Pickerを置く。ラベルは `navigation.agentPickerLabel`、候補は `AgentConsoleAgent.allCases`。
  - PickerのBindingはgetで `navigation.agent`、setで `selection = AgentConsoleNavigationModel.make(agent: newAgent, selection: nil).selectedSection`。
  - 対象切替時は必ず切替先の「状態」に移る。初期値はClaude Codeの状態。
  - サイドバーの設定行は `ForEach(navigation.sections)` だけで描く。各行のactionは既存どおり `selection = section`。
  - 各行の選択表示は `navigation.selectedSection == section`。
  - 全agentのagentGroupを順に描く旧ループを削除する。不要になったagentGroup helperも残さない。
  - 設定行の `section.detail` は常時表示の補助文字から外し、行のhelpへ移す。項目titleと既存の選択traitは維持する。
  - 本文の上に `Text(navigation.locationText)` を常時表示する。状態以外でも現在地が読めること。
  - detailのswitchは `navigation.selectedSection`、messageBarのswitchは `navigation.agent` を使う。既存19caseから既存Paneへの対応と各ConsoleModel引数を維持する。
  - 対象Pickerに `accessibilityIdentifier("agent-console-agent-picker")`、現在地に `"agent-console-location"`、各行に `"agent-console-section-\(section.rawValue)"` を付ける。

- 状態ペインの配線:
  - Claude: `AgentConsoleStatusSummary.make(isAvailable: model.isClaudeAvailable, configFileExists: model.status.settingsFileExists)`。
  - Codex/Cursor: `AgentConsoleStatusSummary.make(isAvailable: model.isAvailable, configFileExists: model.status.configFileExists)`。
  - 検出フラグの根拠は `macos/App/AgentConsole/Claude/ClaudeConsoleModel.swift:52`、`Codex/CodexConsoleModel.swift:49`、`Cursor/CursorConsoleModel.swift:43`。
  - 各状態ペインの本文先頭にsummaryのavailabilityText/detail、configurationText/detailを表示する。その後に既存の集計・設定・メモリ等を置く。
  - 既存の「CLI」節の2行を、標準DisclosureGroupへ移す。ラベルはsummary.cliDetailsTitle。
  - 各状態ペインに `@State private var showsCLIDetails = false` を置き、DisclosureGroupのisExpandedへ接続する。初回表示は閉じる。
  - 展開内容は既存のバージョンと実行ファイルパスをそのまま使う。未取得バージョンの `"—"`、コピー可能なパス表示を維持する。
  - 元の所在は `Claude/ClaudeStatusPane.swift:18`、`Codex/CodexStatusPane.swift:18`、`Cursor/CursorStatusPane.swift:18`。
  - 設定値、件数タイル、メモリ一覧、設定ファイルをFinderで表示する操作、再読み込み、Cursorの認証情報を表示しない説明を残す。
  - 既存messageBarのエラー・操作結果は折りたたまない。ファイル存在やCLI検出の表示で、読み込みエラーを成功扱いにしない。

- 参照可能性:
  - `macos/Packages/AgentConfigKit/Package.swift:10` に既存のAgentConfigKit・AgentConfigKitTestsターゲットがあり、外部パッケージ依存はない。
  - `macos/project.yml:111` でAppはAgentConfigKitへ直接依存する。
  - WindowViewと3状態ペインは既にAgentConfigKitをimportしている。元のAgentConsoleSection.swiftに同importを追加する。
  - 元のenumの製品側参照はAgentConsoleSection.swiftとAgentConsoleWindowView.swiftに限られることを検索で確認した。
  - Appの型をパッケージからimportする逆向き依存を作らない。Package.swift・project.ymlの変更は不要。

- 不変条件:
  - 既存19ペイン、設定の読み書き、CLI呼び出し、reload処理、検出処理、ConsoleModelの寿命・初期化は変更しない。
  - CLI未検出でも3対象と19項目への経路を保つ。既存ペイン個別の無効化条件は維持する。
  - `macos/App/SettingsView.swift` は変更しない。
  - custom agents.jsonの追加・編集機能は実装しない。管理対象へ架空のcustom設定ペインを追加しない。
  - custom起動定義の読取は `macos/Packages/AgentDomain/Sources/AgentDomain/CustomAgentDefinition.swift:5`、
    カタログへの組み込みは `macos/App/CompositionRoot.swift:209`。この系統は変更しない。
  - 本草案は未凍結。PMが受け入れテストとRuby検査を作成し、未実装によるredを確認してからbaseline_commitを設定する。
  - acceptance_testsのアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、PMに報告し承認を得たうえでハーネス部分に限り修理してよい。

## 成功基準

1. 凍結テスト `AcceptanceAgentConsoleNavigationModelTests` green。
   agentのrawValueと表示名を ["claude","codex","cursor"] / ["Claude Code","Codex","Cursor"] に固定する。
   3対象の項目ID・title・順序を上記19組のリテラル配列と比較し、和集合19件・重複なしを確認する。
   各agentでselection=nilなら対応する状態項目、所属する各項目ならそのまま保持、他agent所属なら状態へ戻ることを確認する。
   `locationText` の例 `"Claude Code / 権限"`、`"Codex / 信頼設定"`、`"Cursor / モデル"` とPickerラベルを固定する。
   移設するconfigLocation・detail・symbolNameは元コード由来のリテラル表で不変を確認する。
   StatusSummaryのBool2入力の4組すべてで、4つの表示フィールドとCLI詳細ラベルをリテラル比較する。
   `~/.agents/scripts/compact-test task36-agent-config bash macos/scripts/run-swift-tests.sh AgentConfigKit` green。
   Appを含む隔離Debugビルド成功。AgentConfigKitのテスト成功だけでApp側のpublic/import/switch配線を検証済みにしない。
   統合時は既存 `.claude/verify.sh` を正本として実行する。

2. 配線検査 `.claude/scripts/task36-wiring.rb` OK。
   PMが凍結し、`~/.agents/scripts/compact-test task36-wiring env TASK36_BASELINE=<凍結SHA> ruby .claude/scripts/task36-wiring.rb` で実行する。
   コメントを除去し、括弧・波括弧対応で対象本文を抽出して以下を検査する。
   両enumの定義がAgentConfigKit側に1つずつだけ存在する／新設ファイルにSwiftUI・AppKit・Color・View・Observable状態・I/Oがない／App側extensionに既存tintの3写像が残る。
   navigation.makeが既存selectionから生成される／Pickerのsetが新agentとnil selectionでmakeを呼ぶ／サイドバーがnavigation.sectionsだけを列挙する／独立したselectedAgent状態や旧全グループ表示がない。
   行action・選択判定・現在地Text・detail switch・messageBar switchが契約のnavigation/selectionへ接続される。
   detail switchの19case→Pane名→ConsoleModel引数を固定SHAと比較し、同じ項目数だけ残して接続先を取り違える変更も落とす。
   3状態ペインごとにStatusSummary.makeの実引数、summaryの先頭表示、showsCLIDetails=false、DisclosureGroupのbinding、展開内部のバージョンとパス2行を検査する。
   旧CLI2行がDisclosureGroupの外にも残る二重表示を落とす。
   既存設定行・summaryTiles・メモリ・toolbar・Cursorの認証情報説明、WindowViewのreload・init・messageBarのエラー表示が固定SHAから欠落・変更していないことを検査する。
   HEADとの自己比較は使わない。Rubyの文字列一致だけで表示・到達性を合格にしない。

3. PM目視ゲート:
   この変更から作った隔離Debugを専用DerivedData・専用データディレクトリで起動する。
   起動結果のPID・実行ファイルパス・ウィンドウ所有PIDを照合し、自PIDのAXからhelp「エージェント管理」のボタンを取得してAXPressで開く。
   以後も自PIDへのAX取得・AXPress、必要時のみ遮蔽確認付き座標クリックを使用する。キー送信は禁止。
   標準の管理ウィンドウ寸法（初期900×620、最小900×600。`PhloxApp.swift:141`、`AgentConsoleWindowView.swift:65`）で確認する。
   初期表示がClaude Code / 状態で、サイドバーはClaudeの8項目だけ、状態本文の先頭に検出状況・設定ファイルの有無が表示されることを撮影する。
   PickerでCodex、Cursorへ順に切り替え、状態へ移ること、行数が6件・5件になること、他agentの行やエラーが混在しないことを確認する。
   Claudeの出力スタイル、Codexの信頼設定、Cursorの設定を含む19項目を順に開き、AXの選択trait・現在地・既存ペインの一致を記録する。設定の保存・削除・CLI更新は実行しない。
   各対象の状態に戻り、初回のCLI詳細が閉じていること、AXPressで開くと実際のバージョンと実行ファイルパスが確認でき、閉じても検出状況と設定情報は残ることを撮影する。
   長いパスは既存の省略表示とコピー経路が残ることを確認する。現在地・対象名・末尾の設定行が欠けず、必要な行へスクロールで到達できることを確認する。
   CLI検出・未検出と設定ファイル有無の4組は凍結テストで検査し、GUIでは実環境で観測した状態を記録する。負例を作るために利用者のCLIや設定ファイルを削除・変更しない。
   管理画面の既存read-onlyな情報取得を除き、課金セッションの起動・メッセージ送信を要求しない。custom agentは起動せず、agents.json系統の不変性はコード検査で確認する。
   `PHLOX_DATA_DIR`はCLI設定ホームを隔離しない（`AgentConfigKit/Sources/AgentConfigKit/Claude/ClaudeConfigPaths.swift:12`）。管理画面から設定を書き換えず、隔離済みと誤記しない。
   AX取得・展開・撮影できなかった項目は未検証とし、19件の到達性を全数確認したと報告しない。終了時は自分が起動したPIDと子プロセスだけを確認して終了する。

## レビュー観点（Rubric）

- 画面に見える選択肢が対象エージェントに絞られ、対象名と現在の設定箇所が本文から分かる。
- 既存19経路が残り、CLI未検出を理由に設定編集への入口まで消していない。
- 選択状態の正本が既存selectionだけで、Picker・行の強調・本文・エラーバナーが食い違わない。
- 既存enumの移設はテスト可能性と依存方向のための範囲に限定され、別の項目一覧や文字列変換表を増やしていない。
- CLI検出を認証・通信成功と混同せず、設定ファイル未作成を無条件の異常として扱っていない。
- 技術情報を削除せず、CLI詳細の展開から確認できる。既存エラーは折りたたまれない。
- 設定の保存、権限、秘密情報、CLI実行の既存挙動を変更していない。
- SettingsViewとcustom agents.jsonの系統を、管理画面の改善に巻き込んでいない。
- 標準寸法で対象Pickerと末尾項目へ到達でき、選択trait・操作ラベル・標準フォーカス挙動を維持している。
