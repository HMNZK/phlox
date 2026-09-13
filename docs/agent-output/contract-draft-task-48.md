---
id: task-48
difficulty: standard
depends_on: [task-36, task-38]
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceUIWordingTests.swift
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptancePermissionWordingTests.swift
  - macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/ComposerModeMenuAcceptanceTests.swift
  - macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/AcceptanceContextPopoverBranchTests.swift
  - .claude/scripts/task48-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/DesignSystem/Sources/DesignSystem/UIWording.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatComposer.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/GridChatColumn.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ComposerSettingsControls.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ComposerContextIndicator.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionAccessories.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatCodeBlock.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCopyButton.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamComposer.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift
  - macos/App/SettingsView.swift
  - macos/App/AgentConsole/Claude/ClaudePermissionsPane.swift
  - macos/App/AgentConsole/Codex/CodexSettingsPane.swift
  - macos/App/AgentConsole/Cursor/CursorPermissionsPane.swift
  - macos/App/AgentConsole/Cursor/CursorSettingsPane.swift
  - docs/agent-output/task-48.md
---

## 目的

UX-10「操作の言葉と権限説明をそろえる」。日本語表示では同じ操作に同じ文言を使い、権限の説明ではエージェントごとの承認方式と実行制限を区別する。仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:128`。

配置予定先は `docs/agent-output/contract-draft-task-48.md`。本回答は read-only の未凍結草案であり、ファイルは作成・変更していない。調査時の HEAD は `50b6726c36689cc425c6f21b6ac6a472c3a608ad`。テスト作成・実行、配線検査、App ビルド、GUI 確認は未実施。

実装担当は Cursor。受け入れテストと配線検査は PM が作成・凍結し、Cursor は変更しない。レビュー担当は実装担当と別モデルとする。

## 入出力契約

### 事前条件

- task-36 のエージェント管理画面と task-38 の設定グループ構造を維持する。
- 後掲の対象集合、権限対応表、既存検査の改訂を PM が確定してから凍結する。
- 新設するファイル・API は本契約の要求であり、既存実装として確認したものではない。
- `allowed_paths` は製品実装と実装報告の編集許可である。テスト、配線検査、タスク契約、台帳、検証スクリプトの編集権限を Cursor に与えない。
- App ターゲットへテストを追加しない。表示文言の選択・権限説明の判定は SwiftPM パッケージ内へ置く。
- 課金セッション、実 `claude`・`codex`・`cursor-agent` の起動、メッセージ送信を受け入れ条件にしない。

### 調査結果：ローカライズ機構

| 対象 | 実コードで確認した状態 | 契約上の扱い |
|---|---|---|
| `macos/App/LanguageSettings.swift` | `AppLanguage` は `system`・`ja`・`en`。`LanguageSettings.languageKey` は `phlox.appLanguage`。`system` は `Locale.autoupdatingCurrent` | キー、保存値、既定値を維持 |
| `macos/App/PhloxApp.swift:44` | `@AppStorage` で表示言語を読む | 独自の言語保存先を増やさない |
| `macos/App/PhloxApp.swift:82`・`:125`・`:139` | 各画面へ `.environment(\.locale, appLanguage.locale)` を注入 | 対象 View はこの環境値から表示言語を受け取る |
| `-phlox.appLanguage ja` | 専用引数パーサーは確認していない。実装は UserDefaults の同名キーを読む構造 | 起動引数の反映は PM が隔離 Debug の表示で確認する |
| `macos/App/Localizable.xcstrings` | `sourceLanguage` は `ja`、117項目。今回の主要文言 `Ask Phlox anything...`・`Full Access`・`Bypass`・`Error`・`Output available`・`Command` は未登録 | 既存カタログ全体の移行は行わない |
| 指定された3パッケージ | パッケージ内の `Localizable.xcstrings` は検索で見つからなかった | App のカタログをパッケージテストから利用できると仮定しない |
| `String(localized:)` | App、SessionFeature、DashboardFeature に既存使用あり。例：通知、使用量状態、ダイアログ | 存在だけを根拠に SwiftUI の言語切替へ追随すると扱わない |
| `AgentConfigKit` | 調査した設定モデルは表示名・説明を通常の `String` として返す | 権限の表示変換は App の描画側から文言正本を参照する |
| `DesignSystem/Package.swift` | `AgentDomain` へ依存し、既存のテストターゲットを持つ。リソース指定は `Icons.xcassets` | 新しい依存・パッケージ・リソース読込機構を追加せず、純粋な文言選択を配置できる |

### 調査結果：今回置換する表示文言

以下は表示位置を確認した対象集合である。同じファイルの通常表示・省略メニュー・選択中表示を別経路として検査する。表の日本語を期待値の正本とする。

SessionFeature の行は、特記しない限り `macos/Packages/SessionFeature/Sources/SessionFeature/` 配下。

| 確認箇所 | 現在の表示 | 日本語の期待値 |
|---|---|---|
| `ChatComposer.swift:92`、`GridChatColumn.swift:257`、DashboardFeature の `Dashboard/TeamComposer.swift:52` | `Ask Phlox anything...`／`メッセージを入力` | **メッセージを入力** |
| `ChatMessageCells+Basic.swift:213` | `Error` | エラー |
| `ChatMessageCells+Structured.swift:266` | コマンド欠損時の `Command` | コマンド |
| 同ファイル `:267` | 出力がある場合の `Output available` | 出力あり |
| 同ファイル `:35` | 説明欠損時の `Sub-agent` | サブエージェント |
| `ChatCodeBlock.swift:25`、`RichMarkdownView.swift:147` | `Copy` | コピー |
| `ChatCodeBlock.swift:33`、`RichMarkdownView.swift:152` | `Copy code` | コードをコピー |
| `ChatMessageCopyButton.swift:49`・`:50` | `Copy message`／`コピーしました` | メッセージをコピー／コピーしました |
| `ChatCodeBlock.swift:17`、`RichMarkdownView.swift:140` | 言語名欠損時の `text`／`code` | テキスト／コード |
| `ChatSessionAccessories.swift:368`・`:371`・`:374` | `Accept`／`Decline`／`Cancel` | 承認／拒否／キャンセル |
| `ComposerSettingsControls.swift` | `Model` | モデル |
| 同ファイル | `Effort`／`Reasoning Effort` | 思考の深さ |
| 同ファイル | `Permission`／`Approval` | 承認設定 |
| 同ファイル | `Mode` | 動作モード |
| 同ファイル | `Plan` | 計画 |
| 同ファイル | `Low`／`Medium`／`High`／`XHigh`・`X High`／`Max` | 低／中／高／非常に高／最大 |
| 同ファイル `:913`・`:938` | `Refresh`／ブランチ欠損時の `Branch` | 更新／ブランチ |
| `ComposerContextIndicator.swift:251`・`:264` | `Branch checkout failed`／`No local branches` | ブランチの切り替えに失敗しました／ローカルブランチがありません |
| 同ファイル `:61` | `Context window:` | コンテキスト容量: |
| 同ファイル `:62` | 使用率・残量の英語テンプレート | 使用 `{使用率}%`（残り `{残量}%`） |
| 同ファイル `:63` | 使用トークン数の英語テンプレート | `{使用量} / {容量}` トークン使用 |
| `ChatMessageCells+Basic.swift:162` | AX ラベル `Turn cost …` | この応答の費用 `{既存の金額表示}` |
| DashboardFeature の `Dashboard/DashboardSidebarView.swift:91` | `Projects` | プロジェクト |

- 英語表示の入力欄は3箇所とも `Enter a message` にそろえる。
- その他の既存英語表示は原則維持する。ただし同じ操作の `Effort`／`Reasoning Effort`、`XHigh`／`X High` はそれぞれ `Reasoning Effort`、`X High` に統一する。
- 金額・使用率・トークン数の計算、丸め、単位、通貨を変更しない。文字列テンプレートだけを変更する。
- `Command` は欠損時の代替表示だけを変更する。実コマンド、出力、エラー本文、承認要求本文はそのまま表示する。
- `text`・`code` は言語名欠損時の代替表示だけを変更する。実際のコード言語名は翻訳しない。
- `OK`、言語選択肢の `English`、製品名、モデル名、ブランチ名、パス、設定キー、CLI 引数、AX identifier は翻訳対象にしない。

### 調査結果：別途扱う文言

以下も検索で見つかったが、静的な操作ラベルとは異なる生成・保存経路を持つ。本契約の完了を、これらまで解消したという報告に読み替えない。

| 確認箇所 | 文言 | 扱い |
|---|---|---|
| SessionFeature の `ChatSessionViewModel.swift:2000`、`ChatSessionSupportingTypes.swift` | `Approval requested`、`app-server system error`、未知状態の説明 | アプリが生成する状態説明。別タスクで生成元と表示時ローカライズを契約化 |
| SessionFeature の `SessionViewModel.swift:529`・`:534` | `Codex is asking a question` | ターミナル状態説明。上記の別タスクへ |
| SessionFeature の `ChatSubAgentModel.swift:110`・`:141` | データへ埋め込む `Sub-agent` | 既存データの文字列置換は禁止。代替文言の由来を識別する別契約が必要 |
| AgentConfigKit の `Claude/ClaudeOutputStyleSettings.swift:28`・`:33` | `Explanatory`／`Learning` | 組み込みスタイルの選択肢名。カスタム名と区別する別タスク候補 |
| DashboardFeature の `Usage/CursorUsageProvider.swift:121` | 使用量区分の `Auto` | 権限の `auto` と別物。今回の権限訳語を適用しない |

### 文言の正本

新設要求として `DesignSystem/UIWording.swift` に、表示言語と表示対象を受け取り、文言を返す純粋な公開 API を置く。`UIWording` は新設名であり、既存シンボルではない。

- 一般文言、権限の表示名、権限の説明をここから供給する。対象 View に同じ文言の別定義を残さない。
- 言語は呼び出し側の `@Environment(\.locale)` から渡す。言語コード `en` は英語、`ja` は日本語、それ以外は既存の開発言語に合わせて日本語へフォールバックする。
- `ja-JP`、`en-US` 等は View 側で言語コードへ正規化して渡す。正本が UserDefaults、プロセス環境、`Locale.current` を暗黙に読む設計にしない。
- 通常の値型・列挙型・関数で実装する。View、保存処理、通知、ネットワーク、プロセス起動、翻訳 API を含めない。
- App の既存 xcstrings へ今回の同一文言を重複登録しない。既存カタログや他画面のローカライズ方式は移行しない。
- Swift Testing から日本語・英語を明示して検査できること。
- API の名前・引数型は PM がテスト作成時に確定し、実装前に凍結する。実装結果から期待値を生成しない。

`composerModeOptions(for:codexProfileIDs:)`、`composerPermissionTitle(for:)`、選択中表示の `claudePermissionTitle(for:)`・`cursorModeTitle(for:)`、通常メニューと省略メニューは、同じ正本へ接続する。言語引数の追加は許可するが、選択値・順序・`isPlan`・操作処理は維持する。

### 権限説明の対応表

権限の検索キーは、最低限「対象エージェント・設定の種類・内部値」を区別する。値の文字列だけで横断的に翻訳しない。

#### Claude Code：permission mode

現行メニューの内部値は `acceptEdits`、`auto`、`bypassPermissions`、`manual`、`dontAsk`、`plan`。`default` は表示対応として扱うが、今回のために選択肢を増やさない。

| 内部値 | 日本語表示名 | 凍結する説明 |
|---|---|---|
| `default`／`manual` | 手動承認 | 読み取り以外は権限ルールに従って承認を求めます。実行範囲の制限とは別の設定です。 |
| `acceptEdits` | 編集を自動承認 | ファイル編集などを自動承認します。すべてのコマンド実行を承認する設定ではありません。 |
| `auto` | 自動判定 | Claude Code が操作を判定します。すべての操作を無条件に許可する設定ではありません。 |
| `bypassPermissions` | 承認確認を省略 | 通常の承認確認を省略します。サンドボックスの解除を意味する設定ではありません。 |
| `dontAsk` | 承認が必要な操作を拒否 | 事前に許可された操作などを実行し、承認が必要な操作は確認せず拒否します。 |
| `plan` | 計画 | 調査と計画を行うモードです。編集を進めるモードとは区別されます。 |

`manual` は現在の公式資料では `default` の別名だが、Phlox が送る既存値 `manual` を書き換えない。承認方式と実行範囲は別の設定である。これらの説明は [Claude Code の権限モード](https://code.claude.com/docs/en/permission-modes) に基づく。利用端末の CLI バージョンと機能対応は未確認。

英語表示名は既存の `Manual`、`Accept Edits`、`Auto`、`Bypass`、`Don't Ask`、`Plan` を維持する。`default` の表示名も `Manual` とする。

#### Codex：承認方針と実行制限

`AgentConfigKit/Codex/CodexGeneralSettings.swift` の `CodexSettingKey` は `approval_policy` と `sandbox_mode` を別項目として持つ。この区別を表示にも残す。

| 設定／値 | 日本語表示名 | 凍結する説明 |
|---|---|---|
| `approval_policy=untrusted` | 信頼対象外の操作を確認 | 自動実行できる操作以外は承認を求めます。実行範囲はサンドボックス設定に従います。 |
| `approval_policy=on-request` | 必要時に承認を要求 | Codex が必要と判断したときに承認を求めます。実行範囲はサンドボックス設定に従います。 |
| `approval_policy=never` | 承認を要求しない | 承認を求めず、設定された実行制限の範囲で動作します。実行制限を解除する設定ではありません。 |
| `approval_policy=granular` | 項目別の承認設定 | 承認要求の種類ごとに扱いを定める設定です。この名前だけでは具体的な許可範囲は分かりません。 |
| `sandbox_mode=read-only` | 読み取り専用 | サンドボックス内での書き込みを制限します。承認を求める条件は別の設定です。 |
| `sandbox_mode=workspace-write` | 作業領域への書き込み | 作業領域など、設定された範囲への書き込みを許可します。ネットワークや保護対象の制限は別途適用されます。 |
| `sandbox_mode=danger-full-access` | サンドボックス制限なし | Codex のサンドボックスによる実行制限を外します。承認を求める条件は別の設定です。 |

`never` はサンドボックス解除と同義ではない。[Codex の承認と実行制限](https://developers.openai.com/codex/agent-approvals-security)

コンポーザーの既存プロフィールは次の表示名にする。

| プロフィール ID | 日本語表示名 | 英語表示名 |
|---|---|---|
| `:read-only` | 読み取り専用 | Read Only |
| `:workspace` | 作業領域への書き込み | Auto |
| `:danger-full-access` | 承認なし・実行制限なし | Full Access |
| `nil` | 承認設定 | Approval |

- プロフィール ID だけから未確認の承認方針を推測して説明しない。
- 起動設定の ON/OFF と、サーバーから取得するプロフィール一覧を同じデータとして扱わない。
- `ApprovalPolicy` は `.named(String)` と `.granular(JSONValue)`、`SandboxPolicy` は文字列とオブジェクトを扱う実装を確認した。オブジェクトの内容を表示名へ変換して書き戻さない。
- `CodexSettingKey.knownValues` が文字列 `granular` を候補に持つことと、その値を現在の CLI が受理することは別である。後者は未確認であり、本タスクで設定形式を変更しない。

#### Cursor：承認方式・実行制限・動作モード

`CursorGeneralSettings.swift` は `approvalMode` と `sandbox.mode` を別項目として持つ。`CursorPermissionRules.swift` のルールは `allow`・`deny` の2区分で、Claude の `ask` 区分とは異なる。

| 設定／値 | 日本語表示名 | 凍結する説明 |
|---|---|---|
| `approvalMode=allowlist` | 許可リストで確認 | 許可リスト外の操作では確認を求める設定です。サンドボックス設定とは別です。 |
| `approvalMode=unrestricted` | 承認確認を省略 | 操作の承認確認を省略する設定です。サンドボックス設定とは別です。 |
| `approvalMode=auto-review` | Cursor の自動判定 | Cursor の判定に従って操作を実行します。Claude の権限モードや Codex の承認方針とは別の設定です。 |
| `sandbox.mode=enabled` | 実行制限を有効化 | コマンドをサンドボックス内で実行する設定です。 |
| `sandbox.mode=disabled` | 実行制限を無効化 | サンドボックスによる実行制限を無効にする設定です。 |
| 動作モード `nil` | エージェント | 通常の作業モードです。承認方式や実行制限を選ぶ項目ではありません。 |
| 動作モード `ask` | 質問 | 質問向けの動作モードです。承認方式を選ぶ項目ではありません。 |
| 動作モード `plan` | 計画 | 計画向けの動作モードです。承認方式を選ぶ項目ではありません。 |

承認方式の説明は現在の `CursorSettingKey.explanation` と起動引数に基づく。検索した公式 CLI 権限ページでは `approvalMode`・`auto-review` の説明は確認できなかったため、サーバー側判定の詳細は未確認。`deny` が `allow` より優先される点は [Cursor CLI の権限資料](https://cursor.com/docs/cli/reference/permissions) でも確認した。

Cursor IDE の権限モデルを、そのまま CLI の説明として流用しない。

#### 設定画面の「権限」Section

`SettingsView.swift:244` の全エージェント共通説明と、`:329` の「フルアクセス（bypass）」を置換する。行ごとに対象エージェントの説明を表示し、ON/OFF の意味を確認できるようにする。

| 対象 | Toggle の日本語ラベル | OFF／ON の説明に使う実装上の対応 |
|---|---|---|
| Claude Code | Claude Code: 承認確認を省略 | OFF：`auto`。ON：`bypassPermissions`。サンドボックス解除と表現しない |
| Codex | Codex: 承認と実行制限を解除 | チャット OFF：`on-request`＋`workspace-write`。ON：`never`＋`danger-full-access` |
| Cursor | Cursor: 承認と実行制限を解除 | OFF：`--auto-review --sandbox enabled`。ON：`--force --sandbox disabled` |
| カスタムエージェント | `{descriptor.displayName}: 起動時の権限設定` | 「このエージェントの起動設定に従います。許可範囲はエージェント設定を確認してください。」 |

根拠として確認した経路：

- Claude のチャット起動：`DashboardFeature/Environment/AppEnvironment.swift:237`。
- Claude のターミナル向け設定生成：`macos/App/CompositionRoot.swift:503`。
- Codex のチャット起動：`SessionSpawnService.appServerPolicies(defaults:)`。
- Codex のターミナル起動：`AgentRegistry` の解除引数と `AgentLaunchPlanner`。OFF は解除引数を付けない経路であり、チャットと同じ固定の2設定を必ず送るとは説明しない。
- Cursor：`AgentRegistry` の起動引数と `CursorChatClient` の `.autoReview`／`.runEverything`。

共通 footer は「変更は次回セッション開始から反映されます。承認方式と実行制限はエージェントごとに異なります。解除は信頼できるプロジェクトでのみ有効にしてください。」とする。

説明は Phlox が設定する起動条件を示す。再開済みセッションやバックエンドが最終的に適用した実効権限まで確認済みと見せない。

### 未知値と動的データ

- 未知の権限値・プロフィール ID は原文を表示し、説明を「この設定値の詳細は未確認です。エージェントの設定を確認してください。」とする。
- `nil`、未設定、未知値を「フルアクセス」や「安全」と推測しない。
- 既知値の日本語ラベルと raw value を併記してよい。Picker の `.tag` は raw value のまま維持する。
- 製品名、モデル名、エージェント出力、ユーザー入力、カスタム設定名へ辞書置換を適用しない。
- 英語の権限説明も同じ区別を保つ。新しい英語説明の逐語的な期待値は未確定のため、PM がテスト作成時に確定する。Cursor に翻訳判断を委ねたまま凍結しない。

### 不変条件

- 入力、送信、停止、コピー、承認・拒否・キャンセルの action と実行条件を維持する。
- メニューの項目集合・順序、内部値、選択 Binding、Plan の排他制御を維持する。
- `BypassToggleRow` の `AppStorage(wrappedValue: true, descriptor.bypassKey)` を維持する。文言修正を理由に既定値を変更しない。
- 権限の保存キー、設定ファイル形式、バックアップ、未知キー保持、CLI 引数、クライアント生成を変更しない。
- 表示・言語切替・説明閲覧だけで設定を書き込まない。
- エージェント管理の対象選択と設定グループの配置を維持する。
- 日本語が長くなった場合は説明の折り返しを許す。文字を極端に縮小したり、説明を常時省略したりして収めない。
- AX identifier、既存のクリック領域、フォーカス表示、キーボード操作を維持する。

## 成功基準

### 1. Swift Testing：文言と権限説明を凍結する

PM が新設する2つの受け入れテストから、パッケージ内の実際の文言 API を呼ぶ。

**一般文言**

- 対象表の日本語を逐語比較する。
- 日本語・英語を明示して取得でき、3つの入力欄で同じキーを使う。
- 未対応言語のフォールバックを固定する。
- 数値テンプレートの値・順序を固定する。既存の丸めや金額表示を変えない。
- 入力言語を変えて再取得した際に、最初の言語を保持する不適切なキャッシュがない。

**権限説明**

- 対応表の各行を、エージェント・設定種類・内部値を明示して逐語比較する。
- Claude の `default`／`manual` の表示上の対応を確認する。送信値の書き換えは要求しない。
- Claude の `dontAsk` と `bypassPermissions` を同一説明にしない。
- Codex の `never` と `danger-full-access` を同一説明にしない。
- Codex の承認方針とサンドボックスを独立して説明できる。
- Cursor の `ask` と承認設定を混同しない。
- 組み込み3エージェントの ON/OFF 説明と、カスタム・未知値の説明を固定する。
- 期待値は契約から転記する。製品の辞書・`allCases`・実際の出力から期待集合を生成しない。

実装前に、未実装を原因とする RED を確認する。環境エラーや無関係な既存テスト失敗を RED の代用にしない。

### 2. Ruby：実際の UI 接続と不変条件を検査する

`.claude/scripts/task48-wiring.rb` を PM が作成・凍結する。

**固定基準**

- `TASK48_BASELINE` に明示的なコミット SHA を必須とする。
- `tasks/task-48.md` の `baseline_commit` と解決後の SHA が一致すること。
- 未設定、プレースホルダ、無効 SHA、ブランチ名、`HEAD`・`HEAD~…`、blob 取得失敗は非ゼロ終了。
- `git show <固定SHA>:<path>` で実装前の対象ファイルを取得し、現在の作業ツリーと比較する。
- 基準が HEAD の祖先で、基準時点には今回の実装がないことを確認する。
- 凍結対象のテストと rb 自身が、凍結 SHA の blob と一致すること。
- 凍結直後の HEAD 上に未コミット実装がある通常運用は許す。「SHA が現在の HEAD と等しい」という理由だけでは拒否しない。実装後の内容を基準にした自己比較を拒否する。

**UI への接続**

- 対象表をファイル・描画位置・文言キーの組として固定する。
- 対象リテラルが該当 UI の表示位置から消え、対応する正本参照に置き換わったことを検査する。
- コメント、未使用関数、ダミー文字列、`if false` の中に正本参照を追加しても合格にしない。
- コントロール自体の削除、英語だけの分岐への移動、通常メニューだけの修正を拒否する。
- 入力欄3経路、通常・省略メニュー、選択中ラベル、コピーの help・AX ラベルをそれぞれ検査する。
- 権限表示が正しいエージェント・設定種類・内部値を渡していることを検査する。
- App の権限行で、旧来の汎用説明を表示し続けていないことを検査する。
- 権限以外の設定行や動的なモデル名は、従来の供給元を維持する。

**実装前 blob との比較**

許容差分は文言参照、言語の受け渡し、権限説明の描画だけに限定する。action、Binding、tag、条件、保存値、数値計算、動的データの供給式は固定基準と比較する。

文字列中の空白や補間を消す正規化で差分を隠さない。ソース構造を切り出せない場合は成功にせず失敗する。

**`--selftest`**

実ファイルを書き換えず、本番と同じ検査関数へメモリ上の fixture を渡す。

- 正例：契約どおりの全置換、raw value・動的出力の維持、許容した折り返し。
- 負例：旧文言を1箇所だけ残す、間違った文言キー、正本未使用、コントロール削除。
- 負例：省略メニューだけ未修正、言語の固定、`dontAsk` と bypass の説明交換。
- 負例：Codex の2設定の混同、Cursor の動作モードへの権限説明流用。
- 負例：tag・Binding・既定値・action の改変。
- 負例：固定 SHA の欠落・不正・契約との不一致・実装後自己比較・凍結検査の改変。
- 負例は正例に違反を1つだけ加えて作る。他の失敗が検出を代行しないことを確認する。

### 3. 既存の凍結検査との衝突を解消する

調査で次の固定を確認した。

| 既存検査 | 衝突する対象 |
|---|---|
| `ComposerModeMenuAcceptanceTests.swift` | `Bypass`・`Full Access` 等の英語タイトル |
| `AcceptanceContextPopoverBranchTests.swift` | コンテキスト容量の英語テンプレート |
| `.claude/scripts/task13-wiring.rb` | `Text("Projects")` を前提とする配線検査 |
| `.claude/scripts/task35-wiring.rb`・`task38-wiring.rb` | SettingsView の Section 内容、footer、`BypassToggleRow` の固定比較 |

PM は実装前に表示変更として改訂する。項目集合、順序、内部値、計算、配色、クリック領域、設定の保存先の検査は維持する。

旧検査が rb 自身の blob 同一性を要求する場合、その契約も改訂する。旧製品との比較 SHA と改訂検査の凍結 SHA を区別し、実装後 SHA への差し替えで回帰検査を無効化しない。改訂対象・理由・保持した検査・新しい凍結基準を PM が記録する。

この調整が未完了のまま Cursor へ渡さない。

### 4. 検証コマンド

凍結後、PM は設定済みの正本スクリプトを使う。

```sh
~/.agents/scripts/compact-test task48-packages bash macos/scripts/run-swift-tests.sh DesignSystem SessionFeature DashboardFeature AgentConfigKit
~/.agents/scripts/compact-test task48-wiring-selftest ruby .claude/scripts/task48-wiring.rb --selftest
~/.agents/scripts/compact-test task48-wiring env TASK48_BASELINE=<凍結SHA> ruby .claude/scripts/task48-wiring.rb
~/.agents/scripts/compact-test task48-integration bash .claude/verify.sh
```

App ビルドは作業ディレクトリを `macos` とし、今回専用の DerivedData を指定する。

```sh
~/.agents/scripts/compact-test task48-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用の絶対パス> -destination platform=macOS build
```

- 現在の `.claude/verify.sh` は8パッケージ、更新隔離検査、`git diff --check` を実行する。task48 の rb は現状では含まれていない。
- 改訂した旧配線検査も、それぞれの固定基準を指定して実行する。
- App のコンパイル成功をパッケージテストで代用しない。
- 独立した lint・静的解析設定は今回の調査では確認できず。PM が凍結時に再確認し、未設定・対象外・実行不能を区別する。
- 検査に実エージェント起動が含まれるか PM が確認し、課金起動が必要な検査を本契約のゲートへ混入させない。

### 5. PM 目視ゲート：課金なしの隔離 Debug

PM は今回の変更からビルドした Debug を、専用の `PHLOX_DATA_DIR`、defaults suite、エージェント設定で隔離し、日本語で起動する。

- `-phlox.appLanguage ja` が実画面へ反映されたことを確認する。suite 指定だけで App の `@AppStorage` まで隔離できたと仮定しない。
- `sessions.json` の復元失敗プレースホルダでチャットを表示する。これは PM 確認済みの経路を使う。
- 実コードでも `SessionSpawnService.makeRestoreErrorChatSession` が `DisconnectedStructuredAgentClient` を使う経路を確認した。起動・再開・送信を追加する必要はない。
- 単体・グリッドで「メッセージを入力」が一致し、「エラー」の見出しとエラー本文が欠けず表示されることを撮影する。
- チーム入力欄を表示できる画面では同じ文言を確認する。到達にセッション開始が必要なら課金起動せず、その表示確認だけ未検証として記録する。
- 設定の「エージェント」グループから「権限」Section を開き、組み込み3エージェントの説明が異なり、ON/OFF の意味と反映時期を読めることを確認する。
- 標準設定寸法 `520 × 640` で、説明の折り返し、末尾へのスクロール、切れ・重なりを確認する。
- 権限を切り替える必要はない。開く前後の設定値を比較し、説明閲覧だけで値が変わらないことを確認する。
- 製品名・モデル名・エラー本文を日本語文言の残留検査から除外し、原文が維持されていることを確認する。
- 英語でも同じプレースホルダを表示し、入力欄と変更対象ラベルの言語追随を確認する。
- 承認ボタンや出力カードの撮影のために実エージェントを起動しない。それらの必須判定は Swift Testing と配線検査で行い、目視範囲とは分けて報告する。

証拠は `docs/agent-output/visual-task-48.md` に、コミット、言語、PID、実行ファイル、ウィンドウ、表示経路とともに PM が記録する。終了時は今回起動した不要なプロセスだけを停止し、他の Debug・Release は停止しない。

## レビュー観点（Rubric）

- 単体・グリッド・チームの同じ入力操作が同じ文言を参照している。
- 通常メニューだけでなく、省略メニュー・選択中表示・help・AX ラベルまで正本へ接続している。
- Claude の承認方式、Codex の承認方針とサンドボックス、Cursor の承認方式と動作モードを混同していない。
- `never`・`dontAsk` を「すべて許可」と説明せず、Claude の bypass をサンドボックス解除と説明していない。
- 設定の説明が実際の起動経路を反映し、バックエンドの実効権限まで断定していない。
- 未知値・カスタムエージェントを安全側や解除側へ勝手に分類していない。
- 文言修正が内部値、保存先、CLI 引数、処理条件、既定値を変更していない。
- 製品名・モデル名・ユーザー入力・エージェント出力を翻訳していない。
- 言語選択が View の環境値から届き、システム言語だけを暗黙参照していない。
- 凍結検査が実装前 blob と比較し、自己比較・未使用コード・コントロール削除を拒否する。
- 既存テストの変更を PM が管理し、表示以外の回帰検査を弱めていない。
- パッケージテスト、配線検査、App ビルド、PM の目視結果を区別して報告している。
- 課金セッションを要求せず、今回対象外の状態説明まで解消済みと扱っていない。

### 分割案：凍結前に PM が確定する

一般操作のローカライズと権限説明の正確性は独立に失敗するため、次の分割を推奨する。

1. **task-48：操作文言の統一**  
   入力欄、エラー見出し、コピー、承認ボタン、メニューの一般ラベル、コンテキスト表示。`AcceptanceUIWordingTests` と一般文言の配線検査、プレースホルダ画面の目視を担当する。

2. **別タスク・番号は PM が採番：権限説明の整合**  
   本案の権限対応表、設定 Section、権限メニュー、エージェント管理の説明。task-48 の文言正本へ依存し、`AcceptancePermissionWordingTests` と専用配線検査、設定画面の目視を担当する。

3. **追加の別タスク候補：生成・保存される状態説明**  
   `Approval requested`、システムエラー、ターミナル状態、データへ埋め込む `Sub-agent` を扱う。原文とアプリ生成文言を区別して契約化する。

分割する場合、本案を一括凍結せず、各契約の `acceptance_tests`・`allowed_paths`・固定 SHA・成功基準を担当範囲へ限定する。UX-10 全体の完了判定は、残す文言の扱いを PM が確定した後に行う。