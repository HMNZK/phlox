---
id: task-51
difficulty: standard
depends_on: []
user_visible: false
acceptance_tests:
  - macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceHistoryTitleSourcesTests.swift
  - .claude/scripts/task51-wiring.rb
baseline_commit: "57bfa9e"
contract_tests: []
allowed_paths:
  - macos/Packages/SessionFeature/Sources/SessionFeature/ClaudeSessionHistoryEntry.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift
  - docs/agent-output/task-51.md
---

## 目的

UX-11「履歴を作業名で探せるようにする」のうち、表示用タイトルの材料を元の履歴から取得する。本文の改行と長さを保ち、表示側が実依頼を選べる材料を渡す。元履歴、既存の候補選定、再開先、復元本文を変更しない。

単一草案 `docs/agent-output/contract-draft-task-49.md` を PM 裁定により分割した先行契約である。表示モデルと履歴 UI は task-49 が担当する。本タスクは task-41 のタイトル導出器へ依存しない。

本草案は read-only 調査に基づく。調査時 HEAD は `0511c76e8f6ea86fab48f55cc293419f8189ba99`。ファイル変更・保存、テスト作成・実行、ビルド、GUI 確認は行っていない。

## 入出力契約

### 担当・境界

- Cursor は `allowed_paths` 内の製品実装と開示レポートを担当する。受け入れテスト、Ruby 検査、契約、品質ゲートを作成・変更しない。
- PM が本契約の固定期待値から Swift Testing と Ruby 検査を作成し、未実装による red を確認して凍結する。コンパイル段階の red とアサーションの red は区別して記録する。
- レビューは Cursor の実装モデルとは別モデルが担当する。
- 既存の `DashboardFeatureTests` を使う。App ターゲットへのテスト追加、新規パッケージ・依存・テストターゲットの追加は行わない。
- task-49 の `allowed_paths` との交差はない。タイトル導出・表示モデル・View・起動配線・履歴ルート設定を変更しない。
- `baseline_commit` と `TASK51_BASELINE` は、受け入れテストと Ruby 検査を含み、本タスクの製品実装を含まない凍結コミットに固定する。調査時 HEAD を自動採用しない。

### 確認した既存実装

| ファイル | 確認した実装 |
|---|---|
| `macos/Packages/SessionFeature/Sources/SessionFeature/ClaudeSessionHistoryEntry.swift` | Claude／Codex 共通の entry。`sessionID`、`preview`、`firstUserAt`、`lastModified`、`gitBranch`、`fileURL` を保持する |
| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift` | `ClaudeSessionHistoryDiscovery` が JSONL を走査する。`ParsedLine` は現状 `isMeta` を保持しない。`normalizedPreview` は空白を結合して120文字までにする |
| 同上 | `ClaudeSessionTranscriptLoader` が復元本文を取得する。タイトル材料向けの除外を適用してはならない |
| `macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift` | `CodexSessionHistoryDiscovery` は SQLite を優先し、利用できない場合に rollout JSONL を読む。`messageRole` と `messageText` が存在する |
| 同上 | DB の既存 preview は、非空の `threads.preview` を優先し、なければ `first_user_message` を使う。`lastModified` は `updated_at_ms` に由来する |

`threads.preview` の生成者や、常に要約として使えるかは未確認である。本契約では補助タイトル候補として扱う。

### 新規公開契約：タイトル材料

以下は既存メンバーではなく、本契約で `ClaudeSessionHistoryEntry` に追加する API である。

```swift
public let titleUserMessages: [String]?
public let titleSummary: String?
```

既存 initializer の末尾に、同名・同型・既定値 `nil` の引数を追加する。既存の呼び出しを維持する。

| 値 | 意味 |
|---|---|
| `titleUserMessages == nil` | 旧 initializer による生成。task-49 はこの場合だけ既存 `preview` を代替材料にできる |
| `titleUserMessages == []` | 取得器が調べた結果、ユーザー候補がない。既存 `preview` への代替を許可しない |
| 非空の `titleUserMessages` | 加工前のユーザー本文を出現順に保持する |
| `titleSummary` | 補助候補。Codex DB の加工前 `preview`。Claude／Codex rollout では `nil` |

本タスクが変更する取得器は、生成する entry に必ず `titleUserMessages` を設定する。取得済みなのに `nil` を渡して旧 initializer 扱いにしない。

「加工前」は、既存 JSON パーサーで文字列を取り出した後、preview 用の空白結合・前後空白除去・120文字化を適用する前を指す。text block 配列は対象ブロックの順序を保ち、既存どおり改行で結合する。

### 取得器ごとの規則

| 経路 | ユーザー材料 | 補助材料 |
|---|---|---|
| Claude JSONL | 既存走査範囲内の `type == "user"` の本文を出現順に収集する。`isMeta == true` は材料から除外する。文字列と `type == "text"` の配列に対応する | `nil` |
| Codex rollout | 既存走査範囲内で `messageRole` が `"user"` と判定したレコードの本文を、`messageText` を使って収集する | `nil` |
| Codex DB | 加工前 `first_user_message` を1候補として保持する。NULL・空文字・空白のみなら `[]` とする | 加工前 `preview`。NULL なら `nil`。空文字・空白のみも加工せず保持する |

- Claude の `isMeta` が欠落または `false` の本文は、このフラグを理由に除外しない。
- assistant、system、tool result、tool 出力をユーザー材料にしない。Codex は `messageText` へ `"user"` を渡すだけで代用せず、レコードの role を確認する。
- `/review`、XML 風の本文、`Base directory for this skill:`、コードフェンス等の文字列判定は task-49／task-41 の責務とする。取得器ではタイトルを選定・短縮しない。
- Claude の `isMeta` 除外は新規材料だけに適用する。既存の `firstUserLine`、候補への採否、`preview`、日時、loader の挙動に流用しない。
- Codex の既存 preview 選定と新規材料収集を分離する。ユーザー材料を正しく選ぶために、既存 preview の値まで変更しない。
- タイトル材料が不適格または空でも、既存条件で採用される entry を削除しない。

### 読み取り範囲・不変条件

- Claude の `maxLinesPerFile == 200`、`maxBytesPerFile == 256 * 1024` と既存の読込境界を維持する。同じ走査で材料を収集し、追加の全件走査を行わない。
- Codex のメタデータ16 KiB、本文512 KiB、および既存の `scan` の行数打ち切り条件を維持する。行数制限を別の切り方へ変更しない。
- Codex DB が利用可能なら、タイトル材料の有無・適格性・検索結果0件を理由に rollout を追加走査しない。DB 利用失敗時だけ既存のフォールバックを使う。
- SQLite の `SQLITE_OPEN_READONLY`、DB 選択順、SQL の採否・cwd 条件・件数・並び順を維持する。
- Claude の sidechain 除外、対象プロジェクトのディレクトリ選択、既存の候補採否・mtime 順・件数を維持する。
- 既存 entry の6フィールドの意味と値、`id == sessionID` を維持する。
- `ClaudeSessionTranscriptLoader`、Codex の `loadTranscript` と復元処理を変更しない。共有パーサーの変更は材料取得に必要な追加に限定し、既存の解析結果を変えない。
- JSONL、SQLite、`sessions.json`、transcript store に新規フィールドを書き込まない。元履歴の削除・リネーム・整形保存を行わない。
- CLI 起動、ネットワーク通信、命名専用 AI 呼び出しを追加しない。

## 成功基準

### 1. Swift Testing：実取得器と元履歴の保護

PM は `AcceptanceHistoryTitleSourcesTests.swift` に、一時ディレクトリ内の合成 JSONL／SQLite を実取得器で読むテストを作成する。私有履歴を fixture に転記しない。task-41／task-49 の製品 API を呼んで期待値を作らない。

| 入力・条件 | 固定する期待結果 |
|---|---|
| 新規引数なしの既存 initializer | 新規2フィールドはともに `nil`。既存6フィールドは入力どおり |
| Claude の文字列本文 `"/review\nログイン画面を修正"` | `titleUserMessages == ["/review\nログイン画面を修正"]` |
| Claude の text block 配列 `"/review"`、`"設定画面を整理"` | 1本文として `"/review\n設定画面を整理"` を保持する |
| Claude の `isMeta: true` 本文、後続の実依頼 | メタ本文を材料から除外し、実依頼を保持する。既存 preview は従来の値を維持する |
| Claude の `isMeta` 欠落／`false` | 通常のユーザー本文を保持する |
| 複数のユーザー本文 | 改行・前後空白・出現順を維持する |
| 120文字を超える本文と、その後続行 | 新規材料は切られない。既存 preview は従来どおり120文字まで |
| assistant、system、tool result のみ | ユーザー材料に混入しない。既存条件で entry が成立する fixture では `[]` |
| Codex rollout の `response_item`／`event_msg` | 各形式のユーザー本文を加工せず保持する |
| Codex rollout の assistant が先、user が後 | 材料は user の本文だけ。既存 preview の規則は維持する |
| DB の `first_user_message` と `preview` が異なる | 前者はユーザー材料、後者は補助材料として別々に保持する |
| DB のユーザー本文が NULL・空・空白のみ、preview は非空 | ユーザー材料は `[]`。補助材料を保持し、rollout 走査は0回 |
| DB 利用可能で結果0件 | rollout 走査は0回 |
| DB 利用不可 | 既存の rollout フォールバックを維持する |

併せて以下を検査する。

- Claude の sidechain／メタデータだけのファイルの除外、Codex の cwd 絞り込み、両取得器の件数・順序・読込上限。
- 採用 entry の既存 ID、URL、preview、日時、ブランチが固定期待値と一致すること。
- Claude／Codex の loader が、従来復元していた `/review`、メタ本文、貼り付け内容を同じ本文として返すこと。既存 loader が除外していた内容まで追加する要求ではない。
- 取得と loader 呼び出しの前後で fixture のバイト列・更新日時・ファイル集合が変化しないこと。SQLite fixture はセットアップ接続を閉じてから比較する。
- 実 Claude／Codex／Cursor を起動せずに検査できること。

### 2. Ruby：配線・凍結 blob の保護

PM が `.claude/scripts/task51-wiring.rb` を作成する。

- 新規材料が実際の entry 生成へ渡り、加工前本文を使うことを検査する。
- Claude のメタ除外と Codex の role 判定が材料収集に接続されていることを検査する。
- loader、既存 preview 正規化、走査制限、DB 優先・読み取り専用・SQL 条件等を凍結 blob と比較する。
- 材料追加に必要な変更箇所を限定して認める。変更した関数全体を比較対象から外さない。
- コメント・文字列・未使用ヘルパー・`if false` 内の記述だけでは配線成立と扱わない。対象不在・解析不能は非ゼロ終了とする。

基準は以下に固定する。

1. `TASK51_BASELINE` はコミット SHA 必須。契約の `baseline_commit` と完全 SHA に解決して一致させる。
2. `HEAD`、`HEAD~1`、`@`、ブランチ名、未設定時のフォールバックを拒否する。
3. `git show <凍結SHA>:<path>` の blob を比較元にする。現在ソースから正本を生成しない。
4. 受け入れテストと Ruby 自身が基準コミットに存在し、現在の内容と一致することを確認する。
5. 基準の entry に新規材料フィールドがなく、取得器にも本タスクの材料配線がないことを確認する。実装済み HEAD の SHA による自己比較を拒否する。
6. 実装前の凍結コミットがその時点の HEAD と一致すること自体は拒否しない。

`--selftest` は実ファイルを変更せず、本番と同じ検査関数で正例と単一違反の負例を検査する。負例は、材料未接続、加工済み preview の転記、メタ本文混入、role 判定欠落、loader への除外流用、走査上限拡大、DB 利用時の追加走査、書込接続、コメント等による偽装、SHA 未設定・可変参照・契約不一致・blob 欠落・凍結検査改変・実装入り基準を含む。

変更範囲検査は `TASK51_SCOPE_CHECK=1` の着手時検査に分離する。task-49 以降の回帰実行では、task-49 の許可された View 変更を task-51 の違反としない。材料・復元・凍結検査の保護は常時行う。

### 3. 品質ゲートと開示

リポジトリルートから実行する。`<凍結SHA>` は PM が実値に置換する。

```sh
~/.agents/scripts/compact-test task51-sources bash macos/scripts/run-swift-tests.sh SessionFeature DashboardFeature
~/.agents/scripts/compact-test task51-wiring-selftest ruby .claude/scripts/task51-wiring.rb --selftest
~/.agents/scripts/compact-test task51-wiring env TASK51_BASELINE=<凍結SHA> TASK51_SCOPE_CHECK=1 ruby .claude/scripts/task51-wiring.rb
~/.agents/scripts/compact-test task51-integration bash .claude/verify.sh
```

確認した `.claude/verify.sh` は8パッケージ、更新隔離検査、`git diff --check` を実行する。DashboardFeature の直列実行・実 git テストの別実行は既存スクリプトに任せる。

App のコンパイル・リンクも、今回専用の出力先で確認する。

```sh
~/.agents/scripts/compact-test task51-app-build xcodebuild \
  -project macos/Phlox.xcodeproj \
  -scheme Phlox \
  -configuration Debug \
  -derivedDataPath "$TASK51_DERIVED_DATA" \
  -destination platform=macOS build
```

PM は凍結時に品質設定を再確認する。確認した範囲に独立した lint・静的解析コマンドはなく、未設定と未実行を区別する。

`docs/agent-output/task-51.md` に、材料追加・両取得器・元履歴保護の実装状況、実行結果、未検証事項、変更パスを記録する。表示変更を含まないため PM 目視は対象外。本タスクの成立を UX-11 全体の完了と扱わない。

## レビュー観点（Rubric）

- **材料の忠実性**：改行・長さ・順序を保ち、メタ本文と他 role の出力を混ぜていない。
- **互換性**：`nil` と `[]` を区別し、既存 preview・候補採否・ID・日時を維持している。
- **履歴保護**：元ファイルと復元本文を変えず、タイトル都合の除外を loader に流用していない。
- **取得コスト**：既存走査内で完結し、DB 優先・読込制限を維持している。
- **責務境界**：タイトル導出・UI・起動配線を変更せず、task-49 の許可パスと交差しない。
- **検証の独立性**：実取得器の Swift Testing と、凍結 blob 比較・単一違反 selftest が成立している。
