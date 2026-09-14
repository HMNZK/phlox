---
id: task-50
difficulty: standard
depends_on: [task-48]
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptancePermissionWordingTests.swift
  - .claude/scripts/task50-wiring.rb
baseline_commit: "17c2532"
contract_tests: []
allowed_paths:
  - macos/Packages/DesignSystem/Sources/DesignSystem/UIWording+Permissions.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ComposerSettingsControls.swift
  - macos/App/SettingsView.swift
  - macos/App/AgentConsole/Claude/ClaudePermissionsPane.swift
  - macos/App/AgentConsole/Codex/CodexSettingsPane.swift
  - macos/App/AgentConsole/Cursor/CursorPermissionsPane.swift
  - macos/App/AgentConsole/Cursor/CursorSettingsPane.swift
  - docs/agent-output/task-50.md
---

## 目的

UX-10 のうち、権限説明を実際の設定・起動経路に整合させる。Claude Code の権限モード、Codex の承認方針と実行制限、Cursor の承認方式と動作モードを区別し、同じ意味でない設定を「フルアクセス」「安全モード」で一括説明しない。

対象は権限メニュー、設定画面の権限 Section、エージェント管理の権限説明。既存草案の対応表と調査結果を再利用し、関連する描画・設定・起動処理を実ファイルで再確認した。本起草ではファイル変更、テスト作成・実行、App ビルド、目視確認を行っていない。

## 入出力契約

### 事前条件・担当

- task-48 の検証・目視ゲートが完了した実装を取り込んでから着手する。task-36・task-38 の管理画面と設定グループ構造は推移的な前提として維持する。
- 実装担当は Cursor。受け入れテストと配線検査は PM が作成・凍結する。Cursor はテストを書かず、変更もしない。
- `baseline_commit` は task-48 の完成実装と task-50 の凍結テスト・検査を含み、task-50 の実装を含まないコミットにする。
- 調査中に他作業による `SettingsView.swift` のボタン様式変更を観測した。PM は凍結前に最新の対象コードと旧検査を再照合し、その変更を保持する。
- `allowed_paths` にテスト、契約、台帳、検証スクリプト、設定モデル、起動処理を含めない。
- App ターゲットへテストを追加しない。表示判断は DesignSystem 内の Swift Testing、App への接続は専用 Ruby 検査で扱う。
- 課金セッション、実エージェントの起動・再開・送信を要求しない。

### スコープ外

- 入力欄、コピー、承認ボタン、コンテキスト表示などの一般文言は task-48 が担当済み。変更しない。
- **旧草案の分割案3「生成・保存される状態説明」は、PM 裁定により UX-10 の範囲外。** `Approval requested`、システムエラー、ターミナル状態、データへ埋め込む `Sub-agent` の生成・保存・移行を扱わない。
- CLI の権限仕様修正、バージョン互換対応、実効権限の検出、設定値の補正、保存形式変更、既定値変更を行わない。
- エージェント管理の成功通知など、操作後に生成される状態説明の全面翻訳は含めない。

### 正本・所有境界

新設する `UIWording+Permissions.swift` に `UIWording` の公開拡張を置く。新設ファイル・追加 API は契約要求であり、既存実装ではない。

- 権限表示の入力は最低限「エージェント」「設定種類」「内部値」「言語」を区別する。`auto`・`ask` などの文字列だけで横断変換しない。
- 表示名と説明を取得できること。設定の起動権限行では、エージェント名、行ラベル、OFF 説明、ON 説明を取得できること。
- 言語選択は task-48 の規則を再利用する。`UIWording.swift` を変更せず、一般ラベルと Plan 表示は既存正本を参照する。
- 純粋な文言選択とし、保存先、クライアント、プロセス、ネットワーク、時計へ依存しない。
- 公開 API の名前・引数型と英語文言は PM がテスト作成時に確定し、凍結する。翻訳判断を未確定のまま Cursor へ委ねない。
- 下表の日本語文言は逐語期待値。英語でも各設定の区別、未知値の扱い、反映時期を同じ意味で保持する。既存英語名を維持する箇所は表で指定する。

task-48 と `allowed_paths` が交差するのは **`ComposerSettingsControls.swift` だけ**。`depends_on: [task-48]` により逐次化し、task-48 が変更した一般文言・言語受け渡しを保持する。他の製品ファイル、正本ファイル、テスト、配線検査、報告ファイルは分離する。

### Claude Code：権限モード対応表

対象は既存の `composerModeOptions(for:codexProfileIDs:)` と選択中ラベル、通常・省略メニュー。既存の選択値・順序を維持し、表示だけを変更する。

| 内部値 | 日本語表示名 | 日本語説明 | 英語表示名 |
|---|---|---|---|
| `default`／`manual` | 手動承認 | 読み取り以外は権限ルールに従って承認を求めます。実行範囲の制限とは別の設定です。 | Manual |
| `acceptEdits` | 編集を自動承認 | ファイル編集などを自動承認します。すべてのコマンド実行を承認する設定ではありません。 | Accept Edits |
| `auto` | 自動判定 | Claude Code が操作を判定します。すべての操作を無条件に許可する設定ではありません。 | Auto |
| `bypassPermissions` | 承認確認を省略 | 通常の承認確認を省略します。サンドボックスの解除を意味する設定ではありません。 | Bypass |
| `dontAsk` | 承認が必要な操作を拒否 | 事前に許可された操作などを実行し、承認が必要な操作は確認せず拒否します。 | Don't Ask |
| `plan` | 計画 | 調査と計画を行うモードです。編集を進めるモードとは区別されます。 | Plan |

`default` は表示対応のみ追加し、既存メニューへ項目を増やさない。送信値 `manual` を書き換えない。`dontAsk` の既存キャプションも正本の説明へ置換する。

権限モードとサンドボックスの区別、`manual` の別名、`dontAsk` の扱いは公式資料でも確認した。利用端末の CLI バージョンと実効権限は未検証。[Claude Code の権限モード](https://code.claude.com/docs/en/permission-modes)

### Codex：承認方針・実行制限・プロフィール

`CodexSettingKey` の `approval_policy` と `sandbox_mode` を別設定として扱う。

| 設定／内部値 | 日本語表示名 | 日本語説明 |
|---|---|---|
| `approval_policy=untrusted` | 信頼対象外の操作を確認 | 自動実行できる操作以外は承認を求めます。実行範囲はサンドボックス設定に従います。 |
| `approval_policy=on-request` | 必要時に承認を要求 | Codex が必要と判断したときに承認を求めます。実行範囲はサンドボックス設定に従います。 |
| `approval_policy=never` | 承認を要求しない | 承認を求めず、設定された実行制限の範囲で動作します。実行制限を解除する設定ではありません。 |
| `approval_policy=granular` | 項目別の承認設定 | 承認要求の種類ごとに扱いを定める設定です。この名前だけでは具体的な許可範囲は分かりません。 |
| `sandbox_mode=read-only` | 読み取り専用 | サンドボックス内での書き込みを制限します。承認を求める条件は別の設定です。 |
| `sandbox_mode=workspace-write` | 作業領域への書き込み | 作業領域など、設定された範囲への書き込みを許可します。ネットワークや保護対象の制限は別途適用されます。 |
| `sandbox_mode=danger-full-access` | サンドボックス制限なし | Codex のサンドボックスによる実行制限を外します。承認を求める条件は別の設定です。 |

承認の要否と実行範囲を別軸として表示する。`never` を「すべて許可」と説明しない。[Codex の承認と実行制限](https://learn.chatgpt.com/docs/agent-approvals-security)

コンポーザーのプロフィール表示は次に固定する。

| ID | 日本語表示名 | 英語表示名 | 日本語説明 |
|---|---|---|---|
| `:read-only` | 読み取り専用 | Read Only | 読み取り専用のプロフィールです。承認方針の詳細はエージェントの設定を確認してください。 |
| `:workspace` | 作業領域への書き込み | Auto | 作業領域への書き込みを許可するプロフィールです。承認方針の詳細はエージェントの設定を確認してください。 |
| `:danger-full-access` | 承認なし・実行制限なし | Full Access | 承認と実行制限を解除するプロフィールです。適用内容はエージェントの設定を確認してください。 |
| `nil` | 承認設定 | Approval | プロフィールは未選択です。実際の適用内容はエージェントの設定を確認してください。 |

- プロフィールの列挙元・順序は既存のサーバー由来一覧を維持する。起動時 Toggle の状態からプロフィール一覧を作らない。
- `granular` が現在の設定モデルに存在することと、利用端末の CLI がその文字列形式を受理することは別。後者は未検証であり、本タスクでは保存形式を変更しない。
- プロフィール ID から、契約で定めていない細かな承認方針・ネットワーク許可を推測しない。

### Cursor：承認方式・実行制限・動作モード

`CursorSettingKey` の `approvalMode` と `sandbox.mode`、コンポーザーの動作モードを別設定として扱う。

| 設定／内部値 | 日本語表示名 | 日本語説明 |
|---|---|---|
| `approvalMode=allowlist` | 許可リストで確認 | 許可リスト外の操作では確認を求める設定です。サンドボックス設定とは別です。 |
| `approvalMode=unrestricted` | 承認確認を省略 | 操作の承認確認を省略する設定です。サンドボックス設定とは別です。 |
| `approvalMode=auto-review` | Cursor の自動判定 | Cursor の判定に従って操作を実行します。Claude の権限モードや Codex の承認方針とは別の設定です。 |
| `sandbox.mode=enabled` | 実行制限を有効化 | コマンドをサンドボックス内で実行する設定です。 |
| `sandbox.mode=disabled` | 実行制限を無効化 | サンドボックスによる実行制限を無効にする設定です。 |
| 動作モード `nil` | エージェント | 通常の作業モードです。承認方式や実行制限を選ぶ項目ではありません。 |
| 動作モード `ask` | 質問 | 質問向けの動作モードです。承認方式を選ぶ項目ではありません。 |
| 動作モード `plan` | 計画 | 計画向けの動作モードです。承認方式や実行制限を選ぶ項目ではありません。 |

動作モードの英語表示名は `Agent`・`Ask`・`Plan` を維持する。Cursor の `ask` に Claude の承認ルール説明を流用しない。

承認方式の説明は実コードの `CursorSettingKey.explanation` と起動引数に基づく。サーバー側判定の詳細は未検証。CLI の拒否ルールが許可ルールより優先される点は公式資料でも確認した。[Cursor CLI の権限](https://cursor.com/docs/cli/reference/permissions)

### 設定画面の権限 Section

`SettingsView.swift` の `BypassToggleRow` と権限 footer を変更する。各行に OFF・ON の説明を表示し、現在値だけの説明で反対側の意味を隠さない。

| 対象 | 行ラベル | OFF の説明 | ON の説明 |
|---|---|---|---|
| Claude Code | Claude Code: 承認確認を省略 | 次回開始時に自動判定（auto）を指定します。 | 次回開始時に承認確認の省略（bypassPermissions）を指定します。サンドボックスの解除を意味しません。 |
| Codex | Codex: 承認と実行制限を解除 | チャットでは on-request と workspace-write を指定します。ターミナルでは解除引数を付けず、Codex の設定に従います。 | チャットでは never と danger-full-access を指定します。ターミナルでは承認とサンドボックスの解除引数を付けます。 |
| Cursor | Cursor: 承認と実行制限を解除 | 次回開始時に --auto-review と --sandbox enabled を指定します。 | 次回開始時に --force と --sandbox disabled を指定します。 |
| カスタム | `{descriptor.displayName}: 起動時の権限設定` | このエージェントの起動設定に従います。許可範囲はエージェント設定を確認してください。 | このエージェントの起動設定に従います。許可範囲はエージェント設定を確認してください。 |

根拠として実コードで確認した経路：

- Claude チャット：`DashboardFeature/Environment/AppEnvironment.swift` の `permissionMode` 選択。
- Claude ターミナル用設定：`macos/App/CompositionRoot.swift` の `defaultMode` 選択。
- Codex チャット：`SessionSpawnService.appServerPolicies(defaults:)`。
- Codex・Cursor ターミナル：`AgentDescriptor.swift` の `AgentRegistry` と `AgentLaunchPlanner.swift` の引数合成。
- Cursor チャット：`CursorChatClient` の `.autoReview`・`.runEverything`。

共通 footer は次に固定する。

> 変更は次回セッション開始から反映されます。承認方式と実行制限はエージェントごとに異なります。解除は信頼できるプロジェクトでのみ有効にしてください。

説明は Phlox が指定する起動条件を示す。再開済みセッションやバックエンドが実際に適用した権限まで確認済みと表現しない。

### エージェント管理への接続

| ファイル | 変更する表示 |
|---|---|
| `ClaudePermissionsPane.swift` | 権限ルールの画面説明、バケット見出し・選択ラベル・説明 |
| `CursorPermissionsPane.swift` | 権限ルールの画面説明、バケット見出し・選択ラベル・説明 |
| `CodexSettingsPane.swift` | 承認方針・サンドボックスの項目名、選択肢ラベル、現在値の説明 |
| `CursorSettingsPane.swift` | 承認方式・サンドボックスの項目名、選択肢ラベル、現在値の説明 |

権限以外の設定行は従来の `key.displayName`・`key.explanation`・選択肢供給元を維持する。

項目名は「承認方針」「承認方式」「実行制限（サンドボックス）」とし、設定種類を区別する。値の説明は対応表から取得し、現在値の近傍に常時表示する。

ルール区分は次に固定する。

| エージェント／区分 | 日本語名 | 日本語説明 |
|---|---|---|
| Claude／`allow` | 許可 | 確認なしで実行を許可するルールです。拒否ルールなど、他の権限設定も適用されます。 |
| Claude／`ask` | 確認する | 実行前に確認を求めるルールです。確認できないモードでは実行が拒否される場合があります。 |
| Claude／`deny` | 拒否 | 実行を拒否するルールです。許可ルールより優先されます。 |
| Cursor／`allow` | 許可 | 確認なしで実行を許可するルールです。拒否ルールが優先されます。 |
| Cursor／`deny` | 拒否 | 実行を拒否するルールです。許可ルールより優先されます。 |

画面説明には、Claude が `~/.claude/settings.json` の `permissions`、Cursor が `~/.cursor/cli-config.json` の `permissions` を編集することを残す。ルール編集と起動時 Toggle が別設定であることを説明する。

ルール本文、設定キー、パス、追加・移動・削除の action、保存処理、成功通知の生成経路は変更しない。

### 未知値・未設定

- 未知の値・プロフィール ID は原文を表示し、説明を「この設定値の詳細は未確認です。エージェントの設定を確認してください。」とする。
- Codex・Cursor の設定値が未設定なら表示名は「既定（未設定）」、説明は「値は未設定です。適用される既定値はエージェントの設定を確認してください。」とする。
- Cursor の動作モード `nil` は表どおり `Agent` を意味する。一般の未設定フォールバックへ流さない。
- Codex プロフィール `nil` は表どおり未選択として扱う。
- Claude の選択中表示で既存処理が補う `bypassPermissions` は、その既存処理を維持する。正本自体に汎用の `nil → bypass` 規則を作らない。
- 未知値を安全側・解除側へ分類しない。未知値の選択肢保持、Picker の raw value と tag を維持する。

### 不変条件

- `BypassToggleRow` の `AppStorage(wrappedValue: true, descriptor.bypassKey)`、既定値 `true`、Binding を維持する。
- 権限値、保存キー、設定形式、バックアップ、未知キー保持、CLI 引数、クライアント生成を変更しない。
- メニューの項目集合・順序、選択条件、Plan の末尾配置・排他制御を維持する。
- 設定の5グループ、Section の所属・順序、エージェント管理の選択・保存処理を維持する。
- 表示や説明閲覧だけで設定を書き込まない。
- 長い説明は折り返す。常時省略や極端な縮小で収めない。
- AX identifier、既存の操作領域、フォーカス、キーボード操作、ボタン様式を維持する。

## 成功基準

### 1. Swift Testing

PM が `AcceptancePermissionWordingTests.swift` を作成・凍結する。

- 権限対応表、プロフィール、起動時 ON/OFF、バケット説明、未知値・未設定を、日本語・凍結した英語のリテラルと逐語比較する。
- エージェント・設定種類・内部値を明示して実際の公開 API を呼ぶ。
- Claude の `default`／`manual` の表示対応と、`dontAsk`／`bypassPermissions` の説明の違いを検査する。
- Codex の `never` と `danger-full-access`、設定値とプロフィール ID を混同しないこと。
- Cursor の動作モード `ask` と承認方式、Claude の `ask` ルールを混同しないこと。
- 組み込み3エージェントとカスタムの起動説明を検査する。
- 同じ raw value を別のエージェント・設定種類で問い合わせる負例、未知値、各 `nil` の意味を検査する。
- 日本語・英語・未対応言語、言語変更後の再取得を検査する。
- task-48 の一般文言テストも回帰として通ること。
- 期待値を製品辞書・`allCases`・実行結果から生成しない。

### 2. 専用 Ruby 配線検査

PM が `.claude/scripts/task50-wiring.rb` を作成・凍結する。

**固定基準**

- `TASK50_BASELINE` を必須とし、契約の `baseline_commit` と解決後の SHA が一致すること。
- 未設定、プレースホルダ、無効 SHA、ブランチ名、`HEAD`・`HEAD~…`、必要な blob 取得失敗を非ゼロ終了にする。
- 凍結 SHA は task-48 完成実装を含み、task-50 実装前で、現在の HEAD の祖先であること。
- `git show <凍結SHA>:<path>` と作業ツリーを比較する。新設 `UIWording+Permissions.swift` の基準時点での不在は明示的に扱う。
- テストと rb 自身を凍結 SHA の blob と照合する。
- 実装後 HEAD の自己比較は禁止。凍結直後の HEAD と SHA が等しいだけでは拒否しない。

**表示接続**

- 通常・省略メニュー、選択中ラベル、説明位置をそれぞれ検査する。
- 実際の `agentRef`、設定種類、内部値、表示言語を正本へ渡していること。
- Claude の `dontAsk` だけでなく、契約対象の各選択肢の説明を表示できること。
- 設定の行が descriptor ごとの ON/OFF 説明を使い、旧共通 footer と旧「フルアクセス（bypass）」を表示し続けていないこと。
- エージェント管理では対象設定だけが正本を使い、権限以外の行は従来の供給元を保つこと。
- コメント・未使用コード・ダミー文字列・`if false` への参照追加を合格にしない。
- コントロール削除、動的エージェントの固定3行化、未知値の脱落を拒否する。

**実装前 blob との比較**

- 許す差分は担当表示位置の文言参照、言語受け渡し、説明の描画・折り返しに限定する。
- action、Binding、tag、項目集合・順序、既定値、保存処理、起動引数を保護する。
- `ComposerSettingsControls.swift` の task-48 所有の一般文言接続を task-50 の基準 blob と比較して保持する。
- `SettingsView.swift` の権限表示以外の Section・ボタン様式・設定処理を保持する。
- 文字列内の空白・補間を消して比較しない。構文切り出し失敗は検査失敗とする。

**`--selftest`**

実ファイルを変更せず、本番と同じ検査関数を使う。

- 正例：契約どおりの接続、説明の折り返し、raw value・未知値の保持。
- 負例：通常メニューだけ修正、省略メニュー・選択中ラベル・管理画面の説明が旧文言。
- 負例：Claude の `dontAsk` と bypass の説明交換。
- 負例：Codex の承認方針と実行制限の混同、Cursor の動作モードへ承認説明を流用。
- 負例：カスタムエージェントの「フルアクセス」扱い、未設定から権限を推測。
- 負例：Binding・tag・既定値・action・起動引数の改変、表示時の保存処理追加。
- 負例：task-48 の一般文言の巻き戻し、コントロール削除、未使用の正本参照。
- 負例：固定 SHA の欠落・不正・不一致、実装後自己比較、凍結テスト・rb の改変。
- 各負例は正例へ違反を1つだけ加え、その違反を原因に失敗すること。

### 3. 既存検査との整合

PM が実装前に改訂し、検査の省略や失敗無視で通さない。

- `ComposerModeMenuAcceptanceTests.swift`：日本語と英語を明示し、変更後の値名を検査する。項目集合・順序・内部値・Plan を維持する。
- `.claude/scripts/task35-wiring.rb`・`task38-wiring.rb`：権限 Section、footer、`BypassToggleRow` の表示変更だけを許す。テーマ、分類、保存先、既定値、action、ボタン様式の検査を維持する。
- 旧製品との比較 SHA と改訂検査の凍結 SHA を分け、改訂理由と保持した検査を PM が記録する。
- task-48 のテスト・rb は変更せず再実行する。共有ファイルの一般文言と共通不変条件を引き続き検査できること。
- この調整が未完了なら Cursor へディスパッチしない。

### 4. 自動検証と App ビルド

以下は凍結後の実行要求であり、本起草では未実行。

```sh
~/.agents/scripts/compact-test task50-wiring-selftest ruby .claude/scripts/task50-wiring.rb --selftest
~/.agents/scripts/compact-test task50-wiring env TASK50_BASELINE=<task-50凍結SHA> ruby .claude/scripts/task50-wiring.rb
~/.agents/scripts/compact-test task50-task48-selftest ruby .claude/scripts/task48-wiring.rb --selftest
~/.agents/scripts/compact-test task50-task48-regression env TASK48_BASELINE=<task-48凍結SHA> ruby .claude/scripts/task48-wiring.rb
~/.agents/scripts/compact-test task50-integration bash .claude/verify.sh
```

改訂した旧配線検査も、個別の固定基準と `--selftest` で実行する。設定済みのパッケージテストは既存の正本スクリプトを使う。

App ビルドは `macos` を作業ディレクトリとして実行する。

```sh
~/.agents/scripts/compact-test task50-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用の絶対パス> -destination platform=macOS build
```

PM は凍結時の品質設定を再確認し、未設定・対象外・実行不能を区別して記録する。App ビルド成功を SwiftPM テストや目視で代用しない。

### 5. PM 目視ゲート：設定画面

- 今回の変更からビルドした隔離 Debug を使う。データ、defaults、エージェント設定の実際の保存先を確認し、通常環境を保護する。
- 設定の「エージェント」グループを開き、権限 Section の組み込み3エージェントで説明が異なること、OFF・ON の意味と反映時期が読めることを撮影する。
- 設定コンテンツの標準寸法 `520 × 640` で、折り返し、末尾へのスクロール、切れ・重なりを確認する。
- カスタムエージェントは隔離設定に用意した非起動の descriptor で表示し、汎用の「フルアクセス」説明にならないことを確認する。
- エージェント管理の対象4画面を、隔離された設定データで開く。承認方式・実行制限・ルールの説明が区別され、長文が欠けないことを確認する。
- 日本語と英語で表示し、権限文言が表示言語へ追随すること。
- Toggle・Picker・ルールの保存操作を行わない。開く前後で権限キーの値・有無と設定ファイルを比較し、説明閲覧だけで変更されないことを確認する。
- 実エージェントを起動して実効権限を試す検査は要求しない。権限メニューの必須判定は Swift Testing と Ruby が担当し、目視範囲と区別する。
- 証拠は PM が `docs/agent-output/visual-task-50.md` にコミット、言語、PID、実行ファイル、画面、寸法、設定の前後比較とともに記録する。
- 終了時は起動元と親子関係を確認し、今回起動した不要なプロセスだけを停止する。

必須画面の到達、説明の可読性、閲覧前後の非変更を確認できない場合は未達とし、自動検査だけで完了としない。

## レビュー観点（Rubric）

- Claude の権限モード、Codex の承認方針と実行制限、Cursor の承認方式と動作モードを区別している。
- `never`・`dontAsk` を「すべて許可」、Claude の bypass をサンドボックス解除と説明していない。
- 通常・省略メニュー、選択中ラベル、設定 Section、エージェント管理が同じ権限正本へ接続している。
- 起動時の指定とバックエンドの実効権限を区別している。
- 未知値、未設定、Cursor の動作モード `nil`、カスタムエージェントを混同していない。
- 保存値、既定値、CLI 引数、Binding、tag、Plan の排他制御を変更していない。
- task-48 の一般文言を保持し、共有ファイルを依存順に実装している。
- 凍結 blob 比較と `--selftest` が、説明交換・誤接続・自己比較・表示削除を検出する。
- 旧検査の表示以外の回帰検査を弱めず、Cursor がテストを書き換えていない。
- 生成・保存される状態説明を UX-10 の範囲外として維持している。
- 課金セッションを要求せず、テスト・配線検査・App ビルド・目視・未検証を区別している。

## 受け入れ検査の敵対レビュー反映（2026-09-13、`docs/agent-output/task50-acceptance-adversarial.md` を PM 裁定）

- M1（正常な Codex 設定画面を誤判定）: 採択。`onAppear` から呼ばれる経路への保存追加だけを拒否し、既存の下書き同期を正例に。
- M2（凍結基準に task-48 実装が無い）: 採択（工程）。task-50 は task-48 done 後に **再凍結**し、rb は task-48 正本（`UIWording.swift`）と共有ファイルの必要接続を基準側でも検査する。
- M3（旧検査との整合）: PM 裁定。`task38-wiring.rb` は task-38 の着手時検査で後続に適用しない（task-38.md 注記）。既存 Swift テスト（`ComposerModeMenuAcceptanceTests` 等）の日英改訂は task-48 の検査修正で一括して行う（本タスクでは触らない）。
- H1〜H7・D1・D2: 採択（許可表示差分以外の凍結 blob 比較、起動条件・必要 blob の欠落を非ゼロ、未使用呼び出し・文字列偽装の拒否、ON/OFF 同時描画の正例、管理画面の各表示箇所、3 エージェント×通常・省略メニュー、環境 locale からの言語伝播、未知値・nil・言語の被覆、行数制限・固定高・縮小の拒否）。
