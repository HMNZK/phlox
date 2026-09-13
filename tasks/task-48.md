---
id: task-48
difficulty: standard
depends_on: [task-36, task-38]
user_visible: true
acceptance_tests:
  - macos/Packages/DesignSystem/Tests/DesignSystemTests/Acceptance/AcceptanceUIWordingTests.swift
  - .claude/scripts/task48-wiring.rb
baseline_commit: "2b457e6"
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
  - docs/agent-output/task-48.md
---

## 目的

UX-10 のうち、一般操作の文言を統一する。単体・グリッド・チームの入力欄が同じ文言正本を参照し、日本語・英語の表示設定に追随する。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md` の UX-10。既存の単一草案の調査結果を再利用し、対象の表示箇所と関連処理を実ファイルで再確認した。本起草ではファイル変更、テスト作成・実行、App ビルド、目視確認を行っていない。

## 入出力契約

### 事前条件・担当

- 実装担当は Cursor。受け入れテストと Ruby 配線検査は PM が作成し、未実装を原因とする RED を確認して凍結する。Cursor はテストを書かず、変更もしない。
- `allowed_paths` は製品実装と実装報告の編集許可である。契約、テスト、検査スクリプト、台帳、品質設定の変更を許可しない。
- App ターゲットへテストを追加しない。文言選択は既存の DesignSystem パッケージから Swift Testing で検査する。
- `baseline_commit` は、受け入れテストと配線検査を含み、task-48 の実装を含まないコミットへ PM が固定する。調査時 HEAD を自動採用しない。
- 調査中に他作業による HEAD と未コミット変更の更新を観測した。PM は凍結前に対象ファイルと既存検査を再照合し、他作業の変更を保持する。
- 課金セッション、実エージェントの起動・再開・送信を受け入れ条件にしない。

### スコープ外

- 権限値の表示名・説明、設定画面の権限 Section、エージェント管理の権限説明は task-50 が担当する。
- **旧草案の分割案3「生成・保存される状態説明」は、PM 裁定により UX-10 の範囲外。** `Approval requested`、`app-server system error`、ターミナル状態の `Codex is asking a question`、`ChatSubAgentModel.swift` がデータへ埋め込む `Sub-agent` を変更しない。
- 表示時に説明が空の場合だけ使う `ChatMessageCells+Structured.swift` の `Sub-agent` は一般表示の代替ラベルとして対象に含める。保存済み文字列を検索置換しない。
- 組み込み出力スタイル名、使用量区分の `Auto`、他画面の全面翻訳、既存 xcstrings の移行、状態データの変更は含めない。

### 文言正本

新設する `macos/Packages/DesignSystem/Sources/DesignSystem/UIWording.swift` に、一般文言を返す純粋な公開 API `UIWording` を置く。これは新設要求であり、既存シンボルではない。

- 表示対象と明示的な言語コードを受け取る。下表の各行を一意に指定できること。
- `en` は英語、`ja` は日本語、それ以外は日本語へフォールバックする。
- 対象 View は `@Environment(\.locale)` の言語コードを渡す。`ja-JP`・`en-US` などの地域付き Locale も同じ規則で扱う。
- `LanguageSettings.languageKey`、`AppLanguage`、`PhloxApp` の環境注入を維持する。正本から UserDefaults、`Locale.current`、プロセス環境を暗黙に読まない。
- 引数だけで結果が決まり、I/O、保存、通知、プロセス起動、ネットワーク、翻訳 API、言語を固定するキャッシュを持たない。
- 文言キーの型、関数名、引数型は PM がテスト作成時に固定する。未確定のまま Cursor へ渡さない。
- 新規パッケージ、依存、リソース読込機構を追加しない。`Package.swift`・`project.yml`・App の xcstrings を変更しない。
- task-50 は別ファイル `UIWording+Permissions.swift` の拡張として権限文言を追加する。一般文言正本の書き換えを必要としない公開面にする。

### 凍結する一般文言

次の表が期待値の正本。PM はリテラルをテストへ転記し、製品の辞書・列挙・出力から期待値を生成しない。

SessionFeature のファイル名は `macos/Packages/SessionFeature/Sources/SessionFeature/` 配下を指す。

| 表示位置 | 日本語 | 英語 |
|---|---|---|
| `ChatComposer.swift`・`GridChatColumn.swift`・DashboardFeature の `Dashboard/TeamComposer.swift` の空入力欄 | メッセージを入力 | Enter a message |
| `ChatMessageCells+Basic.swift` のエラー見出し | エラー | Error |
| `ChatMessageCells+Structured.swift` のコマンド欠損時 | コマンド | Command |
| 同ファイルの出力あり表示 | 出力あり | Output available |
| 同ファイルの説明欠損時 | サブエージェント | Sub-agent |
| `ChatCodeBlock.swift`・`RichMarkdownView.swift` のコピー操作 | コピー | Copy |
| 同2ファイルのコードコピー help | コードをコピー | Copy code |
| `ChatMessageCopyButton.swift` の help・AX ラベル | メッセージをコピー | Copy message |
| 同ファイルのコピー後表示・help・AX ラベル | コピーしました | Copied |
| `ChatCodeBlock.swift` の言語名欠損時 | テキスト | text |
| `RichMarkdownView.swift` の言語名欠損時 | コード | code |
| `ChatSessionAccessories.swift` の承認操作 | 承認 | Accept |
| 同ファイルの拒否操作 | 拒否 | Decline |
| 同ファイルのキャンセル操作 | キャンセル | Cancel |
| `ComposerSettingsControls.swift` のモデル見出し・未選択ラベル | モデル | Model |
| 同ファイルの `Effort`・`Reasoning Effort` | 思考の深さ | Reasoning Effort |
| 同ファイルの一般見出し `Permission` | 承認設定 | Permission |
| 同ファイルの未選択ラベル `Approval` | 承認設定 | Approval |
| 同ファイルの一般見出し `Mode` | 動作モード | Mode |
| 同ファイルの Plan 項目・選択中表示 | 計画 | Plan |
| 同ファイルの `low` | 低 | Low |
| 同ファイルの `medium` | 中 | Medium |
| 同ファイルの `high` | 高 | High |
| 同ファイルの `xhigh` | 非常に高 | X High |
| 同ファイルの `max` | 最大 | Max |
| 同ファイルの更新操作 | 更新 | Refresh |
| 同ファイルのブランチ欠損時 | ブランチ | Branch |
| `ComposerContextIndicator.swift` の切替失敗見出し | ブランチの切り替えに失敗しました | Branch checkout failed |
| 同ファイルの空一覧 | ローカルブランチがありません | No local branches |
| 同ファイルの容量見出し | コンテキスト容量: | Context window: |
| DashboardFeature の `Dashboard/DashboardSidebarView.swift` のプロジェクト見出し | プロジェクト | Projects |

数値を含む文言は次のテンプレートに固定する。波括弧は入力値の挿入位置であり、画面へ表示する記号ではない。

| 対象 | 日本語 | 英語 |
|---|---|---|
| コンテキスト使用率 | 使用 `{使用率}%`（残り `{残量}%`） | `{使用率}% used ({残量}% left)` |
| コンテキスト使用量 | `{使用量} / {容量}` トークン使用 | `{使用量} / {容量} tokens used` |
| 応答費用の AX ラベル | この応答の費用 `{既存の金額表示}` | Turn cost `{既存の金額表示}` |

- `ComposerContextPopoverText.lines(usedTokens:windowTokens:)` の割合計算、容量0の扱い、`tokenText(_:)` の丸めと `k` 表示を維持する。言語の受け渡しとテンプレート接続だけを変更する。
- 費用は既存の金額整形結果を渡す。通貨・小数桁・計算を変更しない。
- 未知の effort、モデル名、製品名、ブランチ名、パス、ユーザー入力、エージェント出力、エラー本文、実コマンド、実コード言語名は原文を維持する。
- `Output available` の置換で `isRunning`・空出力の条件を変更しない。既存の「実行中」はこの表の対象ではない。

### 表示への接続とタスク境界

- 3入力欄は同じ文言キーを参照する。各 View へ同じ文字列を個別に埋め込む実装は不可。
- 通常メニュー、省略メニュー、選択中表示、help、AX ラベルを対象表どおりに接続する。
- 実コードで確認した `composerModeOptions(for:codexProfileIDs:)`、`composerPermissionTitle(for:)`、`claudePermissionTitle(for:)`、`cursorModeTitle(for:)` のうち、本タスクが変更するのは一般ラベル、Plan 表示、必要な言語引数だけ。権限固有の値名・説明は task-50 に残す。
- Plan の表示は本タスクの正本を使い、task-50 でも継続使用する。`isPlan`、末尾配置、排他制御を変更しない。

両契約の `allowed_paths` の交差は、既存の通常・省略メニューが同居する **`ComposerSettingsControls.swift` だけ**とする。分割だけを目的に View を再構成しない。

| ファイル | task-48 の所有範囲 | task-50 の所有範囲 |
|---|---|---|
| `ComposerSettingsControls.swift` | 一般見出し、Plan、effort、ブランチ関連ラベル、一般文言への言語受け渡し | 権限・動作モード固有の値名、説明、権限正本への接続 |

task-50 の `depends_on: [task-48]` で逐次化する。同ファイルを並列実装しない。

### 不変条件

- 入力、送信、停止、コピー、承認、拒否、キャンセル、更新、ブランチ切替の action と条件を維持する。
- 項目集合、順序、Binding、tag、内部値、保存キー、既定値、CLI 引数を変更しない。
- コピー対象の本文・コード、成功表示の時間、アニメーションを維持する。
- コンテキスト数値計算と金額計算を維持する。
- AX identifier、クリック領域、フォーカス表示、キーボード操作、配色を維持する。
- 言語切替・表示だけで設定やセッション状態を書き換えない。

## 成功基準

### 1. Swift Testing

PM が `AcceptanceUIWordingTests.swift` を作成・凍結する。

- 表の一般文言と数値テンプレートを、日本語・英語それぞれ逐語比較する。
- 未対応言語の日本語フォールバックと、言語を変えて再取得した結果を検査する。
- 3入力欄が参照する共通キーの日本語・英語を検査する。実 View の接続は Ruby で別途検査する。
- 数値テンプレートへ異なる値を渡し、値の欠落・逆転・固定値化を検出する。
- 計算の回帰は既存の `AcceptanceContextPopoverBranchTests.swift` を維持し、PM が必要な言語引数と表示期待値だけを改訂する。
- 期待集合は契約のリテラルから作る。製品出力との自己比較を行わない。

### 2. Ruby 配線検査

PM が `.claude/scripts/task48-wiring.rb` を作成・凍結する。

**固定基準**

- `TASK48_BASELINE` を必須とし、`tasks/task-48.md` の `baseline_commit` と解決後のコミット SHA が一致すること。
- 未設定、プレースホルダ、無効 SHA、ブランチ名、`HEAD`・`HEAD~…`、必要な blob の取得失敗は非ゼロ終了。
- `git show <凍結SHA>:<path>` で実装前 blob を読み、現在の作業ツリーと比較する。
- 基準は現在の HEAD の祖先であり、task-48 の実装前であること。新設 `UIWording.swift` の基準時点での不在は、明示した新設ファイルとして扱う。
- 受け入れテストと rb 自身を凍結 SHA の blob と照合し、改変を拒否する。
- 実装後 HEAD を基準にする自己比較は禁止。凍結直後の HEAD に未コミット実装がある状態は、SHA の同値だけを理由に拒否しない。

**検査内容**

- 表の各表示位置と正本文言キーの対応を固定する。
- 3入力欄、通常・省略メニュー、選択中表示、コピー前後の表示・help・AX ラベルを個別に検査する。
- コメント、未使用関数、ダミー文字列、`if false` 内の参照で合格させない。
- コントロールの削除、対象表示条件の変更、言語の固定を拒否する。
- action、Binding、tag、内部値、項目集合・順序、計算、動的出力の供給式を実装前 blob と比較する。
- 文字列内部の空白・補間を消す正規化を使わない。構文を切り出せない場合は失敗する。
- 共有ファイルは本タスク所有の表示位置と共通の不変条件を検査する。task-50 所有の権限説明を旧英語のまま固定する検査は作らない。

**`--selftest`**

実ファイルを変更せず、本番と同じ検査関数へメモリ上の fixture を渡す。

- 正例：対象位置の正本接続、動的出力の保持、言語受け渡し。
- 負例：入力欄1箇所だけ旧文言、誤ったキー、省略メニューだけ未修正、コピー後 AX ラベルだけ未修正。
- 負例：未使用コードへの参照、コントロール削除、言語固定、数値の逆転。
- 負例：action、Binding、tag、既定値、Plan の順序・排他条件の改変。
- 負例：固定 SHA の欠落・不正・不一致、実装後自己比較、凍結テスト・rb の改変。
- 各負例は正例へ違反を1つだけ加え、その違反を原因に失敗すること。

### 3. 既存検査の改訂

PM が Cursor へのディスパッチ前に行う。

- `AcceptanceContextPopoverBranchTests.swift`：言語を明示する呼び出しへ改訂し、既存の数値・丸め・ブランチ操作の検査を維持する。
- `ComposerModeMenuAcceptanceTests.swift` と `GridComposerSettingsAcceptanceTests.swift`：一般文言・言語引数の変更に必要な箇所だけを改訂する。項目集合、順序、内部値、Plan の検査を維持する。
- `.claude/scripts/task13-wiring.rb`：`Text("Projects")` の直接記述を要求する箇所を正本参照に対応させ、文字役割・配色の検査を維持する。
- 改訂するテストは SwiftPM 内の Swift Testing に限定する。App テストを追加しない。
- 旧検査の製品比較 SHA と、改訂検査自身の凍結 SHA を区別する。実装後 SHA への差し替えで旧回帰検査を無効化しない。

### 4. 自動検証と App ビルド

以下は凍結後の実行要求であり、本起草では未実行。

```sh
~/.agents/scripts/compact-test task48-wiring-selftest ruby .claude/scripts/task48-wiring.rb --selftest
~/.agents/scripts/compact-test task48-wiring env TASK48_BASELINE=<凍結SHA> ruby .claude/scripts/task48-wiring.rb
~/.agents/scripts/compact-test task48-integration bash .claude/verify.sh
```

既存 `.claude/verify.sh` は8パッケージのテスト、更新隔離検査、`git diff --check` を実行する。改訂した旧配線検査も、それぞれの固定基準で実行する。

App ビルドは `macos` を作業ディレクトリとして実行する。

```sh
~/.agents/scripts/compact-test task48-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用の絶対パス> -destination platform=macOS build
```

PM は凍結時に適用される品質設定を再確認する。lint・型チェック・静的解析の未設定、対象外、実行不能を区別し、テスト・ビルド・目視の結果を読み替えない。

### 5. PM 目視ゲート：プレースホルダ画面

- 今回の変更からビルドした隔離 Debug を使用する。専用データディレクトリ、defaults、エージェント設定を用い、実際の保存先を確認する。
- `SessionSpawnService.makeRestoreErrorChatSession` が `DisconnectedStructuredAgentClient` を使う復元失敗プレースホルダ経路を利用する。PM は復元 fixture が実エージェント起動へ進まないことを確認する。
- 単体・グリッドの空入力欄を日本語で表示し、「メッセージを入力」が一致すること、エラー見出しと本文が欠けないことを撮影する。
- 英語でも同じ2画面を表示し、入力欄が `Enter a message`、見出しが `Error` になることを確認する。
- グリッドの狭い幅で切れ・重なり・入力領域の欠落がないこと。
- チーム入力欄は課金なしで到達できる場合に撮影する。到達できない場合はその目視のみ未検証と記録し、必須の正本接続判定は Swift Testing と Ruby で行う。
- 承認カードや出力カードの撮影を目的に実エージェントを起動しない。自動検査の対象と目視した対象を区別する。
- 証拠は PM が `docs/agent-output/visual-task-48.md` にコミット、言語、PID、実行ファイル、表示経路、ウィンドウとともに記録する。
- 終了時は今回起動した不要なプロセスだけを停止する。他セッションの Debug・Release を停止しない。

単体・グリッドの必須目視、App ビルド、自動検査のいずれかが未達なら完了としない。

## レビュー観点（Rubric）

- 3入力欄が同じ正本を参照し、明示された表示言語へ追随する。
- 通常・省略メニュー、選択中表示、help、AX ラベルの対象漏れがない。
- 数値、動的な名前・本文、操作処理、選択値を翻訳や文言統一で変更していない。
- task-50 の権限説明へ実装範囲を広げていない。
- 共有ファイルの変更が担当範囲内であり、後続 task-50 の回帰確認を妨げない。
- 固定 blob 比較と `--selftest` が、自己比較・未使用コード・表示削除を検出する。
- Cursor がテストを書き換えていない。
- 生成・保存される状態説明を UX-10 の完了対象へ戻していない。
- テスト、配線検査、App ビルド、目視の実施範囲と未検証を区別している。

## 受け入れ検査の敵対レビュー反映（2026-09-13、`docs/agent-output/task48-acceptance-adversarial.md` を PM 裁定）

- MUST1（通常メニューに無い見出しを要求）・MUST2（struct 外ヘルパーを追跡できない）: 採択。実在する位置で検査し、ファイル直下ヘルパー（`chatMarkdownTheme`・`composerPermissionTitle`）まで追跡。
- MUST3（既存検査の改訂）: PM 裁定。`task13-wiring.rb` は task-13 の着手時検査で後続に適用しない（task-13.md 注記）。既存 Swift テスト `AcceptanceContextPopoverBranchTests`・`ComposerModeMenuAcceptanceTests`・`GridComposerSettingsAcceptanceTests` の旧英語逐語期待値は、**PM 承認のもと本タスクの検査修正で言語引数付き期待値へ改訂**する（項目集合・順序・内部値・計算検査は保持。task-50 が変える権限表示名は旧英語へ固定しない）。改訂後のテストは凍結 blob に含める。
- HIGH4〜8: 採択（Text/Label/help/AX/選択中表示の引数と分岐の固定対応、環境 Locale からの言語伝播と Markdown テーマキャッシュの言語キー、操作本体・Binding・tag の baseline 比較、数値供給式・条件式の比較、必須 blob 欠落は即 NG）。
- MED9（ADR 0147 サブタイトル）: PM 裁定。単独コマンドセルのサブタイトル（実行中／出力あり）は現状維持し翻訳のために復活・削除しない。ADR 0147 への適用範囲追記はフェーズ 5。
- MED10・11: 採択（自己比較の削除、受け入れテストは `import DesignSystem` で公開 API を使用）。
