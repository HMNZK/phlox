---
id: task-49
difficulty: standard
depends_on:
  - task-41
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceHistoryEntryPresentationTests.swift
  - macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceHistoryTitleSourcesTests.swift
  - .claude/scripts/task49-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/SessionFeature/Sources/SessionFeature/HistoryEntryPresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ClaudeSessionHistoryEntry.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatHistoryStartView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/CodexSessionHistory.swift
  - docs/agent-output/task-49.md
---

## 目的

UX-11 / P2「履歴を作業名で探せるようにする」。履歴候補の主表示を作業名とし、プロジェクトと最終利用時刻から再開対象を識別できるようにする。表示用タイトルを元の本文から分離し、履歴ファイル、再開先、復元する会話内容を変更しない。

仕様の正本は `macos/docs/specs/ui-ux-improvement-backlog.md:133`。対象は Claude／Codex チャットの履歴一覧であり、全文検索、履歴削除、手動リネーム、命名専用の AI 呼び出しは追加しない。

保存予定先は `docs/agent-output/contract-draft-task-49.md`。本本文は未凍結の草案で、ファイルには保存していない。調査時 HEAD は `0ded7603d762863a7bcdf4a12ac9ba75b43a6ac2`。製品変更、テスト作成・実行、ビルド、GUI 検証は未実施。

## 入出力契約

### 実コードで確認した起点

以下のパスはリポジトリ相対。新設する型・メンバーは後段で「新規契約」として区別する。

| 対象 | 確認した実装と意味 |
|---|---|
| 履歴データ | `macos/Packages/SessionFeature/Sources/SessionFeature/ClaudeSessionHistoryEntry.swift`。`sessionID`、`preview`、`firstUserAt`、`lastModified`、`gitBranch`、`fileURL` を保持。Codex も同じ型を使う |
| 履歴一覧 | 同ディレクトリの `ChatHistoryStartView.swift`。`row(for:)` は `entry.preview` を主表示し、日付は `firstUserAt ?? lastModified`。現在の主表示にはプロジェクト名がない |
| 到達経路 | `ChatSessionView.swift` の overlay → `ChatHistoryStartView` → `ChatSessionViewModel.startFromHistory` |
| 再開処理 | `ChatSessionViewModel.swift:557`。選択した entry を loader に渡し、`client.resume(sessionRef: entry.sessionID)` を呼ぶ |
| 履歴取得 | 同 VM の `scheduleHistoryCacheLoadIfNeeded`。provider を main actor 外で一度だけ実行し、最大20件をキャッシュ |
| プロジェクトの補助表示 | 同 VM の `workspaceName`、`workspacePath`、`rawWorkspacePath`。履歴取得条件で使った作業ディレクトリを表示へ渡せる |
| Claude の取得元 | `macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift` の `ClaudeSessionHistoryDiscovery`。最初の対象ユーザー発言を空白結合し、120文字までの `preview` にする |
| Claude の要約 | 現行 `ParsedLine` に `summary` の保持欄はなく、履歴タイトルにも使用しない。既存受け入れテストは summary だけのファイルを候補から除外する |
| Codex の取得元 | 同 Spawn ディレクトリの `CodexSessionHistory.swift`。SQLite が利用可能なら `threads.preview`、空なら `first_user_message`。DB が利用できない場合は rollout JSONL の最初のユーザー本文 |
| Codex の時刻 | DB は `updated_at_ms`、rollout はファイル更新日時を `lastModified` に格納 |
| Codex の別の発見処理 | `Dashboard/DashboardViewModel.swift:125` の `codexDiscovery` は `CodexNativeSessionDiscoveryController`。PTY のネイティブ再開 ID の発見・確保・保存を担当し、履歴タイトルの取得器ではない |
| provider の注入 | `Environment/AppEnvironment.swift` の `claudeSessionHistoryProviders`／`codexSessionHistoryProviders` → `Dashboard/SessionSpawnService.swift` の `makeChatSessionViewModel` |

`threads.preview` を誰が生成し、常に要約として扱えるかは未確認。本契約では「既存の補助タイトル候補」として扱い、AI 要約であるとは断定しない。

### 定型文が主表示へ入る経路

- Claude は `<` から始まるユーザー本文を除外するが、`isMeta` を解析していない。ローカルの実 JSONL で、`isMeta: true` のユーザー本文が `Base directory for this skill:` から始まる例を確認した。この形式は現行の除外条件を通過する。
- `/xxx` から始まる本文も現行の Claude 履歴抽出では採用される。
- 改行を空白へ潰して120文字に切った後では、スキル呼び出し行と次行の実依頼を分離できない。長い貼り付けの後にある作業名も失われる。
- Codex も preview の空白結合・120文字化を行う。DB の `preview` が非空なら、別に存在する `first_user_message` は現在の主表示へ使われない。

ローカル JSONL では `message.content` の文字列形式、`type: "text"` の配列形式、`tool_result` の配列形式を確認した。私有の本文は fixture に転記せず、確認した構造だけを使う。

### 事前条件と担当

- task-41 の `SessionTitleDeriver.derive(from:)` と `DerivedSessionTitle` を再利用する。調査時の製品ソースには未実装で、API は `docs/agent-output/contract-draft-task-41.md` の新規契約として確認した。
- task-41 が分割された場合も、依存対象はタイトル導出の契約とする。名前の保存・手動リネームの完了は本件の前提にしない。
- PM が受け入れテストと Ruby 配線検査を作成し、実装不足による red を確認して凍結する。Cursor は製品実装のみ担当し、テスト、配線検査、契約、品質ゲートを編集しない。
- レビューは Cursor の実装モデルとは別モデルが担当する。
- 新規パッケージ・依存・App ターゲットのテストは追加しない。既存の SessionFeature／DashboardFeature の Swift Testing を使う。
- `baseline_commit` と `TASK49_BASELINE` は、task-41 の必要実装と task-49 の凍結テストを含み、task-49 の製品実装を含まないコミットへ固定する。

### 新規契約：元データとタイトル材料の分離

`ClaudeSessionHistoryEntry` に以下を追加する。名前は新規契約である。

```swift
public let titleUserMessages: [String]?
public let titleSummary: String?
```

既存 initializer の末尾へ、いずれも既定値 `nil` の引数を追加する。

- `titleUserMessages` はタイトル候補となるユーザー本文を、改行・文字数を変えず出現順に保持する。
- `nil` は旧 initializer による生成を表す。この場合だけ、既存 `preview` を候補として導出器へ渡す。
- `[]` は取得器が調べた結果、候補がないことを表す。`preview` へ戻して除外済み定型文を再採用しない。
- `titleSummary` は補助候補。Codex DB の加工前 `preview` を渡す。Claude と Codex rollout では `nil`。
- 既存 `preview` の生成規則・値を維持する。表示名で上書きしない。
- `sessionID`、`fileURL`、`firstUserAt`、`lastModified`、`gitBranch` の意味を変えない。
- 新規フィールドを JSONL、SQLite、`sessions.json`、transcript store に保存しない。

取得器の契約：

| 経路 | タイトル材料 |
|---|---|
| Claude JSONL | 既存走査範囲内のユーザー本文を出現順に収集。`isMeta == true` は除外。文字列と text block 配列の両方を扱い、tool result／assistant／system は採らない |
| Codex rollout | 既存走査範囲内のユーザー本文を出現順に収集。既存 `messageRole`／`messageText` を再利用し、assistant／tool 出力を採らない |
| Codex DB | 加工前 `first_user_message` をユーザー候補、加工前 `preview` を補助候補として別々に渡す |

候補の除外はタイトル材料だけに適用する。履歴一覧への採否、元の `preview`、transcript loader まで同時に変更しない。

Claude の200行・256 KiBの既存走査制限、Codex のメタデータ16 KiB・本文512 KiBの既存読込制限と行数制限を広げない。タイトルのためにファイル全体を再走査しない。

Codex DB が利用可能な場合は、タイトル候補が不適格でも rollout を追加走査しない。`CodexSessionHistoryTests.swift` にある「DB 利用時は走査回数0」の既存契約を維持する。

### 新規契約：表示モデル

`SessionFeature/HistoryEntryPresentation.swift` に以下を置く。

```swift
public struct HistoryEntryPresentation: Equatable, Sendable {
    public let title: String
    public let fullTitle: String
    public let projectName: String
    public let projectPath: String?
    public let lastUsedAt: Date?

    public init(
        entry: ClaudeSessionHistoryEntry,
        workingDirectory: String?
    )
}
```

判定順序：

1. `titleUserMessages` の各本文を出現順に調べる。旧 initializer の場合だけ `preview` を一つの本文として扱う。
2. 前後空白を除いた本文が `<` または `Base directory for this skill:` で始まる場合、その本文全体をタイトル候補から除外する。
3. 残った本文を加工前の改行を保って `SessionTitleDeriver.derive(from:)` に渡し、最初の導出成功を採る。
4. 成功がなければ `titleSummary` に同じ除外・導出規則を適用する。
5. どちらも導出できなければ `title == fullTitle == "作業名なし"`。

`/xxx` 行、コードフェンス、貼り付けコード、32文字境界の処理は task-41 に任せる。別の導出器を実装しない。

補助情報：

- 作業ディレクトリの最終パス要素を `projectName`、入力のパスを `projectPath` とする。末尾の `/` は名前抽出時に取り除く。
- `/` はプロジェクト名も `/`。空・空白のみ・未指定なら `"プロジェクト不明"`、`projectPath == nil`。
- `lastUsedAt` は `entry.lastModified`。`.distantPast` の場合だけ `nil`。
- `firstUserAt` を最終利用時刻の代わりにしない。現在時刻を補充しない。
- 同じタイトルでも行を統合しない。行の識別・選択には元 entry の `sessionID` を使う。

モデルは Foundation、標準ライブラリ、AgentDomain の導出器だけに依存する。ファイル、設定、時計、ネットワーク、プロセス、View を参照しない。

この契約は構造と固定規則による除外であり、任意の自然文がスキル説明か実依頼かを識別するものではない。この限界は `ponytail:` コメントに記し、拡張には具体例と凍結テストを必要とする。

### 表示と操作

- `ChatHistoryStartView` へ作業ディレクトリを渡す。呼び出し元は既存の `viewModel.rawWorkspacePath` を使う。
- 各行の主表示は `HistoryEntryPresentation.title`。`entry.preview` を主表示へ直接描画しない。
- 主表示は1行省略とし、`fullTitle` を help とアクセシビリティラベルから確認できるようにする。
- 補助行はプロジェクト名と「最終利用」の日付・時刻。日時不明は `"最終利用日時不明"`。日付の整形は View 側で行う。
- プロジェクト名の help でパスを確認できるようにする。既存ブランチ表示は補助情報として維持する。
- 作業名が同一、または `"作業名なし"` でも区別できるよう、help／アクセシビリティラベルには元の `sessionID` も含める。内部 ID を通常の主表示にはしない。
- 履歴見出しを `"続きから再開"` とし、選択すると過去の会話を引き継ぐことを示す。
- 履歴が提示される画面には `"新規作成"` と「下の入力欄から新しい依頼を始める」旨の案内を別に表示する。既存 composer を利用し、表示のための新規セッション生成や送信を行わない。
- 行選択は元 entry をそのまま `onSelect` へ渡す。表示タイトルや行番号から再開先を検索し直さない。
- 既存の `ChatHistoryStartLayout`、高さ制限、スクロール、composer の操作領域、Button のキーボード操作を維持する。

### 不変条件

- `ChatSessionViewModel.startFromHistory`、既存 transcript loader、再開失敗処理を変更しない。
- provider の一度だけの取得、最大20件、対象 cwd の絞り込み、既存順序を維持する。
- Claude の sidechain／メタデータだけのファイルの除外を維持する。
- Codex の SQLite 読み取り専用接続、DB 優先、空の検索結果と DB 利用失敗の区別を維持する。
- `codexDiscovery`、ネイティブ ID の発見・確保・保存、通常のセッション命名に変更を加えない。
- 表示・スクロール・help・新規作成案内では、履歴への書き込み、セッション再開、メッセージ送信を行わない。
- 元履歴を削除・リネーム・整形保存しない。元本文を表示タイトルで置換しない。

## 成功基準

### 1. Swift Testing：表示モデル

PM は次の期待値をリテラルで凍結する。期待値を製品モデルや導出器から生成しない。

| 入力 | 期待結果 |
|---|---|
| ユーザー候補 `["ログイン画面を修正"]` | `"ログイン画面を修正"` |
| `["/review\nログイン画面を修正"]` | `"ログイン画面を修正"` |
| `["/review", "設定画面を整理"]` | `"設定画面を整理"` |
| `["Base directory for this skill: /tmp/skill\n説明文", "履歴表示を修正"]` | `"履歴表示を修正"` |
| `["<command-name>/review</command-name>", "履歴表示を修正"]` | `"履歴表示を修正"` |
| コードフェンス内のコードに続く `ログイン画面を修正` | `"ログイン画面を修正"` |
| 適格なユーザー候補と異なる補助候補 | ユーザー候補が優先 |
| ユーザー候補なし、補助候補 `"履歴表示を修正"` | `"履歴表示を修正"` |
| ユーザー候補・補助候補とも定型文だけ | `"作業名なし"` |
| `titleUserMessages == []`、定型文の旧 preview | preview を再採用せず `"作業名なし"` |
| 新規引数を渡さない旧 initializer、preview `"履歴表示を修正"` | `"履歴表示を修正"` |
| `abcdefghijklmnopqrstuvwx123456789` | title は `abcdefghijklmnopqrstuvwx1234567…`、fullTitle は33文字の入力 |
| 結合文字・複合絵文字を含む32／33 Character | task-41 の境界規則を維持 |
| cwd `/tmp/project-a/` | projectName は `project-a`、projectPath は入力パス |
| cwd 未指定 | `"プロジェクト不明"`、projectPath は nil |
| firstUserAt より後の lastModified | lastUsedAt は lastModified |
| lastModified が `.distantPast` | lastUsedAt は nil |

同じ入力で同じ結果になることと、モデル生成前後で entry の既存フィールドが変わらないことも検査する。

### 2. Swift Testing：実取得器からの材料供給

一時ディレクトリのダミー JSONL／SQLite を実際の取得器で読む。実 claude／codex／cursor は起動しない。

- Claude の文字列形式と text block 配列形式から、加工前の本文を渡せる。
- `isMeta: true` のスキル展開文を除外し、後続の実依頼を採れる。
- `/xxx` の後に改行を挟んだ依頼が、120文字化より前にモデルへ渡る。
- assistant／tool result は作業名にならない。
- タイトル導出不可でも、既存条件で採用される履歴は一覧に残る。
- Codex rollout の `response_item` と `event_msg` のユーザー本文を扱える。
- Codex DB の `first_user_message` と `preview` を混同せず、ユーザー候補優先・補助候補への移行を検査できる。
- Codex DB 利用時は追加 rollout 走査が0回。DB 利用不可時の既存フォールバックも維持する。
- cwd 絞り込み、件数、順序、元の ID・URL・preview・日時が維持される。
- JSONL／SQLite の内容と更新日時が、取得・モデル生成の前後で変化しない。
- transcript loader の出力に元の `/xxx`・定型文・貼り付け内容が従来どおり残る。タイトル向け除外を復元へ流用しない。

再開先の保護には、既存 `ChatHistoryStartAcceptanceTests.swift` の制御可能なクライアントによる検査も実行する。実 CLI の再開を受け入れ条件にしない。

### 3. Ruby：配線と凍結 blob の比較

PM が `.claude/scripts/task49-wiring.rb` を作成する。

検査対象：

- 取得器が加工前の材料を新規フィールドへ渡している。
- `HistoryEntryPresentation` が task-41 の導出器を呼ぶ。
- `ChatSessionView` → `ChatHistoryStartView` → 行の主表示までモデルと作業ディレクトリが届く。
- 元 entry の `onSelect` → `startFromHistory` が維持される。
- 主表示、全文 help、アクセシビリティラベル、プロジェクト、最終利用、新規作成／続きから再開の区別が、到達可能な描画経路にある。
- `startFromHistory`、transcript loader、Codex のネイティブ ID 発見処理などの不変部分を凍結 blob と比較する。
- 変更可能な取得器では、材料収集・転記のために許可した変更だけを比較から除く。関数全体を無条件に比較除外しない。

基準の扱い：

- `TASK49_BASELINE` 必須。契約の `baseline_commit` と完全 SHA に解決して一致させる。
- `HEAD`、`HEAD~1`、`@`、ブランチ名、未設定時のフォールバックを拒否する。
- 基準は `git show <凍結SHA>:<path>` の blob。現在ソースから比較用の正本を作らない。
- 基準コミットに受け入れテストと rb 自身が存在し、現在の内容と一致することを確認する。
- 基準に task-49 の表示モデル・製品配線が含まれていれば失敗する。実装後 HEAD の SHA を指定する自己比較を拒否する。
- 実装前の凍結コミットがその時点の HEAD と一致すること自体は拒否しない。

`--selftest` は実ファイルを変更せず、正例と以下の負例を検査する。

- コメント・文字列・未使用ヘルパー・`if false` だけにモデル呼び出しを置く。
- 主表示を `entry.preview` に戻す。
- `firstUserAt` を最終利用に使う。
- 作業ディレクトリを固定値にする。
- タイトルから再開先を引き直す、または別 entry を選択する。
- help／アクセシビリティラベルを欠落させる。
- 材料取得の前に120文字化・改行除去する。
- loader をタイトル除外処理へ接続する。
- baseline 未指定、可変参照、blob 取得失敗、凍結テスト改変、実装済み基準を与える。

対象不在・解析不能は非ゼロ終了とする。Ruby は Swift の判定テストや実描画確認の代用にしない。

### 4. 品質ゲート

リポジトリルートから実行する。`TASK49_BASELINE` は PM が凍結した SHA を設定する。

```sh
~/.agents/scripts/compact-test task49-wiring-selftest ruby .claude/scripts/task49-wiring.rb --selftest
~/.agents/scripts/compact-test task49-wiring ruby .claude/scripts/task49-wiring.rb
~/.agents/scripts/compact-test task49-integration bash .claude/verify.sh
```

確認した `.claude/verify.sh` は8パッケージの検査、更新隔離検査、`git diff --check` を実行する。DashboardFeature の直列実行と実 git テストの別実行は、既存 `run-swift-tests.sh` に任せる。

App のコンパイル・リンクは別に検査する。`TASK49_DERIVED_DATA` は今回専用の出力先とする。

```sh
~/.agents/scripts/compact-test task49-app-build xcodebuild \
  -project macos/Phlox.xcodeproj \
  -scheme Phlox \
  -configuration Debug \
  -derivedDataPath "$TASK49_DERIVED_DATA" \
  -destination platform=macOS build
```

確認した品質ゲートに独立した lint・静的解析コマンドはない。凍結時に設定を再確認し、未設定・対象外・実行不能を区別して記録する。既存アプリを終了する `debug-build-restart.sh` は目視準備に使わない。

### 5. PM 目視ゲート：課金なし・隔離データ

チャット画面を `sessions.json` の復元失敗プレースホルダで表示できることは PM 確認済みとして扱う。実 claude／codex／cursor の起動・送信・再開は要求しない。

**凍結前に解決する配線差分：**

- 現行 `makeRestoreErrorChatSession` は履歴 provider／loader を渡さない。
- `markRestoreFailed` は transcript にエラーを追加する。一方、`shouldOfferHistoryStart` は transcript が空であることを要求する。
- `PHLOX_DATA_DIR` はアプリ保存先を隔離するが、Claude の履歴ルートは `homeDirectoryForCurrentUser/.claude/projects`。同変数だけでは履歴ルートまで隔離されない。

したがって、**チャット画面の表示成功を履歴一覧の目視成功とは扱わない**。PM は凍結前に、既存の課金なし起動手順へ「隔離した取得器の出力を同じ履歴 View に渡す」到達経路を確立し、実ファイル・操作手順を記録する。新しい起動用配線が必要なら末尾の別契約で扱い、本件へ暗黙に混ぜない。履歴画面への到達方法は本調査では未検証。

到達経路確立後の手順：

1. 専用の `PHLOX_DATA_DIR`、`PHLOX_DEFAULTS_SUITE`、`PHLOX_AGENTS_JSON` と履歴 fixture ルートを用意する。通常の履歴ディレクトリを変更しない。`HOME` の上書きに依存しない。
2. 専用 `sessions.json` に課金なし表示用 descriptor を置く。復元失敗プレースホルダの既存手順を使い、実クライアントの起動に到達しないことを確認する。
3. Claude fixture は確認した JSONL 構造で作る。例の session ID に対応するファイル名と、`projectDirectoryName(forWorkingDirectory:)` が返すディレクトリ名を使う。

```jsonl
{"type":"user","isMeta":true,"message":{"role":"user","content":"Base directory for this skill: /tmp/task49-skill\n定型の説明文"},"uuid":"u-meta","sessionId":"11111111-1111-4111-8111-111111111111","cwd":"/tmp/task49-project-a","timestamp":"2026-09-10T09:00:00.000Z","isSidechain":false}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"/review\nログイン画面を修正"}]},"uuid":"u-task","sessionId":"11111111-1111-4111-8111-111111111111","cwd":"/tmp/task49-project-a","timestamp":"2026-09-10T09:01:00.000Z","gitBranch":"dev","isSidechain":false}
```

4. 別作業名、同名、長い名前、定型文だけの履歴を追加する。初回発言日時と異なる更新日時を設定する。Codex は DB 経路と rollout 経路を別 fixture で表示する。
5. 今回ビルドした隔離 Debug を起動し、自 PID・実行ファイル・ウィンドウ所有 PID を照合して撮影する。
6. 作業名、プロジェクト、最終利用、長いタイトルの全文、同名履歴の識別情報、新規作成／続きから再開の区別を確認する。狭い表示領域でも末尾へスクロールでき、composer と重ならないことを確認する。
7. GUI では送信・実再開を行わない。選択先 ID と復元本文は Swift Testing、UI の接続は rb で検査する。
8. fixture の内容・更新日時が表示前後で変わらないことを確認する。画像、SHA、PID、寸法、fixture 条件、確認範囲を `docs/agent-output/visual-task-49.md` に PM が記録する。
9. 起動元・親子関係を確認し、この作業で起動した不要なプロセスだけを終了する。

この草案では目視を実施していない。調査時には、存在しないビルドスクリプト候補等の検索エラーと、read-only 制約によるヒアドキュメント実行失敗があった。後者は一時ファイルを使わない読み取りで再実施した。これらを検証成功として扱わない。

## レビュー観点（Rubric）

- **識別できるか**：定型文が主表示を占めず、作業名・プロジェクト・最終利用から対象を判断できる。
- **材料が失われていないか**：改行除去・120文字化の前に導出器へ渡し、実ユーザー本文とメタ本文を混同しない。
- **依存が適切か**：task-41 の導出器を再利用し、独自の短縮・コード判定を複製していない。
- **履歴を保護しているか**：表示名と再開 ID・元本文が分離され、表示都合で保存データを書き換えない。
- **既存範囲を守るか**：DB 優先、走査上限、20件、cwd、順序、キャッシュ、復元処理が維持される。
- **表示に到達できるか**：未使用モデルだけで合格せず、実際の行、help、アクセシビリティへつながる。
- **証拠が一致するか**：Swift Testing、凍結 blob 比較、App ビルド、PM 目視を区別する。課金なしのチャット表示を履歴一覧の確認へ読み替えない。

### 凍結前の分割案

本草案には、独立に失敗しうる「履歴材料の取得」と「表示モデル・UI」が含まれる。課金なしの履歴画面への到達経路にも未確定部分があるため、凍結時は次の分割を推奨する。

| 契約 | 責務 | 依存 |
|---|---|---|
| 先行タスク・番号未設定 | entry の材料追加、Claude／Codex の取得、元履歴非改変、取得器の Swift Testing | なし |
| task-49 | 表示モデル、task-41 の再利用、履歴 UI、rb 配線、PM 目視 | task-41、上記先行タスク |
| 検証支援タスク・番号未設定、必要な場合のみ | 隔離履歴と復元失敗プレースホルダから同じ履歴 View を課金なしで表示する配線 | PM が到達方法を確定 |

分割採用時は PM が `depends_on`、`acceptance_tests`、`allowed_paths` を各契約へ分けて再凍結する。未確定の目視到達経路を残したまま実装役へ渡さない。