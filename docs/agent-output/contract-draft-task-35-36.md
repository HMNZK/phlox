## 調査結果

2件の契約草案を以下に示します。ファイル変更、テスト実行、ビルド、GUI検証は行っていません。

- UI-06: `macos/App/SettingsView.swift:77,383,490`。テーマ行の見本は背景・ANSI 6色・前景の色帯です。
- 配色: `macos/Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift:64,83,200`。アプリ用の背景・文字はグレー化され、ターミナル用RGBとは別です。
- 選択行は `macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift:102,157`、入力欄は `macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift:117` と `GridChatColumn.swift:281`。背景に白4%を重ね、枠は `Tokens.swift:138` です。
- UX-12: `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardTopBarControls.swift:39` → `macos/App/PhloxApp.swift:131` → `AgentConsoleWindowView`。3エージェント・19項目を同時表示しています（`macos/App/AgentConsole/AgentConsoleSection.swift:48`）。
- CLI情報は `macos/App/AgentConsole/Claude/ClaudeStatusPane.swift:18`、`Codex/CodexStatusPane.swift:18`、`Cursor/CursorStatusPane.swift:18`。設定・集計情報も各状態ペインにあります。
- custom定義は `macos/Packages/AgentDomain/Sources/AgentDomain/CustomAgentDefinition.swift:5` → `macos/App/CompositionRoot.swift:209` の起動カタログ系統で、管理画面の固定3対象とは別です。
- 既存テストは `AppThemeTests.swift:5`、`ThemeStoreTests.swift:13`、`AcceptanceComposerBorderContrastTests.swift:95`、`ClaudeMemoryAndStatusTests.swift:44`、`CodexSettingsTests.swift:23`、`CursorSettingsTests.swift:32`。今回の見本・管理画面の分類を直接守るテストは、検索した範囲では見つかりませんでした。
- 探索中の推定パス不存在と、一時ファイル作成を伴う読み取りの拒否は、実在パスと一時ファイル不要の読み取り方法に切り替えました。

## tasks/task-35.md

```markdown
---
id: task-35
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceThemePreviewModelTests.swift
baseline_commit: TBD
contract_tests: []
allowed_paths:
  - macos/Packages/DesignSystem/Sources/DesignSystem/ThemePreviewModel.swift
  - macos/App/SettingsView.swift
---

## 目的

UI-06。テーマ一覧の色帯だけでは、適用後のアプリ外観を判断できない。
背景・本文・現在の会話行・入力欄を含む小さな見本と、用途を明記したターミナル配色の色帯を並べる。
新しいテーマや配色規則は追加しない。

仕様の観察・改善案・完了条件は `macos/docs/specs/ui-ux-improvement-backlog.md:169`。
現在の描画は `macos/App/SettingsView.swift:383,490`。
アプリ用RGBとターミナル用RGBは `macos/Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift:64,83` で別々に保持され、
アプリ用のグレー化は同ファイル `:200` で行われる。

## 入出力契約

- 新設 `ThemePreviewModel`（`ThemePreviewModel.swift`、public struct、Equatable、Sendable）:
  - SwiftUI・AppKitをimportしない。公開値は既存の `RGB`、String、Double、配列、以下の純粋値型だけとし、Color・View・ColorSchemeを保持しない。
  - `public struct Layer: Equatable, Sendable { public let rgb: RGB; public let opacity: Double }`
  - `public static func make(theme: AppTheme) -> ThemePreviewModel`
  - `themeID: String` = `theme.id`。
  - `themeName: String` = `theme.name`。
  - `appLabel: String` = `"アプリ外観"`。
  - `terminalLabel: String` = `"ターミナル配色"`。
  - `bodyText: String` = `"本文の見本"`。
  - `selectedRowText: String` = `"現在の会話"`。
  - `inputText: String` = `"メッセージを入力"`。
  - `background: RGB` = `theme.background`。
  - `textPrimary: RGB` = `theme.textPrimary`。
  - `currentMarker: RGB` = `theme.accent`。
  - `selectedRow: Layer` = `Layer(rgb: theme.textPrimary, opacity: AppTheme.sidebarSelectedOpacity)`。
  - `inputFill: Layer` = `Layer(rgb: RGB(255, 255, 255), opacity: 0.04)`。
  - `inputBorder: Layer`:
    - `theme.background.relativeLuminance >= 0.5` なら `Layer(rgb: theme.textPrimary, opacity: 0.86)`。
    - それ以外は `Layer(rgb: RGB(255, 255, 255), opacity: 0.06)`。
    - 既存の `AppTheme.preferredColorScheme` と同じ輝度判定を、既存のRGB計算で行う。SwiftUIの型は使わない。
  - `terminalSwatches: [RGB]` = `[theme.terminalBackground] + Array(theme.ansi[1...6]) + [theme.terminalForeground]`。
  - 事前条件: 入力は製品が登録しているAppThemeで、ANSI配列は16色。任意長のパレット編集機能は扱わない。
  - ThemeStore.active、UserDefaults、ファイル、プロセス、グローバルな選択状態を参照・変更しない。渡された候補テーマだけから決定する。

- 配色対応の根拠:
  - 選択行は `macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift:102,157` の「主文字色を10%重ねる」描画に対応する。不透明な事前合成色へ置き換えない。
  - 入力欄は `macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift:117` と `GridChatColumn.swift:281` の「chatBackgroundに白4%を重ねる」描画に対応する。
  - 入力欄の枠は `macos/Packages/DesignSystem/Sources/DesignSystem/Tokens.swift:138` の明色86%・暗色白6%に対応する。
  - 輝度判定の正本は `macos/Packages/DesignSystem/Sources/DesignSystem/AppTheme.swift:87`。
  - これらは既存描画の写像であり、新しい配色仕様ではない。配線検査で製品側のレシピとの一致を固定する。

- 配線（`SettingsView`）:
  - `ThemeRowView` の候補ごとに `ThemePreviewModel.make(theme: theme)` を呼ぶ。
  - 既存の `Button(action: onSelect)` のラベル内に、テーマ名、アプリ外観の見本、ターミナル配色の色帯、既存の選択チェックを配置する。
  - アプリ見本は `ThemeAppPreview(model:)`、色帯は `ThemeSwatchStrip(model:)` とし、両方を同じmodelで描く。新しいViewはSettingsView.swift内に置く。
  - アプリ見本は不透明な `model.background.color` を下地とし、`model.textPrimary.color` の本文、`model.selectedRow` を重ねた現在の会話行、`model.inputFill` と `model.inputBorder` を重ねた入力欄を描く。
  - 現在の会話行は本文より太くし、leading側に `model.currentMarker.color` の小さなマーカーを出す。既存UI-08の「現在の会話」という意味を保つ。
  - 各Layerは `.rgb.color.opacity(.opacity)` で適用する。入力欄にも不透明なmodel.backgroundの下地を敷き、設定行のhover・選択色が透け込まないようにする。
  - `Text(model.appLabel)` と `Text(model.terminalLabel)` を実際に表示する。用途をhelpだけに隠さない。
  - 色帯は `model.terminalSwatches` の順に描く。アプリ見本にterminalBackgroundやANSI色を背景色として流用しない。
  - 見本の入力欄はTextと図形で描き、TextFieldやTextEditorにはしない。テーマ選択Button内に別の操作を入れない。
  - テーマ名・選択状態がAXから分かること。見本を別のフォーカス対象にせず、色帯の各矩形を独立した操作として読み上げさせない。
  - 候補見本内の色はmodel由来に限定する。見本の外側の説明・テーマ名・選択チェックは既存DSColorの使用を維持してよい。

- 参照可能性:
  - `macos/App/SettingsView.swift:5` は既にDesignSystemをimportしている。
  - `macos/Packages/DesignSystem/Package.swift:14,19` はSourcesとDesignSystemTestsを既存ターゲットとして持つ。
  - 新しいモデルとその公開プロパティをpublicにすれば、Appから参照できる。Package.swift・project.ymlの変更は不要。

- 不変条件:
  - ThemeStore.allの10テーマ、順序、ID、テーマRGB、テーマ保存キー、選択時の `themeID = theme.id` を変更しない（`AppTheme.swift:424`、`SettingsView.swift:77`）。
  - テーマ適用やターミナルへの反映処理を変更しない。ターミナル側の写像は `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift:656`。
  - 設定画面の他の項目・操作・保存処理を欠落させない。
  - 本草案は未凍結。テストとRuby検査はPMが作成し、未実装を原因とするredを確認してからbaseline_commitを設定する。実装役のallowed_pathsにテスト・検証スクリプトを含めない。
  - acceptance_testsのアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、PMに報告し承認を得たうえでハーネス部分に限り修理してよい。

## 成功基準

1. 凍結テスト `AcceptanceThemePreviewModelTests` green。
   Phloxでbackground=(17,17,17)、textPrimary=(230,230,230)、selectedRow=((230,230,230),0.10)、inputFill=((255,255,255),0.04)、inputBorder=((255,255,255),0.06)を字面で固定する。
   Phloxの色帯を [(14,14,14),(239,68,68),(52,211,153),(251,191,36),(96,165,250),(217,119,87),(56,189,248),(214,214,214)] に固定する（`AppTheme.swift:245,271`）。
   GitHub Lightではbackground=(255,255,255)、inputBorderのopacity=0.86、RGBが同テーマのtextPrimaryであることを確認する。
   文言5種、themeID/name、マーカー色、色帯の8色と順序を検査する。
   登録10テーマについて候補由来の背景・文字・選択行・枠・色帯への写像を検査し、Phlox→GitHub Light→Phloxの呼び出しで前の候補が混入しないことを確認する。
   数値は実コード上のRGB・不透明度の契約であり、スクリーンショットの測色値ではない。
   `~/.agents/scripts/compact-test task35-design-system bash macos/scripts/run-swift-tests.sh DesignSystem` green。
   Appを含む隔離Debugビルド成功。統合時は既存 `.claude/verify.sh` を正本として実行し、パッケージテストの成功をAppのビルド成功と読み替えない。

2. 配線検査 `.claude/scripts/task35-wiring.rb` OK。
   PMが凍結し、`~/.agents/scripts/compact-test task35-wiring env TASK35_BASELINE=<凍結SHA> ruby .claude/scripts/task35-wiring.rb` で実行する。
   コメントを除去し、括弧・波括弧対応で対象View本文と引数を取り出して以下を検査する。
   ThemeRowViewが候補のthemeでmakeを呼ぶ／同じmodelを両見本へ渡す／アプリ・ターミナル双方の用途名をTextとして表示する／各見本がmodelの該当フィールドを実描画へ使う／selectedRowとinputFillに不透明なmodel.backgroundの下地がある／各Layerのopacityを適用する／見本内にDSColor・ThemeStore.active・UserDefaults・入力コントロールがない。
   既存のテーマ列挙、選択action、選択チェックが残ることを検査する。
   モデルのSwiftUI/AppKit importおよびColor/View/ColorScheme保持がないことを検査する。
   読み取り対象のTokens・ChatComposer・GridChatColumn・AppThemeについて、前述の選択面・入力面・枠・輝度判定が契約どおりであることを検査する。製品側だけ変更された場合も検査を落とす。
   SettingsViewの変更をテーマ行・テーマ見本に限定し、他の設定Sectionとactionの欠落を固定SHAとの差分で検出する。HEADとの自己比較は使わない。

3. PM目視ゲート:
   この変更から作った隔離Debugを専用DerivedData・専用データディレクトリで起動する。
   `PHLOX_DATA_DIR`、`PHLOX_AGENTS_JSON`、専用defaults suiteを利用し、実際にテーマ選択を書き込むdefaultsドメインも隔離されていることを事前確認する。suite指定だけでSettingsViewのAppStorageまで隔離されたと仮定しない（`SettingsView.swift:26`）。
   起動結果から自PIDを取得し、実行ファイルパスとウィンドウ所有PIDを照合する。自PIDに対するAX取得・AXPress、必要時のみ遮蔽確認付き座標クリックを使用する。キー送信は禁止。
   DraculaとGitHub Lightについて、設定一覧の候補見本と、適用後の背景・文字・現在の会話行・入力欄を撮影して比較する。
   選択前から各候補が固有の配色であること、テーマ選択後も他候補の見本が同じ色に染まらないこと、用途名・テーマ名・チェックが通常の設定ウィンドウ幅で欠けないことを確認する。
   課金セッションの起動・メッセージ送信は要求しない。サイドバーとターミナルは隔離した `/bin/cat` のcustom agentを利用できる。製品のチャット入力欄を課金なしで表示する経路は本草案では未確認のため、PMが凍結前に既存の未接続セッション等による表示経路を実証する。実証できなければ入力欄との実画面比較は未達として残し、配色テストだけで代替合格にしない。
   スクリーンショットには対象テーマ・PID・ウィンドウ寸法を記録する。測色する場合は同じ表示環境で内部の平坦面を比較し、文字縁・枠のアンチエイリアスを色差と混同しない。
   終了時は自分が起動したPIDと子プロセスだけを確認して終了する。撮影不能・AX取得不能は未検証として記録する。

## レビュー観点（Rubric）

- アプリ外観とターミナル配色を、用途名と内容の両方で区別できる。
- 現在選択中のテーマではなく、各行の候補テーマから見本を描いている。
- 入力欄の白4%と選択行の主文字10%を、不透明な候補背景上に正しく重ねている。
- 配色の導出を変更せず、既存描画との対応を凍結テスト・配線検査・代表2テーマの実画面で別々に確認している。
- 見本のためにSettingsView全体を大きく作り替えず、テーマ名・選択チェック・他の設定への到達性を維持している。
- 小さな見本に実入力や追加のフォーカス対象を持ち込んでいない。
- 未測定の見本寸法や実描画色を検証済みと書いていない。入力欄を含むPM目視ゲート未達のままUI-06完了にしない。
```

## tasks/task-36.md

```markdown
---
id: task-36
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/AgentConfigKit/Tests/AgentConfigKitTests/Acceptance/AcceptanceAgentConsoleNavigationModelTests.swift
baseline_commit: TBD
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
```

## PM への確認事項

なし。task-35の課金なし入力欄表示経路は、凍結前の技術確認として契約内に明記しました。