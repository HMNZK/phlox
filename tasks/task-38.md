---
id: task-38
difficulty: standard
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceSettingsGroupingModelTests.swift
  - .claude/scripts/task38-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/App/SettingsView.swift
  - macos/Packages/DesignSystem/Sources/DesignSystem/SettingsGroup.swift
  - docs/agent-output/task-38.md
---

## 目的

UX-06 / P1「設定を目的別にまとめる」。既存設定を「一般」「外観」「エージェント」「接続」「詳細」の5グループへ再配置し、外観変更・権限確認・接続設定・更新確認の所在を見出しから判断できるようにする。設定画面を開く操作とグループ切替では、設定値を変更しない。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:105`。観察された問題は、テーマ・討論設定・権限・モバイル・更新を縦に探す必要があること。改善は分類と再配置に限定し、設定機能やボタン様式を変更しない。

本草案は read-only 調査に基づく未凍結の契約である。調査時の HEAD は `c5a83afa4e29c0fc41fda3fc1180135bc04ec0b3`。ファイル変更、受け入れテスト作成・実行、配線検査実行、App ビルド、GUI 検証は行っていない。

## 入出力契約

### 事前条件

- 対象は `macos/App/SettingsView.swift` の既存681行。現在の単一 `Form` を、既存 Section の内容を保ったまま5グループへ分ける。
- `appUpdater`、`agentCatalog`、`hookDispatcherPath`、`mobileToken` と `openWindow` の受け渡しを維持する。
- task-35 のテーマ見本が存在すること。`ThemePreviewModel`、`ThemeRowView`、`ThemeAppPreview`、`ThemeSwatchStrip` を変更しない。
- PM が本契約のリテラルから受け入れテストと配線検査を作成し、未実装を原因とする red を確認して凍結する。
- `baseline_commit` と `TASK38_BASELINE` は、受け入れテスト・検査を凍結し、task-38 の実装を含まないコミットに固定する。調査時 HEAD を自動採用しない。

### 純粋モデル

`macos/Packages/DesignSystem/Sources/DesignSystem/SettingsGroup.swift` に以下の公開面を置く。

```swift
public struct SettingsGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let sectionIDs: [String]

    public static let all: [SettingsGroup]
}
```

- `all` の内容は後掲の5行に固定する。各 `sectionIDs` は表示順を持つ。
- Swift 標準ライブラリだけで構成する。SwiftUI・AppKit・Foundation を import せず、View、Binding、UserDefaults、ViewModel、ファイル、ネットワーク、プロセス、時計、環境変数に依存しない。
- 初期化・`all` の取得はリテラル値の構築だけとし、I/O、保存、登録、通知、設定値の補正を行わない。
- Section ID はこの分類の識別子であり、保存キーではない。設定値や動的なエージェント・端末・テーマの一覧をモデルへ複製しない。
- コントロールのラベル一覧を、テスト用だけの製品メタデータとして追加しない。純粋モデルのテストが分類を、配線検査が実際の Section・コントロールを検証する。

配置先は既存の `DesignSystem` とする。`DesignSystem/Package.swift` は依存が `AgentDomain` のみで、既存の `DesignSystemTests` から検査できる。`SettingsView` は既に DesignSystem を import し、同じ設定画面向けの純粋モデル `ThemePreviewModel` も存在する。

`DashboardFeature/Package.swift` は SessionFeature・TerminalUI・ControlServer・各 CLI バックエンド・MarkdownUI 等へ依存する。静的な表示分類のためにその依存を必要としないため、今回は採用しない。新規パッケージ、依存追加、`Package.swift`・`project.yml` の変更は不要とする。

### 表示方式

- **macOS 標準の `TabView` による5タブ**とする。
- タブの列挙・順序・表示名・シンボルは `SettingsGroup.all` を使う。タブの一覧を App 側で別途ハードコードしない。
- 各タブの内容は `Form` とし、後掲の所属・順序どおりに既存 Section を配置する。Section 内のコントロール順序は維持する。
- 選択状態は SettingsView 内の非永続な `@State` のみとし、初期値を `"general"` にする。`@AppStorage`・`@SceneStorage` にタブ選択を保存しない。
- タブの選択対象に `settings-group-<id>` の AX identifier を付ける。本文だけに identifier を置いて代用しない。
- グループの本文は `group.id` に対応する描画分岐へ接続する。`sectionIDs` と実際の描画分岐の一致は配線検査で固定する。未使用のモデルを置いて合格させない。
- `MobileTokenSection` は内部で2つの Section を描く既存の複合 View である。「接続」で一度だけ呼び、分割・二重呼び出しを行わない。
- 既存のヘッダーと、外側の `.frame(width: 520, height: 640)` を維持する。これは設定コンテンツの寸法であり、OS のタイトルバーを含む外枠寸法とは区別する。
- `PhloxApp.swift` の `Settings` シーンには独自の `.defaultSize` がない。近傍の `900 × 620` はエージェント管理ウィンドウの値であり、設定ウィンドウへ流用しない。
- `.formStyle(.grouped)`、`.scrollContentBackground(.hidden)`、`.tint(DSColor.accent)`、`.toggleStyle(AccentSwitchToggleStyle())` の効果を各 Form に維持する。背景と `ThemeStore.active.preferredColorScheme` への追随も維持する。
- 標準寸法で各グループの末尾までスクロールできること。テーマ見本の内部寸法を縮めて収めない。

タブ追加後の実画面での収まりと AX identifier の露出は未実測であり、成功基準3で確認する。

## 凍結する項目集合と順序

以下の表が期待値の正本である。PM はこのリテラルをテスト・配線検査へ転記する。実装の `all`・`allCases`・描画ソースから期待集合を生成してはならない。

### グループ順序と所属

| 順序 | id | title | systemImage | sectionIDs：この順序に固定 | 分類の根拠 |
|---|---|---|---|---|---|
| 1 | `"general"` | `"一般"` | `"gearshape"` | `["language", "sessions", "notifications", "updates"]` | 表示言語、日常の起動方法、通知、更新確認をまとめる。更新は所在を見つけやすくするため一般に置く |
| 2 | `"appearance"` | `"外観"` | `"paintpalette"` | `["theme", "app-icon"]` | アプリの見た目を変える2項目 |
| 3 | `"agents"` | `"エージェント"` | `"wrench.and.screwdriver"` | `["permissions", "agent-management"]` | 権限の確認と、各エージェント設定への入口 |
| 4 | `"connection"` | `"接続"` | `"network"` | `["mobile-connection", "paired-devices"]` | QR 接続と接続済み端末の管理 |
| 5 | `"advanced"` | `"詳細"` | `"slider.horizontal.3"` | `["discussion", "usage", "privacy", "about"]` | 討論の上限・時間・発言順、使用量表示の細かな設定、参照中心の情報を主操作から離す |

「詳細」への分類は設定内容に基づく設計判断であり、操作頻度を計測したという主張ではない。

### 現状の全 Section 見出し

現状順は、`MobileTokenSection` 内の条件付き Section を呼び出し位置へ展開して数える。**12個の直接 Section と2個の内部 Section、計14個**を対象にする。

| 現状順 | Section ID | 見出しの文字列リテラル | 移動先／グループ内順 | 既存の表示条件 |
|---|---|---|---|---|
| 1 | `"theme"` | `"外観"` | 外観／1 | 常時 |
| 2 | `"app-icon"` | `"アプリアイコン"` | 外観／2 | 常時 |
| 3 | `"language"` | `"言語"` | 一般／1 | 常時 |
| 4 | `"sessions"` | `"セッション"` | 一般／2 | 常時 |
| 5 | `"discussion"` | `"チームビュー討論"` | 詳細／1 | 常時 |
| 6 | `"permissions"` | `"権限"` | エージェント／1 | 常時。行は `agentCatalog.allDescriptors` |
| 7 | `"mobile-connection"` | `"モバイル接続"` | 接続／1 | `mobileToken != nil` かつ `MobileConnectionGuidePolicy.showsSettingsConnectionSection` |
| 8 | `"paired-devices"` | `"接続済みの端末"` | 接続／2 | 上記に加えて `!viewModel.devices.isEmpty` |
| 9 | `"notifications"` | `"通知"` | 一般／3 | 常時 |
| 10 | `"usage"` | `"使用量"` | 詳細／2 | 常時 |
| 11 | `"agent-management"` | `"エージェント"` | エージェント／2 | 常時 |
| 12 | `"privacy"` | `"プライバシー"` | 詳細／3 | 常時 |
| 13 | `"updates"` | `"アップデート"` | 一般／4 | 常時 |
| 14 | `"about"` | `"このアプリについて"` | 詳細／4 | 常時 |

調査時の実コードでは `MobileConnectionGuidePolicy.isCompanionClientBundled = true`。ただし optional VM と端末一覧の条件は残る。14件は描画コードとしての集合であり、すべてが常に画面に出るという意味ではない。条件により本文が空でも「接続」タブ自体は削除しない。

### 各 Section の全コントロール・表示行

各セルの番号は Section 内の順序。動的ラベルは固定文字列と区別して、現在の式をそのまま固定する。Link・LabeledContent・状態表示も欠落防止の対象に含める。

| Section ID | コントロール／独自 View とラベル・選択肢 |
|---|---|
| `"theme"` | 1. `ForEach(ThemeStore.all)` → `ThemeRowView`。内部は `Button(action: onSelect)`、名前は `Text(theme.name)`。用途表示は `Text(model.appLabel)`＝`"アプリ外観"`、`Text(model.terminalLabel)`＝`"ターミナル配色"`。内部の `ThemeAppPreview` は `"本文の見本"`、`"現在の会話"`、`"メッセージを入力"` を表示。`ThemeSwatchStrip` は既存の色帯。選択時の `Image(systemName: "checkmark")` を維持 |
| `"app-icon"` | 1. `ForEach(AppIconStore.all)` → `AppIconRowView`。内部は `Button(action: onSelect)`、名前は `Text(option.name)`、画像は `Image(option.assetName)`。選択時の `"checkmark"` を維持 |
| `"language"` | 1. `Picker`：`Label("表示言語", systemImage: "globe")`。選択肢は `Text("システム")`、`Text("日本語")`、`Text("English")` の順 |
| `"sessions"` | 1. `Picker`：`Label("デフォルトの開き方", systemImage: "rectangle.on.rectangle")`。選択肢は `Text("チャット")`、`Text("ターミナル")` の順 |
| `"discussion"` | 1. `TextField("最大発言数", …)`。2. `TextField("最大エージェント数", …)`。3. `TextField("ターンタイムアウト（秒）", …)`。4. `Picker`：`Label("スケジューラ", systemImage: "arrow.triangle.2.circlepath")`。選択肢は `Text("自由発言")`、`Text("ラウンドロビン")` の順 |
| `"permissions"` | 1. `ForEach(agentCatalog.allDescriptors, id: \.ref)` → `BypassToggleRow`。内部は `Toggle`、ラベルのソース表記は `Label("\(descriptor.displayName): フルアクセス（bypass）", systemImage: descriptor.symbolName)` |
| `"mobile-connection"` | `MobileTokenSection(viewModel: mobileToken)` 内：1. `TextField("端末名", …)`。2. 条件付き `Text(disabledReason)`。3. `Button`：`Label("QR コードを表示", systemImage: "qrcode")`。4. 条件付き `PairingQRView(payloadString: payload.urlString)`。5. 条件付き `Text(lastError)` |
| `"paired-devices"` | 同じ `MobileTokenSection` 内：1. `ForEach(viewModel.devices)` → `MobileDeviceRow`。行内は `Text(device.name)`、`Button("失効", role: .destructive, action: onRevoke)`、`Text(pairedAtText)` の順。未ペアリング時の文言は `String(localized: "未接続")` |
| `"notifications"` | 1. `Toggle`：`Label("セッション完了をバナーで通知", systemImage: "bell")`。2. `Toggle`：`Label("完了サウンド（Glass）を鳴らす", systemImage: "speaker.wave.2")`。3. `Button("通知テスト")` |
| `"usage"` | 1. `Toggle`：`Label("使用量サイドバーを自動更新", systemImage: "arrow.clockwise")`。2. `Toggle`：`Label("Claudeの使用量を取得", systemImage: "sparkles")`。3. `Toggle`：`Label("未取得のCLIも表示", systemImage: "eye.slash")`。4. `Toggle`：`Label("ヘッダーに使用量を表示", systemImage: "menubar.rectangle")` |
| `"agent-management"` | 1. `Button`：`Label("エージェント管理を開く", systemImage: "wrench.and.screwdriver")` |
| `"privacy"` | 1. `Link`：`Label("プライバシーポリシー", systemImage: "hand.raised")`。リンク先は `"https://phlox.cc/privacy"` |
| `"updates"` | 1. `Toggle`：`Label("起動時に自動でアップデートを確認", systemImage: "clock.arrow.circlepath")`。2. `Button("今すぐ確認")` |
| `"about"` | 1. `LabeledContent("アプリ", value: AppFlavor.current.displayName)`。2. `LabeledContent("バージョン", value: appVersion)`。3. `LabeledContent("ビルド", value: buildNumber)` |

補足の固定対象：

- 共通ヘッダーの `Text("設定")` と `Text(AppFlavor.current.displayName)`。
- モバイル端末名の初期値と空文字時の既定値 `String(localized: "iPhone")`。
- 通知テストの `sessionName: String(localized: "テスト")`。
- `appVersion`・`buildNumber` の情報取得と欠損時の `"—"`。
- 動的なテーマ名・アイコン名・エージェント名・端末名・エラー文言を固定文字列に置き換えない。既存データ源と表示式を維持する。

### footer 文言

以下の8件を、所属 Section とともに一字一句維持する。それ以外の6 Section に footer を新設しない。

| Section ID | `Text` の文字列リテラル |
|---|---|
| `"theme"` | `"テーマ（ターミナルの配色とアプリ全体）を切り替えます。変更は即座に反映されます。"` |
| `"app-icon"` | `"Dock とアプリのアイコンを切り替えます。変更は即座に反映されます。"` |
| `"sessions"` | `"新規セッションをチャット画面かターミナルで開くかの既定です。チャット非対応のエージェントはターミナルで開きます。"` |
| `"discussion"` | `"チームビュー討論の上限・タイムアウト・発言順の既定です。変更は次回の討論開始から反映されます。"` |
| `"permissions"` | `"変更は次回セッション開始から反映されます。OFF は通常の安全モード（Claude Auto／Codex Auto／Cursor Auto-review）、ON は承認なしのフルアクセスです。信頼できるプロジェクトでのみ有効にしてください。"` |
| `"mobile-connection"` | `"iPhone アプリで QR コードを読み取ると、同一 Tailscale ネットワーク経由で接続できます。「QR コードを表示」を押すたびに新しい端末として発行されます。既存の端末は影響を受けません。"` |
| `"usage"` | `"Codex・Cursor の使用量は自動で表示されます。Claude は Phlox 内で起動したセッションの使用量を表示します（直近に Phlox 内で Claude を起動していないと最新の値にならない場合があります）。"` |
| `"agent-management"` | `"Claude Code・Codex・Cursor の設定をここから操作できます。対話 TUI のスラッシュコマンド（/plugin・/permissions 等）や、設定ファイルの手編集でしか触れない項目が対象です。"` |

## 不変条件

### Binding・保存先・操作

以下の `@AppStorage` 宣言、参照先、既定値を維持する。キー定数の直接参照を文字列の再定義へ置き換えない。

| 保存対象 | 既存キー参照 | 現在のキー文字列 | 既定値 |
|---|---|---|---|
| `bannerNotificationEnabled` | `NotificationSettings.bannerKey` | `"phlox.notify.banner"` | `true` |
| `completionSoundEnabled` | `NotificationSettings.soundKey` | `"phlox.notify.sound"` | `true` |
| `usageAutoRefresh` | `UsageSettings.autoRefreshKey` | `"phlox.usage.autoRefresh"` | `true` |
| `claudeScrape` | `UsageSettings.claudeScrapeKey` | `"phlox.usage.claudeScrape"` | `true` |
| `showUnavailableUsage` | `UsageSettings.showUnavailableKey` | `"phlox.usage.showUnavailable"` | `false` |
| `showUsageInHeader` | `UsageSettings.showInHeaderKey` | `"phlox.usage.showInHeader"` | `true` |
| `themeID` | `ThemeStore.themeKey` | `"phlox.theme"` | `AppTheme.phlox.id` |
| `appIconID` | `AppIconStore.iconKey` | `"phlox.appIcon"` | `AppIconStore.defaultOption.id` |
| `appLanguageRaw` | `LanguageSettings.languageKey` | `"phlox.appLanguage"` | `AppLanguage.system.rawValue` |
| `defaultSessionBackendRaw` | `DefaultSessionBackendPreference.storageKey` | `"phlox.defaultSessionBackend"` | `DefaultSessionBackendPreference.chat.rawValue` |
| `agoraMaxUtterances` | `AgoraDiscussionSettings.maxUtterancesKey` | `"phlox.agora.maxUtterances"` | `30` |
| `agoraMaxAgents` | `AgoraDiscussionSettings.maxAgentsKey` | `"phlox.agora.maxAgents"` | `5` |
| `agoraTurnTimeoutSeconds` | `AgoraDiscussionSettings.turnTimeoutSecondsKey` | `"phlox.agora.turnTimeoutSeconds"` | `180` |
| `agoraSchedulerRaw` | `AgoraDiscussionSettings.schedulerKey` | `"phlox.agora.scheduler"` | `AgoraSchedulerKind.freeSpeech.rawValue` |
| `BypassToggleRow.isEnabled` | `descriptor.bypassKey` | descriptor が供給する既存キー | `true` |

さらに以下を固定 SHA との比較で保護する。

- `appLanguageBinding`、`defaultSessionBackendBinding`、`agoraSchedulerBinding` の get/set 全体と Picker の tag。
- 各 Toggle・TextField の Binding、数値書式、モバイル端末名の `@State`。
- テーマ選択の `themeID = theme.id`。アイコン選択の保存と `NSApp.applicationIconImage` 更新。
- 通知テストの `SessionCompletionNotifier.notifyCompleted` 呼び出し。
- エージェント管理の `openWindow(id: AgentConsoleCommands.windowID)`。
- 更新 Toggle の `appUpdater.automaticallyChecksForUpdates` の get/set、`appUpdater.checkForUpdates()`、`.disabled(!appUpdater.canCheckForUpdates)`。
- QR 表示・失効の action、非同期処理、disabled 条件、表示条件、端末列挙順。
- `BypassToggleRow`、`MobileTokenSection`、`MobileDeviceRow`、`ThemeRowView`、`ThemeAppPreview`、`ThemeSwatchStrip`、`AppIconRowView`、`RichButtonStyle` の内部全体。
- ボタンの `.buttonStyle`、`.focusEffectDisabled()`、destructive role、色、カーソル、hover、選択チェック、AX の既存指定。新しい親修飾で既存ボタンの様式を上書きしない。

### 開くだけでは設定値を書き込まない

- `SettingsGroup` の構築・取得は I/O を持たない。
- SettingsView の初期化・`body`・追加する描画ヘルパー・タブ切替経路に、UserDefaults/suite の書き込み、登録、削除、設定 Binding への代入、ViewModel の設定変更を追加しない。
- タブ切替で変更してよい値は、非永続なタブ選択状態のみ。`.onAppear`・`.task`・`.onChange`・初期化クロージャへ設定補正や既定値の保存を追加しない。
- `@AppStorage` の既定値解決と Binding の生成を、それだけで永続書き込みと判定しない。既存 setter/action の本文と、それがユーザー操作からだけ呼ばれる構造を検査する。
- `MobileTokenSection` の既存 `.task { await viewModel.refreshReachability() }` は維持する。これはモバイル待受・到達性の更新を伴い得るため、「画面表示は一切の副作用を持たない」とは主張しない。設定値の書き換え禁止と区別する。
- OS による設定ウィンドウ位置等の保存は、アプリ設定値の変更と別に観測する。task-17 に記載された `Settings_window` の変更実測を、task-38 で再検証済みとは扱わない。

### スコープと既存契約・ADR

- 実装役の変更は frontmatter の3ファイルに限定する。SettingsView 内の分類・再配置、純粋モデル、開示レポートだけを扱う。
- テスト、Ruby 検査、契約、verify の配線、台帳、ADR、スクリーンショットと PM の目視記録は PM 所有であり、`allowed_paths` 外。
- `Package.swift`、`macos/project.yml`、`CompositionRoot.swift`、`Localizable.xcstrings`、既存の隔離起動ヘルパーを変更しない。
- **task-17（UI-05、未凍結・pending）は吸収しない。** `RichButtonStyle` の標準 bordered 化、焦点抑制の除去、旧スタイル削除は task-17 の領域である。
- task-17 と SettingsView を共有するため、`depends_on: []` を同時編集可能という意味にしない。PM が同ファイルの実装を逐次にする。
- task-35 の既存受け入れテストと見本構造を保護する。task-35 に残る目視未達事項を task-38 の分類確認で完了扱いにしない。
- acceptance_tests のアサーションは変更禁止。ただしテストハーネスの欠陥を発見した場合は、PM に報告し承認を得たうえでハーネス部分に限り修理してよい。

ADR 索引 `macos/docs/adr/README.md` から関連文書を確認した。ADR 0071 のセッション既定、0112 の使用量表示、0156 の権限設定、0160 の端末別管理、0042 のテーマ追随は、内容を保った再配置と整合する。ADR 0121 は別のエージェント管理ウィンドウを対象とし、SettingsView の5タブを禁止するものではない。

- **PM 判断：** ADR 0072 はユーザー可視名称を「アゴラ」へ改称するとしているが、SettingsView の見出し・footer は「チームビュー討論」のままである。本契約では既存文言を保護し、名称の不整合は **PM がフェーズ5で扱う**。
- **PM 判断：** `macos/docs/architecture/mobile-proxy.md` には iOS 同梱まで非表示という記述が残るが、現在の `isCompanionClientBundled` は `true`。実コードを本契約の根拠とし、文書との整合は **PM がフェーズ5で扱う**。
- **PM 判断：** task-17 が先に入る場合は、その実装を task-38 の変更として取り込まず、PM が不変比較の基準と契約を凍結し直す。

## 成功基準

### 1. 凍結テスト：純粋モデルの分類が一致する

`AcceptanceSettingsGroupingModelTests` を PM が作成し、次をリテラル期待値で検査する。

- グループ数が `5`。
- ID の順序が `["general", "appearance", "agents", "connection", "advanced"]`。
- タイトルの順序が `["一般", "外観", "エージェント", "接続", "詳細"]`。
- systemImage の順序が `["gearshape", "paintpalette", "wrench.and.screwdriver", "network", "slider.horizontal.3"]`。
- 各グループの `sectionIDs` が「グループ順序と所属」の各配列と順序まで一致する。
- 連結後の要素数が `14`、重複がなく、集合が次のリテラル集合と一致する。

```text
theme
app-icon
language
sessions
discussion
permissions
mobile-connection
paired-devices
notifications
usage
agent-management
privacy
updates
about
```

- グループ ID にも重複がない。
- 繰り返し取得して同じ値が得られる。
- `SettingsGroup` が `Identifiable`、`Equatable`、`Sendable` に適合する。

実装の列挙から期待配列・期待集合・期待件数を作らない。実値の連結や集合化は検査対象を計算するためにのみ使う。

Section 見出し・コントロール・footer の実描画は SwiftUI 非依存のテストから検証できないため、成功基準2と合わせて欠落を判定する。モデルの green だけで既存設定の保存・描画を保証したと報告しない。

実行はリポジトリルートで次を使う。

```sh
~/.agents/scripts/compact-test task38-design-system bash macos/scripts/run-swift-tests.sh DesignSystem
```

DesignSystem の既存テストと task-35 のテーマ見本テストも通ること。PM は凍結前の red の具体的な失敗箇所を記録し、ハーネス欠陥による失敗と区別する。現時点では未作成・未実行である。

### 2. 配線検査：リテラル・描画経路・不変条件を守る

PM が `.claude/scripts/task38-wiring.rb` を作成し、実装前に凍結する。単純なファイル全体の文字列包含だけでは合格にしない。

検査項目：

1. **字句と構造の解析**
   - 文字列リテラルの内容を保持してコメントを除去し、括弧・波括弧対応で View・Section・引数・action を切り出す。
   - URL 内の `//`、文字列補間、文字列中の括弧を壊さない。解析不能・対象不在は失敗にする。
   - 比較用の正規化はコメントと文字列外の空白に限定する。ラベルや footer の文字列内空白を消して差異を隠さない。

2. **タブと Section への接続**
   - SettingsView の実際の `body` が標準 `TabView` を描き、`SettingsGroup.all` の5件からタブ名・シンボル・tag を供給する。
   - AX identifier が `settings-group-general`、`settings-group-appearance`、`settings-group-agents`、`settings-group-connection`、`settings-group-advanced` に対応する。
   - 各タブから到達する Section の見出しと順序が契約に一致する。モデルだけ正しく、描画先が別グループなら失敗にする。
   - `MobileTokenSection` は接続分岐で一度だけ呼ぶ。内部2 Section と既存条件を展開して対応を検査する。
   - 未使用ヘルパー、コメント、ダミー文字列、`if false`、常時非表示等にラベルを残しても合格にしない。

3. **既存項目の欠落・変更防止**
   - 契約の14見出し、コントロール表、選択肢、動的な表示式、8 footer をリテラルで固定する。
   - 各ラベルが対応する実コントロールのラベル位置に残り、Section 内の順序・個数・条件が維持されること。
   - テーマ・アイコン・descriptor・端末の `ForEach` と供給元を維持する。動的な行数を固定件数へ置き換えない。
   - `TASK38_BASELINE` から既存 Section の内容を取り出し、移設後と比較する。許すのは契約どおりの所属・Section 順序・描画ヘルパーへの移設と外側の分類構造だけ。
   - Binding、`@AppStorage` 宣言、既定値、footer、action、disabled 条件、ボタン修飾、独自 View 内部を比較する。
   - `.frame(width: 520, height: 640)`、既存の Form 修飾・背景・テーマ追随を維持する。

4. **表示時の書き込み禁止**
   - `SettingsGroup.swift` は標準ライブラリの値型・リテラル構築だけであることを検査する。外部ヘルパーや初期化クロージャへの処理の隠蔽も拒否する。
   - SettingsView の新規初期化処理、描画ヘルパー、ライフサイクル処理、選択 Binding を検査し、設定保存・登録・削除・設定値代入を拒否する。
   - 既存の操作 action と Binding setter は固定 SHA と比較して許可する。`@AppStorage` の存在だけを違反としない。
   - 非永続なタブ選択更新と、既存の `MobileTokenSection.refreshReachability()` を区別する。

5. **固定基準**
   - `TASK38_BASELINE` は必須。未設定、無効なコミット、対象ファイル取得失敗は非ゼロ終了。
   - `HEAD`、ブランチ名、現在の作業ファイルを基準として使わない。未設定時のフォールバックは禁止。
   - 凍結コミットと実装コミットが異なることを確認する。実装後 HEAD を基準にした自己比較を拒否する。

`--selftest` は実ファイルを変更せず、メモリ上の fixture で次を検査する。

- 正例：契約どおりの Section 移動、描画ヘルパー抽出、非永続タブ選択、既存の条件付きモバイル2 Section。
- 負例：グループ欠落・重複・順序違い・タイトル違い・所属違い・モデル未使用・AX identifier 欠落。
- 負例：Section／コントロール／Picker 選択肢の欠落、同じラベルを未使用コードへ残す偽装。
- 負例：Binding 先・保存キー・既定値・footer・action・disabled・ボタン様式・独自 View 内部の変更。
- 負例：設定画面の構築やタブ変更からの書き込み、モデル初期化の I/O。
- 正例：URL、補間文字列、コメント、文字列中の括弧を正しく処理する。
- 負例：文字列内空白の改変、構文切り出し失敗、固定 SHA の欠落・不正・自己比較。

verify に次の検査を含め、各終了コードが成功すること。`<PM が固定する SHA>` は凍結時に実値へ置換する。

```sh
~/.agents/scripts/compact-test task38-wiring-selftest ruby .claude/scripts/task38-wiring.rb --selftest
~/.agents/scripts/compact-test task38-wiring env TASK38_BASELINE=<PM が固定する SHA> ruby .claude/scripts/task38-wiring.rb
~/.agents/scripts/compact-test task38-task35-selftest ruby .claude/scripts/task35-wiring.rb --selftest
~/.agents/scripts/compact-test task38-task35-regression env TASK35_BASELINE=094f86a ruby .claude/scripts/task35-wiring.rb
```

**既存 task35 検査との衝突：** 現在の `task35-wiring.rb` は、`ThemeRowView`・`ThemeAppPreview`・`ThemeSwatchStrip` を除いた SettingsView 全体を `094f86a` と比較する。したがって、テーマ見本を変更しなくても、今回の TabView 化・Section 移動を「テーマ行・見本以外が差分あり」として拒否する。現行検査を無変更のまま通すことと、UX-06 の再配置は両立しない。

- **PM 判断・凍結前必須：** task35 検査をどう更新するか決定する。案は、`TASK35_BASELINE=094f86a` とテーマ見本・製品配色の検査を維持し、再配置された既存 Section の内容を比較する方式へ PM が更新すること。その際、task38 検査で新しい所属・順序を保護し、移動だけを許す正例と内容改変を拒む負例を追加する。
- **PM 判断・凍結前必須：** 上記の検査更新は未承認・未実装である。基準 SHA のすり替え、残余比較の単純削除、失敗無視、旧検査の省略を回避策として採らない。判断が済むまで実装役へ凍結契約として渡さない。

### 3. App ビルド・回帰確認・PM 目視ゲート

SettingsView は App ターゲットにあり、DesignSystem の `swift test` ではコンパイルも実描画も検証されない。次の App ビルド成功を **PM ゲート必須項目**にする。

作業ディレクトリを `macos` として実行する。

```sh
~/.agents/scripts/compact-test task38-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath /tmp/phlox-t13-visual.SPfR9c/Build -destination platform=macOS build
```

統合検証は既存 `.claude/verify.sh` を正本として実行する。

```sh
~/.agents/scripts/compact-test task38-integration bash .claude/verify.sh
```

同スクリプトの対象は8パッケージ、更新隔離検査、`git diff --check`。成功を App ビルドや GUI 検証の代用にしない。lint・静的解析等の追加ゲートが凍結時に設定されていれば PM が確認し、対象外・未設定・実行不能を区別して記録する。

PM 目視ゲート：

- 今回の変更からビルドした隔離 Debug を、専用の `PHLOX_DATA_DIR`、`PHLOX_AGENTS_JSON`、defaults suite で起動する。課金セッションやメッセージ送信を使わない。
- `/tmp/phlox-t13-visual.SPfR9c/shoot-t35.sh` の、自 PID・実行ファイルパス・ウィンドウ所有 PID を照合して AX で設定を開き、ウィンドウ単位で撮影する流儀を参考にする。同スクリプトはテーマ変更操作・固定 PID・禁止コマンド等を含むため、そのまま実行しない。
- suite 指定だけで SettingsView の `@AppStorage` が隔離されると仮定しない。Debug の実際の保存ドメイン、専用 suite、通常の Release ドメインを確認する。
- アプリ起動後・設定を開く直前、設定を開いた直後、5グループ往復後で、設定値とキーの有無を比較する。未設定キーが勝手に保存されないことも確認する。OS のウィンドウ保存や起動時の既存更新処理は別に記録する。
- 設定入口を AX で操作し、初期選択「一般」と5タブの順序・名前・identifier を確認する。
- 5タブを AX で切り替え、各グループの見出しとコントロールが契約どおりであることを撮影する。値を変更する Toggle・Picker・TextField・テーマ・アイコン・通知テスト・更新確認・QR 発行・失効を操作しない。
- 「外観」から外観変更、「エージェント」から権限確認と管理入口、「接続」からモバイル接続、「一般」からアップデート確認の所在が読み取れることを確認する。
- コンテンツ `520 × 640` の標準寸法で各グループの先頭と末尾を撮影する。外枠の実測寸法も記録し、末尾のコントロール・footer へのスクロール到達、文字の欠け・重なり、テーマ見本の用途名の折り返しを確認する。
- 非選択グループが操作対象として残らず、選択状態が AX で分かることを確認する。標準タブのキーボード操作・焦点表示を妨げる修飾を追加しない。
- 「モバイル接続」は実 VM がある状態で確認する。「接続済みの端末」は隔離環境に既存の端末データがある場合だけ確認する。撮影のために新しい端末やトークンを発行しない。
- 各画像にコミット、グループ ID、PID、ウィンドウ ID、寸法、表示条件を記録する。PM の結果は `docs/agent-output/visual-task-38.md` に保存する。
- 終了時は起動元・親子関係を確認し、この作業で起動した不要な PID と子プロセスだけを終了する。他セッションの Debug・Release を停止しない。

- **PM 判断・凍結前必須：** 値を変えずに「接続済みの端末」を描画できる隔離データの有無を確認する。未確保なら当該 Section の実画面検証は未達とする。配線検査や空一覧の画像を、端末行の目視成功に読み替えない。
- **PM 判断：** AX 操作、標準寸法での到達、保存先の隔離・前後比較が確認できない場合は、その項目を未検証として残す。検証範囲の変更を明示的に決めるまで UX-06 の完了を宣言しない。

## レビュー観点（Rubric）

- 5グループの名前・順序・所属が契約に一致し、外観・権限・接続・更新の入口が見出しから分かる。
- 14 Section のコード、コントロール、選択肢、動的な行、footer が欠落せず、既存の条件付き表示も保たれている。
- `SettingsGroup.all` が実際のタブに使われ、モデルだけ正しく描画が異なる実装になっていない。
- `MobileTokenSection` の複合構造を壊さず、一度の呼び出しで2 Section を保持している。
- Binding・保存先・既定値・action・disabled 条件を変更せず、タブ選択を永続化していない。
- 表示時の設定書き込み禁止を、`@AppStorage` の既定値解決や既存の到達性更新と区別して検証している。
- task-35 の見本構造と task-17 のボタン領域を守り、分類変更に無関係な改善を混ぜていない。
- 標準 `TabView` と既存 Form を使い、不要な依存・独自タブ・設定保存基盤・未使用メタデータを追加していない。
- 標準寸法で末尾へ到達でき、テーマ見本・文言・タブ名が欠けず、AX から選択と操作対象が分かる。
- 固定 SHA 比較が実際に回帰を検出し、旧 task35 検査との衝突を無視・基準変更・検査削除で隠していない。
- 純粋モデルのテスト、配線検査、App ビルド、実画面確認の証拠を区別し、条件付き端末行や隔離の未検証を明示している。
- ADR・関連文書の不整合は PM のフェーズ5課題として残し、今回の再配置に名称変更や機能変更を混ぜていない。
## PM 決定（2026-09-13、草案の「PM 判断」への回答）

1. **task35-wiring.rb との衝突**: `TASK35_BASELINE=094f86a` とテーマ見本・製品配色の検査は維持する。SettingsView の「テーマ以外の残余を丸ごと比較」する部分は、**Section 単位の内容比較**（見出しリテラルで各 Section ブロックを切り出し、空白正規化のうえ 094f86a の同 Section と比較。Form 間の移動・順序変更は許容、内容改変は拒否）へ PM 側で更新する。基準 SHA のすり替え・残余比較の削除・失敗無視は行わない。更新は受け入れテスト・rb と同じ凍結コミットに含める。
2. **「接続済みの端末」の実画面**: 値を変えずに端末行を描ける隔離データが無ければ、当該 Section は「未検証（描画コードの存在は rb で確認）」として `visual-task-38.md` に記録し、それを理由に task-38 を止めない。UX-06 の [x] 判定時にこの未検証を仕様へ明記する。
3. **分類**: 草案の 5 グループ・所属・順序を採用する（更新は「一般」）。
4. **acceptance_tests の rb**: `.claude/scripts/task38-wiring.rb` は PM 所有の配線検査として frontmatter に残すが、実装役の allowed_paths 外である。
5. **task-17（UI-05）**: 本タスクで吸収しない。task-17 草案は task-38 完了後に再ベースする（decision-log 2026-09-13）。

## 契約改訂（2026-09-13、敵対レビュー `docs/agent-output/task38-acceptance-adversarial.md` の反映・PM 裁定）

- **[指摘1]** 配線検査は `body` から実際に到達する描画経路だけを検査対象にする（未使用ヘルパー内の分岐を配線済みと数えない）。タブは `ForEach(SettingsGroup.all)`（`reversed()`・並べ替え・部分列は NG）で列挙し、タブのタイトル・シンボルは `group.title`／`group.systemImage` から描くこと。AX identifier は `.accessibilityIdentifier("settings-group-\(group.id)")` の形でタブ側に付ける（`help` 等への置換は NG）。
- **[指摘2]** `@AppStorage` は**宣言単位**（属性・キー・変数名・既定値をひとまとめ）で `TASK38_BASELINE` と一致すること。内部を固定する独自 View の一覧に `AppIconRowView` を加える（`BypassToggleRow`・`MobileTokenSection`・`ThemeRowView`・`ThemeAppPreview`・`ThemeSwatchStrip`・`AppIconRowView`）。
- **[指摘3]** 「開いただけでは値を変えない」: SettingsView の保存対象（`@AppStorage` 変数・`ThemeStore`・`appUpdater` 等）への**代入・呼び出し箇所の集合**が baseline と一致すること（`onAppear`／`task`／`onChange`／描画ヘルパー内の新規書き込みは NG）。`SettingsGroup.all` は `SettingsGroup(...)` イニシャライザ呼び出しだけを要素とするリテラル配列（クロージャ・関数呼び出し・`print`・副作用を含まない）であること。
- **[指摘4]** Section 以外のコード（保存宣言・Binding 実装・計算プロパティ・独自 View・Section 外の条件分岐）は従来どおり**宣言単位で baseline と一致**を要求する（保護範囲を Section 本文と footer に狭めない）。同名 Section の重複は NG（後勝ち上書き・`.uniq` による吸収を禁止）。task35-wiring.rb にも同じ扱いを適用する。
- **[指摘5]** `TASK38_BASELINE` は「HEAD と一致しないこと」ではなく、**凍結基準の内容**で検証する: ①HEAD の祖先である ②基準時点で `SettingsGroup.swift` が存在せず SettingsView に `TabView` が無い（＝実装前） ③基準時点の受け入れテストと本 rb が現在と同一。凍結 HEAD 上の未コミット実装を検査する通常運用を拒否しない。
- **[指摘6]** `--selftest` の負例は「正例 fixture に違反を 1 つだけ加えたもの」とし、**本番と同じ検査関数**で NG になることを確認する（重複分岐・並べ替え・未使用コード偽装・`if false` 包みを含む）。task35-wiring.rb の selftest も本番関数を使う。
- **[指摘7]** PM 目視ゲートの起動条件に `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を加え、通常 Debug の Keychain（端末ストア）を隔離する。
