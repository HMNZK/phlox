---
id: task-49
difficulty: standard
depends_on:
  - task-41
  - task-51
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceHistoryEntryPresentationTests.swift
  - .claude/scripts/task49-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/SessionFeature/Sources/SessionFeature/HistoryEntryPresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatHistoryStartView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift
  - docs/agent-output/task-49.md
---

## 目的

UX-11「履歴を作業名で探せるようにする」の表示モデルと履歴 UI を実装する。履歴候補の主表示を作業名とし、プロジェクトと最終利用日時から再開対象を判断できるようにする。表示用タイトルと元の会話内容を分離し、選択する entry と復元処理を維持する。

task-51 が取得した材料と task-41 のタイトル導出器を再利用する。全文検索、履歴削除、手動リネーム、命名専用 AI 呼び出し、検証支援の第三契約は追加しない。

本草案は read-only 調査に基づく。調査時 HEAD は `0511c76e8f6ea86fab48f55cc293419f8189ba99`。ファイル変更・保存、テスト作成・実行、ビルド、GUI 確認は行っていない。課金なし目視の到達性は、後掲の実コード調査結果に従って判定する。

## 入出力契約

### 担当・前提・境界

- Cursor は `allowed_paths` 内の製品実装と開示レポートを担当する。テスト、Ruby 検査、契約、品質ゲートを作成・変更しない。
- PM が固定期待値から Swift Testing と Ruby 検査を作成し、未実装による red を確認して凍結する。レビューは Cursor の実装モデルとは別モデルが担当する。
- task-41 の `SessionTitleDeriver.derive(from:)` と `DerivedSessionTitle`、task-51 の材料フィールドが利用可能であること。
- 調査時の AgentDomain 製品ソースでは `SessionTitleDeriver` の実装を確認できていない。API は `tasks/task-41.md` の契約として確認した。依存完了を文書だけで判定せず、凍結時に製品実装と検証結果を確認する。
- 既存の `SessionFeatureTests` を使う。App ターゲットにテストを置かず、新規パッケージ・依存を追加しない。
- `baseline_commit` と `TASK49_BASELINE` は、task-41／task-51 の必要実装と本タスクの凍結検査を含み、本タスクの製品実装を含まないコミットに固定する。
- task-51 の `allowed_paths` との交差はない。entry、取得器、VM、loader、AppEnvironment、セッション生成・復元処理を変更しない。
- PM の目視記録は `docs/agent-output/visual-task-49.md` とする。PM 専有であり Cursor の許可パスには含めない。

### 新規公開契約：表示モデル

次の型・メンバーは本契約で新設する API である。配置先は `HistoryEntryPresentation.swift` とする。

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

タイトルの決定順序を以下に固定する。

1. `entry.titleUserMessages` を出現順に調べる。値が `nil` の場合だけ `[entry.preview]` を代替材料にする。`[]` から preview へ戻らない。
2. 前後空白を除いた本文が `<` または `Base directory for this skill:` で始まる場合、その本文全体を除外する。判定は大文字・小文字を区別する。
3. 残った本文は改行や先頭空白を加工せず、`SessionTitleDeriver.derive(from:)` に渡す。最初の導出成功の `title`／`fullTitle` をそのまま採る。
4. 成功がなければ `titleSummary` に同じ除外・導出規則を適用する。
5. いずれも導出できなければ `title == fullTitle == "作業名なし"` とする。

`/xxx` 行、コードフェンス、貼り付けコード、幅変換、32文字境界は task-41 に任せる。独自の導出器・短縮処理を追加しない。`fullTitle` は導出された候補行の全文であり、会話全文ではない。

補助情報の規則：

- 作業ディレクトリの末尾 `/` を名前抽出時だけ取り除き、最終パス要素を `projectName` とする。`projectPath` は入力パスを保持する。
- `/` のプロジェクト名は `/`。
- 未指定・空文字・空白のみなら `projectName == "プロジェクト不明"`、`projectPath == nil`。
- `lastUsedAt` は `entry.lastModified`。`.distantPast` の場合だけ `nil`。
- `firstUserAt` や現在時刻で最終利用日時を補わない。
- 同名の entry を統合しない。表示モデルに再開先の検索・置換を持たせない。

モデルは Foundation、標準ライブラリ、AgentDomain の導出器だけに依存する。ファイル、設定、時計、ネットワーク、プロセス、View に依存しない。

定型文除外は限定した接頭辞による判定である。この限界と、拡張には具体例・固定テストを必要とすることを `ponytail:` コメントに記す。

### 表示・操作

実コードで確認した `ChatSessionView` の overlay → `ChatHistoryStartView` → `row(for:)` に接続する。

- `ChatHistoryStartView` に作業ディレクトリを渡す。呼び出し元は `viewModel.rawWorkspacePath` を使い、固定パスや表示用に短縮されたパスへ置き換えない。
- 各行の主表示は `HistoryEntryPresentation.title` とする。`entry.preview` を直接主表示へ描画しない。
- 主表示は1行省略を維持する。`fullTitle` を help とアクセシビリティラベルから確認できるようにする。
- 補助行にプロジェクト名と「最終利用」の日付・時刻を示す。不明の場合は `"最終利用日時不明"` とする。日付整形は View 側で行う。
- プロジェクト名の help で `projectPath` を確認できるようにする。パス不明時に架空のパスを補わない。
- 既存のブランチ表示を維持する。
- 同名・作業名なしの履歴を識別できるよう、行の help とアクセシビリティラベルに元の `sessionID` を含める。ID を通常の主表示にしない。
- 履歴見出しを `"続きから再開"` とし、過去の会話を引き継ぐ操作であることを示す。
- 同じ画面に `"新規作成"` と `"下の入力欄から新しい依頼を始めます"` を別の案内として表示する。既存 composer を使い、案内表示だけでセッション生成・送信を行わない。
- `ForEach(entries)` の識別と、元 entry をそのまま `onSelect(entry)` に渡す操作を維持する。表示タイトルや行番号から再開先を引き直さない。
- `ChatSessionView` の `Task { await viewModel.startFromHistory(entry) }` への接続を維持する。
- 既存 `ChatHistoryStartLayout`、高さ制限、スクロール、composer の操作領域、Button のキーボード操作、既存 AX identifier を維持する。

### 不変条件

- `ChatSessionViewModel.shouldOfferHistoryStart`、`scheduleHistoryCacheLoadIfNeeded`、`startFromHistory`、復元失敗処理を変更しない。
- provider の非同期取得・一度だけのキャッシュ・最大20件を維持する。
- task-51 の材料と元の entry を変更・保存しない。
- Claude／Codex の取得器、transcript loader、ネイティブ再開 ID の発見・保存を変更しない。
- 表示、スクロール、help、新規作成案内から送信・再開・元履歴への書き込みを発生させない。
- PM 目視のために表示条件を弱めたり、復元エラーを消したり、製品内へ fixture や検証専用起動経路を追加したりしない。

## 成功基準

### 1. Swift Testing：表示モデル

PM が `AcceptanceHistoryEntryPresentationTests.swift` に以下の期待値を固定する。製品モデルや導出器を呼んで期待値を生成しない。

| 入力 | 期待結果 |
|---|---|
| ユーザー材料 `["ログイン画面を修正"]` | title／fullTitle ともに `"ログイン画面を修正"` |
| `["/review\nログイン画面を修正"]` | `"ログイン画面を修正"` |
| `["/review", "設定画面を整理"]` | `"設定画面を整理"` |
| `["Base directory for this skill: /tmp/skill\n説明文", "履歴表示を修正"]` | `"履歴表示を修正"` |
| `["<command-name>/review</command-name>", "履歴表示を修正"]` | `"履歴表示を修正"` |
| 閉じたコードフェンスに続く依頼行 | フェンス後の依頼行 |
| 適格なユーザー材料と異なる補助材料 | 最初の適格なユーザー材料を優先 |
| ユーザー材料が不適格、補助材料 `"履歴表示を修正"` | `"履歴表示を修正"` |
| ユーザー材料・補助材料が定型文だけ | `"作業名なし"` |
| `titleUserMessages == []`、preview は `"採用してはいけない旧表示"`、補助材料なし | `"作業名なし"` |
| `titleUserMessages == nil`、preview は `"履歴表示を修正"` | `"履歴表示を修正"` |
| `abcdefghijklmnopqrstuvwx12345678` | title／fullTitle ともに入力32文字 |
| `abcdefghijklmnopqrstuvwx123456789` | title は `abcdefghijklmnopqrstuvwx1234567…`、fullTitle は入力33文字 |
| cwd `/tmp/project-a/` | projectName は `project-a`、projectPath は入力どおり |
| cwd `/` | projectName／projectPath ともに `/` |
| cwd が nil・空・空白のみ | `"プロジェクト不明"`、projectPath は nil |
| firstUserAt と異なる lastModified | lastUsedAt は lastModified |
| lastModified が `.distantPast` | lastUsedAt は nil |

さらに、複合絵文字・結合文字の32／33 Character 境界、同一入力の決定性、モデル生成前後で entry の既存・新規フィールドが変化しないことを検査する。

取得器からの材料供給は task-51 の受け入れテストを回帰実行する。再開先と復元本文は既存 `ChatHistoryStartAcceptanceTests.swift` の制御可能なクライアントを使う検査を実行する。これらを実 CLI 再開や GUI の確認と読み替えない。

### 2. Ruby：実描画への配線と凍結比較

PM が `.claude/scripts/task49-wiring.rb` を作成する。

検査対象：

- 表示モデルが task-41 の導出器を呼び、その結果を返すこと。
- `ChatSessionView` から `rawWorkspacePath` と `historyEntries` が履歴 View へ届くこと。
- 実際の行でモデルを構築し、主表示・全文 help・アクセシビリティ・プロジェクト・最終利用へ接続すること。
- 新規作成案内と続きから再開が、到達可能な描画経路に存在すること。
- 元 entry の `onSelect` → `startFromHistory` が維持されること。
- 履歴表示条件、キャッシュ、再開・復元、`ChatHistoryStartLayout` の保護対象を凍結 blob と比較すること。
- task-51 の entry と両取得器が、task-49 の凍結時点から変更されていないこと。

VM 等の共有ファイルは本契約の関連宣言を比較し、無関係な他契約の変更まで一律に禁止しない。View は変更を認める部分を限定し、関数全体を無条件に比較除外しない。

基準の扱い：

1. `TASK49_BASELINE` はコミット SHA 必須。契約の `baseline_commit` と完全 SHA に解決して一致させる。
2. `HEAD`、`HEAD~1`、`@`、ブランチ名、未設定時のフォールバックを拒否する。
3. `git show <凍結SHA>:<path>` の blob を比較元とする。
4. 受け入れテストと Ruby 自身が基準コミットに存在し、現在内容と一致することを確認する。
5. 基準に task-41／task-51 の必要実装が存在し、`HistoryEntryPresentation.swift` と本タスクの表示配線が存在しないことを確認する。
6. 実装済み HEAD の SHA による自己比較を拒否する。実装前の凍結コミットがその時点の HEAD と一致すること自体は拒否しない。

`--selftest` は実ファイルを変更せず、本番と同じ検査関数へ正例と単一違反の負例を渡す。負例は以下を含む。

- コメント・文字列・未使用ヘルパー・`if false` だけのモデル呼び出し。
- 主表示を `entry.preview` に戻す。
- 作業ディレクトリを固定値にする。
- 最終利用に `firstUserAt` を使う。
- help、アクセシビリティ、新規作成／続きから再開の案内を欠落させる。
- 別 entry を選択する、タイトルから再開先を引き直す。
- 履歴表示条件を弱める、キャッシュや復元処理を変更する。
- task-51 の entry／取得器を変更する。
- SHA 未設定・可変参照・契約不一致・blob 欠落・凍結検査改変・実装入り基準。

対象不在・解析不能は非ゼロ終了とする。Ruby は Swift の判定テストや実画面の目視を代替しない。変更範囲の全体検査は `TASK49_SCOPE_CHECK=1` の着手時検査に分離する。

### 3. 品質ゲート

リポジトリルートから実行する。各 `<凍結SHA>` は対応する契約の実値に置換する。task-41／task-51 の回帰検査には着手時の scope check を付けない。

```sh
~/.agents/scripts/compact-test task49-models bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
~/.agents/scripts/compact-test task49-wiring-selftest ruby .claude/scripts/task49-wiring.rb --selftest
~/.agents/scripts/compact-test task49-wiring env TASK49_BASELINE=<task-49の凍結SHA> TASK49_SCOPE_CHECK=1 ruby .claude/scripts/task49-wiring.rb
~/.agents/scripts/compact-test task49-task41-wiring env TASK41_BASELINE=<task-41の凍結SHA> ruby .claude/scripts/task41-wiring.rb
~/.agents/scripts/compact-test task49-task51-wiring env TASK51_BASELINE=<task-51の凍結SHA> ruby .claude/scripts/task51-wiring.rb
~/.agents/scripts/compact-test task49-integration bash .claude/verify.sh
```

App のコンパイル・リンクを別に確認する。

```sh
~/.agents/scripts/compact-test task49-app-build xcodebuild \
  -project macos/Phlox.xcodeproj \
  -scheme Phlox \
  -configuration Debug \
  -derivedDataPath "$TASK49_DERIVED_DATA" \
  -destination platform=macOS build
```

確認した `.claude/verify.sh` は8パッケージ、更新隔離検査、`git diff --check` を実行する。独立した lint・静的解析設定は確認範囲では見つかっていない。PM は凍結時に再確認し、未設定・対象外・実行不能を区別する。

### 4. PM 目視ゲート：課金なし到達性の確定

#### 実コードで確認した表示条件

`macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift` の `shouldOfferHistoryStart` は、次の条件をすべて要求する。

1. `agentRef` が組み込み Claude Code または組み込み Codex。
2. `historyProvider != nil`。
3. `transcript.isEmpty`。
4. `submitBaselineTurnSeq == nil`。
5. `cachedHistoryEntries` が非空。

`ChatSessionView.swift` はこの値が true の場合だけ overlay に `ChatHistoryStartView` を配置する。View 自体に空状態の本文はあるが、キャッシュ0件では通常の親画面からその View に到達しない。

通常の provider 注入には、`AppEnvironment.swift` の `claudeSessionHistoryProviders`／`codexSessionHistoryProviders` に空でない working directory が渡ることも必要である。ロードは非同期なので、fixture が存在するだけでは即時表示を保証しない。

#### 課金なし経路の調査結果

| 候補 | 確認結果・契約上の扱い |
|---|---|
| 既存報告の `sessions.json` 復元失敗プレースホルダ | `visual-task-27-35-composer.md` は custom kind `ui-chat-probe`、存在しない binary、`backend: appServer`、pid なしからチャット表示を観測した記録。ただし custom agent は条件1を満たさない |
| `makeRestoreErrorChatSession` | `SessionSpawnService.swift` で provider／loader を渡さず、`markRestoreFailed` を呼ぶ。条件2・3も満たさない。組み込み agent の descriptor に変えても、この失敗経路では履歴を表示できない |
| 復元 descriptor の thread ID を省略する | `SessionRestoreCoordinator.swift` は VM 生成後に `markRestoreFailed("chat restore failed: missing thread id")` を呼ぶ。transcript が空にならず、履歴表示の代替経路にならない |
| Claude JSONL を `PHLOX_DATA_DIR` 配下へ配置する | ファイル配置自体は可能。しかし `AppEnvironment.claudeProjectsRoot` は `homeDirectoryForCurrentUser/.claude/projects` を使い、同変数を参照しない。通常アプリはその fixture を取得しない |
| Codex DB／rollout を `PHLOX_DATA_DIR` 配下へ配置する | `codexHome` の既定値は `homeDirectoryForCurrentUser/.codex`。`CompositionRoot.swift` は別の `codexHome` を注入していない。同変数だけでは切り替わらない |
| 取得器へ隔離ルートを直接渡す | `ClaudeSessionHistoryDiscovery(projectsRoot:)`／`CodexSessionHistoryDiscovery(codexHome:)` で可能。task-51 の Swift Testing に採用する。通常アプリへの fixture 注入経路ではない |
| `HOME` の差し替え | Foundation のホーム解決が変わるかは今回未実測。仮に変わっても provider 欠落・非空 transcript・custom agent の条件違反は解消しない。成立する目視手順として採用しない |
| 通常の新規チャット作成 | `startAppServerSession` → `startNew` → `client.start()` に進む。Codex は既定 factory でも `ProcessTransport.start()` を呼ぶ。実 CLI を起動しない目視経路として採用しない |

`PHLOX_DATA_DIR` が切り替えるのは `AppSupportLocator` のアプリ保存先であり、Claude／Codex の履歴ルートまで隔離する設定ではない。

**裁定：調査した既存経路では、隔離履歴を使って実 CLI を起動せず通常アプリの履歴一覧へ到達する手順は成立していない。task-49 の PM 目視は「未達として記録」する。** チャット入力欄の過去の観測を履歴一覧の目視成功へ読み替えない。第三契約や検証専用の製品配線は追加しない。

#### PM が固定して実施する手順

1. 凍結時に上記の表示条件・provider 注入・履歴ルート・復元失敗処理を実コードで再確認する。
2. 条件が変わっていなければ、到達しないことが分かっているプレースホルダを履歴目視目的で繰り返し起動しない。`docs/agent-output/visual-task-49.md` に「履歴一覧の目視：未達」、阻害条件、確認した SHA、GUI 未実施の範囲を記録する。
3. Swift Testing、Ruby 検査、App ビルドの結果は個別に記録する。自動検査が通っても、PM 目視 pass・task-49 の最終完了・UX-11 完了とは扱わない。
4. 凍結前の再確認で、既存の課金なし経路が別途成立した場合だけ、使用ファイル、起動環境、fixture 注入方法、画面操作を契約に追記して固定する。実 CLI 起動・送信・再開を要求しない。未確認の手順を Cursor へ委ねない。
5. 成立した経路で実画面を確認する場合は、別作業名・同名・長いタイトル・定型文のみ・日時不明を含む合成履歴を用いる。作業名、プロジェクト、最終利用、全文 help、AX、末尾へのスクロール、composer との非重複、新規作成／続きから再開の区別を確認する。
6. GUI 上の履歴選択は実再開につながるため行わない。選択先の保護は Swift Testing と Ruby 検査で確認する。
7. 目視を実施した場合は、使用 SHA、実行ファイル、自 PID とウィンドウ所有 PID、寸法、画像、fixture のバイト列・更新日時の前後比較、実 CLI 子プロセスの有無を記録する。通常の履歴・Release アプリへ触れず、自分が起動した不要なプロセスだけを終了する。

この未達条項は目視ゲートの免除ではない。到達できなかった事実と、自動検査で確認できた範囲を分けて残すための条項である。

### 5. 開示

`docs/agent-output/task-49.md` に、表示モデル、task-41 再利用、履歴 UI、選択経路の各実装状況と、実行結果・未検証事項を記録する。PM の目視結果は `visual-task-49.md` を参照し、未達を省略しない。

## レビュー観点（Rubric）

- **識別性**：作業名・プロジェクト・最終利用から候補を判断でき、同名でも元 ID を確認できる。
- **導出の再利用**：task-41 を使い、材料の `nil`／`[]` とユーザー優先・補助候補の順序を守る。
- **操作の保護**：元 entry が選択され、履歴・再開先・復元本文を変更していない。
- **描画への接続**：未使用モデルだけで合格せず、実際の行・help・AX・案内へ接続している。
- **責務境界**：task-51 の許可パスと交差せず、目視のために表示条件・復元処理を弱めていない。
- **証拠の正確さ**：Swift Testing、Ruby、App ビルド、PM 目視を区別し、課金なし到達経路が成立しなければ未達を明記している。
