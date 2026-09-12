---
id: task-36
difficulty: standard
depends_on: [task-35]
user_visible: true
acceptance_tests:
  - macos/Packages/AgentConfigKit/Tests/AgentConfigKitTests/Acceptance/AcceptanceAgentConsoleNavigationModelTests.swift
baseline_commit: a704d51
contract_tests: []
allowed_paths:
  - macos/Packages/AgentConfigKit/Sources/AgentConfigKit/Shared/AgentConsoleNavigationModel.swift
  - macos/App/AgentConsole/AgentConsoleSection.swift
  - macos/App/AgentConsole/AgentConsoleWindowView.swift
---

## 目的

UX-12。「エージェント管理」で対象エージェントを選び、その対象の項目だけを表示する。
対象名と現在の設定箇所を常時示し、既存19項目と設定の編集経路は失わない。
状態要約・CLI詳細の先頭表示は task-37 の契約。

ADR-0121 の「3 グループを縦に並べる・切替器にしない」決定を、仕様 UX-12（ユーザー承認済み）に基づき置換する。ADR の更新はフェーズ5で PM が行う（実装役の対象外）。

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
  - Colorを返す `AgentConsoleAgent.tint` だけを、元のApp側ファイルのextensionに残す。既存の3色は変更しない。switch 式で `return` を省略した記法も許容する。
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
  - このファイルに `AgentConsoleStatusSummary` は置かない（task-37）。

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

- ナビゲーションの配線（`AgentConsoleWindowView`）:
  - 既存の `selection: AgentConsoleSection?` を選択状態の正本として残す。永続化や、独立したselectedAgent状態は追加しない。
  - `navigation` は `AgentConsoleNavigationModel.make(agent: selection?.agent ?? .claude, selection: selection)`。
  - サイドバー上部に標準のmenu形式Pickerを置く。ラベルは `navigation.agentPickerLabel`、候補は `AgentConsoleAgent.allCases`。
  - `.pickerStyle(.menu)` と `.pickerStyle(MenuPickerStyle())` のどちらも許容する。
  - PickerのBindingはgetで `navigation.agent`、setで `selection = AgentConsoleNavigationModel.make(agent: newAgent, selection: nil).selectedSection`。
  - 対象切替時は必ず切替先の「状態」に移る。初期値はClaude Codeの状態。
  - サイドバーの設定行は `ForEach(navigation.sections)` だけで描く。各行のactionは既存どおり `selection = section`。
  - 各行の選択表示は `navigation.selectedSection == section`。
  - 全agentのagentGroupを順に描く旧ループを削除する。不要になったagentGroup helperも残さない。
  - 設定行の `section.detail` は常時表示の補助文字から外し、行のhelpへ移す。項目titleと既存の選択traitは維持する。`.accessibilityAddTraits` に `.isSelected` を含む条件式を残す。
  - 本文の上に `Text(navigation.locationText)` を常時表示する。状態以外でも現在地が読めること。
  - detailのswitchは `navigation.selectedSection`、messageBarのswitchは `navigation.agent` を使う。既存19caseから既存Paneへの対応と各ConsoleModel引数を維持する。
  - 対象Pickerに `accessibilityIdentifier("agent-console-agent-picker")`、現在地に `"agent-console-location"`、各行に `"agent-console-section-\(section.rawValue)"` を付ける。

- 参照可能性:
  - `macos/Packages/AgentConfigKit/Package.swift:10` に既存のAgentConfigKit・AgentConfigKitTestsターゲットがあり、外部パッケージ依存はない。
  - `macos/project.yml:111` でAppはAgentConfigKitへ直接依存する。
  - WindowViewは既にAgentConfigKitをimportしている。元のAgentConsoleSection.swiftに同importを追加する。
  - 元のenumの製品側参照はAgentConsoleSection.swiftとAgentConsoleWindowView.swiftに限られることを検索で確認した。
  - Appの型をパッケージからimportする逆向き依存を作らない。Package.swift・project.ymlの変更は不要。

- 不変条件:
  - 既存19ペイン、設定の読み書き、CLI呼び出し、reload処理、検出処理、ConsoleModelの寿命・初期化は変更しない。
  - CLI未検出でも3対象と19項目への経路を保つ。既存ペイン個別の無効化条件は維持する。
  - SettingsView の不変検査は task-36 自身の差分で判定する。`TASK36_BASELINE` は task-35 完了後の SHA を PM が固定する（HEAD 自己比較は使わない）。task-36 は SettingsView を変更しない。
  - custom agents.jsonの追加・編集機能は実装しない。管理対象へ架空のcustom設定ペインを追加しない。
  - custom起動定義の読取は `macos/Packages/AgentDomain/Sources/AgentDomain/CustomAgentDefinition.swift:5`、
    カタログへの組み込みは `macos/App/CompositionRoot.swift:209`。この系統は変更しない。
  - WindowView の toolbar 相当操作は持たないが、reload 本文、init 引数と3 ConsoleModel の生成、`.task(id: claudeExecutablePath) { await reload() }`、messageBar の case ごとの error / info / dismiss 対応は固定SHA（`TASK36_BASELINE`）と一致させる。
  - 本草案は未凍結。PMが受け入れテストとRuby検査を作成し、未実装によるredを確認してからbaseline_commitを設定する。
  - acceptance_testsのアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、PMに報告し承認を得たうえでハーネス部分に限り修理してよい。

## 成功基準

1. 凍結テスト `AcceptanceAgentConsoleNavigationModelTests` green。
   agentのrawValueと表示名を ["claude","codex","cursor"] / ["Claude Code","Codex","Cursor"] に固定する。
   3対象の項目ID・title・順序を上記19組のリテラル配列と比較し、和集合19件・重複なしを確認する。ID配列とtitle配列は別々に比較する（タプル配列の `==` は使わない）。
   `section.agent` の19組写像と `AgentConsoleSection.allCases` の順序をリテラル表で固定する。
   3 agent ×（19 selection ＋ nil）＝60組のすべてで、agent・sections（selection 時もその agent の19組該当部分と一致）・selectedSection・locationText を検査する。
   `locationText` の例 `"Claude Code / 権限"`、`"Codex / 信頼設定"`、`"Cursor / モデル"` とPickerラベルを固定する。
   移設するconfigLocation・detail・symbolNameは元コード由来のリテラル表で不変を確認する。
   `AgentConsoleNavigationModel` / `AgentConsoleAgent` / `AgentConsoleSection` は `func requireEquatable<T: Equatable & Sendable>(_: T.Type)` で確認する。
   `~/.agents/scripts/compact-test task36-agent-config bash macos/scripts/run-swift-tests.sh AgentConfigKit` green。
   Appを含む隔離Debugビルド成功。AgentConfigKitのテスト成功だけでApp側のpublic/import/switch配線を検証済みにしない。
   統合時は既存 `.claude/verify.sh` を正本として実行する。

2. 配線検査 `.claude/scripts/task36-wiring.rb` OK。
   PMが凍結し、`~/.agents/scripts/compact-test task36-wiring env TASK36_BASELINE=<task-35完了後SHA> ruby .claude/scripts/task36-wiring.rb` で実行する。`TASK36_BASELINE` は task-35 完了後の SHA を PM が固定する。HEADとの自己比較は使わない。
   文字列リテラルを先にプレースホルダ化したうえで `//` と `/* */` を除去し、括弧・波括弧対応（文字列内の括弧は数えない）で対象本文を抽出して以下を検査する。
   両enumの定義がAgentConfigKit側に1つずつだけ存在する／新設ファイルにSwiftUI・AppKit・Color・View・Observable状態・I/Oがない／App側extensionに既存tintの3写像が残る（`return` 省略の switch 式も許容）。
   navigation.makeが既存selectionから生成される／Pickerのsetが `selection = AgentConsoleNavigationModel.make(agent: newAgent, selection: nil).selectedSection` を代入する／サイドバーがnavigation.sectionsだけを列挙する／独立したselectedAgent状態や旧全グループ表示がない。
   `.pickerStyle(.menu)` または `.pickerStyle(MenuPickerStyle())`。
   行action・選択判定・現在地Text・detail switch・messageBar switchが契約のnavigation/selectionへ接続される。
   `.accessibilityAddTraits` に `.isSelected` を含む条件式が残る。
   detail switchの19case→Pane名→ConsoleModel引数を固定SHAと比較し、同じ項目数だけ残して接続先を取り違える変更も落とす。
   WindowView の reload 本文、init 引数と3 ConsoleModel 生成、`.task(id: claudeExecutablePath) { await reload() }`、messageBar の case ごとの error / info / dismiss 対応を `TASK36_BASELINE` と比較する。
   SettingsView は `TASK36_BASELINE`（task-35 完了後）からの task-36 自身の差分が無いこと。
   HEADとの自己比較は使わない。Rubyの文字列一致だけで表示・到達性を合格にしない。
   `--selftest` で、Picker set の正例・負例、`.isSelected` 条件、`DisclosureGroup(isExpanded:) { } label: { }` 形、`MenuPickerStyle()`、`return` 省略 switch、文字列内 `//` と `/* */` 除去を自己検査する。

3. 隔離 Debug の App ビルド（`xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build`）成功を PM ゲートの必須項目とする。
   PM目視ゲート:
   この変更から作った隔離Debugを専用DerivedData・専用データディレクトリで起動する。
   起動結果のPID・実行ファイルパス・ウィンドウ所有PIDを照合し、自PIDのAXからhelp「エージェント管理」のボタンを取得してAXPressで開く。
   以後も自PIDへのAX取得・AXPress、必要時のみ遮蔽確認付き座標クリックを使用する。キー送信は禁止。
   標準の管理ウィンドウ寸法（初期900×620、最小900×600。`PhloxApp.swift:141`、`AgentConsoleWindowView.swift:65`）で確認する。
   初期表示がClaude Code / 状態で、サイドバーはClaudeの8項目だけであることを撮影する。
   PickerでCodex、Cursorへ順に切り替え、状態へ移ること、行数が6件・5件になること、他agentの行やエラーが混在しないことを確認する。
   Claudeの出力スタイル、Codexの信頼設定、Cursorの設定を含む19項目を順に開き、AXの選択trait・現在地・既存ペインの一致を記録する。設定の保存・削除・CLI更新は実行しない。
   現在地・対象名・末尾の設定行が欠けず、必要な行へスクロールで到達できることを確認する。
   管理画面の既存read-onlyな情報取得を除き、課金セッションの起動・メッセージ送信を要求しない。custom agentは起動せず、agents.json系統の不変性はコード検査で確認する。
   AX取得・展開・撮影できなかった項目は未検証とし、19件の到達性を全数確認したと報告しない。終了時は自分が起動したPIDと子プロセスだけを確認して終了する。

## レビュー観点（Rubric）

- 画面に見える選択肢が対象エージェントに絞られ、対象名と現在の設定箇所が本文から分かる。
- 既存19経路が残り、CLI未検出を理由に設定編集への入口まで消していない。
- 選択状態の正本が既存selectionだけで、Picker・行の強調・本文・エラーバナーが食い違わない。
- 既存enumの移設はテスト可能性と依存方向のための範囲に限定され、別の項目一覧や文字列変換表を増やしていない。
- 設定の保存、権限、秘密情報、CLI実行の既存挙動を変更していない。
- SettingsViewとcustom agents.jsonの系統を、管理画面の改善に巻き込んでいない。
- 標準寸法で対象Pickerと末尾項目へ到達でき、選択trait・操作ラベル・標準フォーカス挙動を維持している。
