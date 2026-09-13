---
output: docs/agent-output/contract-draft-task-41-split.md
status: 未凍結
read_only: true
---

=== FILE: tasks/task-41.md ===
---
id: task-41
difficulty: standard
depends_on: []
user_visible: false
acceptance_tests:
  - macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift
  - .claude/scripts/task41-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleDeriver.swift
  - docs/agent-output/task-41.md
---

## 目的

UX-01 のうち、一つのユーザーメッセージから短い作業名を導出する純粋関数を実装する。名前状態・チャット接続・保存は task-44、表示は task-45 が担当する。UX-01 の完了は3契約の成立後とする。

仕様の正本は `macos/docs/specs/ui-ux-improvement-backlog.md:78`。本契約は単一草案 `docs/agent-output/contract-draft-task-41.md` の分割版である。

調査対象 HEAD は `cb17de2193f80010a5126e19b2265b018452a2d7`。草案と実コードを読み合わせた。今回の起草ではファイル変更、テスト作成・実行、ビルド、GUI確認を行っていない。

## 入出力契約

### 担当・境界

- Cursor は `allowed_paths` 内の製品実装と開示レポートだけを担当する。受け入れテスト・Ruby検査・契約・検証ゲートを作成、変更しない。
- PM が本契約の期待値から Swift Testing とRuby検査を作成し、未実装による red を確認して凍結する。レビューはCursorの実装モデルとは別モデルが担当する。
- `AgentDomain/Package.swift` に既存の `AgentDomainTests` がある。新規パッケージ・依存・テストターゲットを追加せず、Appターゲットにテストを置かない。
- task-44、task-45 の `allowed_paths` との交差はない。本タスクで既存ファイルや呼び出し元を変更しない。
- `baseline_commit` は調査時HEADから自動設定しない。

### 新規公開契約

次の型・メンバーは既存シンボルではなく、本契約で新設するAPIである。

```swift
public struct DerivedSessionTitle: Equatable, Sendable {
    public let title: String
    public let fullTitle: String
}

public enum SessionTitleDeriver {
    public static func derive(from text: String) -> DerivedSessionTitle?
}
```

入力は一つのユーザーメッセージ本文。出力は表示用に短縮した `title` と、短縮前の候補行 `fullTitle`。適格な候補がなければ `nil` とする。`fullTitle` は依頼全文やtranscript全文ではない。

導出規則は次の順序に固定する。

1. CRLF・CRをLFとして扱い、元の行順で走査する。
2. コードフェンスの開始・終了行と内部を除外する。開始は行頭の半角空白0〜3個に続く、バッククォートまたはチルダの同一文字3個以上の連続。後続の言語指定は許す。終了は同じ文字が開始時以上の個数続き、その後が空白だけの行。別種・短いフェンスでは閉じず、未閉鎖なら末尾まで除外する。
3. フェンス外で、元の行がタブまたは半角空白4個以上で始まる場合は、貼り付けコードとして除外する。
4. 行の前後の空白を除き、Foundationの幅変換で全角・半角の違いを揃える。ロケールは固定し、大文字・小文字は変更しない。
5. 行内の連続する半角空白・タブ・全角空白を半角空白1個にする。
6. 空行と以下の行を除外し、次の行へ進む。接頭辞判定は大文字・小文字を区別する。
   - `/` で始まる行。引数付きも行全体を除外する。
   - `import `、`from `、`func `、`def `、`class `、`struct `、`enum `、`let `、`var `、`const `、`function `、`return `、`#include `、`#!/`、`$ ` で始まる行。
   - `{`、`}`、`[`、`]` で始まる行。
7. 最初に残った行を `fullTitle` とする。残らなければ `nil`。
8. Swiftの `Character` 単位で32文字以内なら `title == fullTitle`。33文字以上なら先頭31文字と `…` を結合する。絵文字・結合文字を途中で切らない。

Foundationと標準ライブラリだけを使う。ファイル、時計、設定、乱数、ネットワーク、プロセス、Viewに依存せず、元の送信本文・添付・transcriptを変更しない。

コード候補の除外は限定的な規則であり、任意のプログラミング言語を識別しない。この限界と「実例・テストが必要になった時点で拡張する」方針を `ponytail:` コメントに記す。

## 成功基準

### 1. Swift Testing

PMは次の期待値を固定する。製品の戻り値から期待値を生成しない。表の `\n`・`\r`・`\t` は実際の制御文字を入力する。

| 入力 | 期待する結果 |
|---|---|
| `ログイン画面を修正\n詳しい条件` | title/fullTitleともに `ログイン画面を修正` |
| `\r\n  API\t の　接続を修正  \r\n次の行` | 両方 `API の 接続を修正` |
| `ＡＰＩ　１２３を修正` | 両方 `API 123を修正` |
| 空文字、空白のみ、改行のみ | `nil` |
| `/review`、`／review 引数` | `nil` |
| `/review\nログイン画面を修正` | 両方 `ログイン画面を修正` |
| バッククォート3個の開始行、コード、対応する終了行だけ | `nil` |
| 上記の閉じたフェンスの次行が `ログインを修正` | 両方 `ログインを修正` |
| チルダ3個のフェンス | バッククォートと同じ除外規則 |
| バッククォート4個で開始し、3個の行しかない | 開始後から候補を採らない |
| バッククォートで開始し、チルダだけで終了を試みる | 開始後から候補を採らない |
| 未閉鎖フェンスの前に適格な行がある | フェンス前の最初の適格行 |
| `    let value = 1\nログインを修正` | 両方 `ログインを修正` |
| `\t説明\nログインを修正` | 両方 `ログインを修正` |
| `import Foundation\nログインを修正` | 両方 `ログインを修正` |
| 各除外接頭辞の行に続く `ログインを修正` | 両方 `ログインを修正` |
| `APIを修正` | 大文字を維持 |
| `abcdefghijklmnopqrstuvwx12345678` | 32文字をそのまま維持 |
| `abcdefghijklmnopqrstuvwx123456789` | titleは `abcdefghijklmnopqrstuvwx1234567…`、fullTitleは入力33文字 |

さらに、`👨‍👩‍👧‍👦` と結合文字 `e\u{301}` をそれぞれ使った32／33 Character境界を検査する。33 Characterの入力では31 Characterと `…` になり、fullTitleを維持する。同一入力への反復呼び出しが同じ結果を返し、入力文字列が変化しないことも検査する。

### 2. 凍結検査

PMが `.claude/scripts/task41-wiring.rb` を作成する。見本は `.claude/scripts/task38-wiring.rb` と `.claude/scripts/task39-wiring.rb`。文字列導出の正しさはSwift Testingで検査し、Rubyへの再実装で代替しない。

Ruby検査は以下を要求する。

- `TASK41_BASELINE` はコミットSHA必須。契約の `baseline_commit` と完全SHAに解決して一致させる。
- `HEAD`、`HEAD~1`、`@`、ブランチ名、未設定時のフォールバックは禁止する。
- `git show <凍結SHA>:<path>` のblobを基準にする。受け入れテストとRuby自身が基準コミットに存在し、現在の内容と一致することを確認する。
- 基準コミットには新規 `SessionTitleDeriver.swift` が存在しないことを確認する。実装入りHEADのSHAを渡す自己比較を拒否する。
- 実装前の凍結時点で指定SHAとHEADが同一であること自体は拒否しない。
- 新規公開APIの存在、許可したimport、I/O・追加AI呼び出しがないことを確認する。コメント・文字列を実コードとして数えない。対象不在・解析不能は非ゼロ終了。
- `--selftest` は実ファイルを変更せず、正例と、SHA未設定・不正・契約不一致・blob欠落・テスト改変・検査改変・実装入り基準・禁止依存・コメントだけの宣言偽装を検査する。

### 3. 検証と開示

凍結時の受け入れ確認：

```sh
~/.agents/scripts/compact-test task41-models bash macos/scripts/run-swift-tests.sh AgentDomain
~/.agents/scripts/compact-test task41-wiring-selftest ruby .claude/scripts/task41-wiring.rb --selftest
~/.agents/scripts/compact-test task41-wiring env TASK41_BASELINE=<凍結SHA> ruby .claude/scripts/task41-wiring.rb
```

実装後の統合確認は既存の正本を使う。

```sh
~/.agents/scripts/compact-test task41-integration bash .claude/verify.sh
```

`<凍結SHA>` はPMが実値に置換する。確認した `.claude/verify.sh` は8パッケージ、更新隔離検査、`git diff --check` を実行する。受け入れテストとRuby検査の実行結果を別に記録する。

変更は純粋関数の新設だけであり、App画面の目視ゲートは対象外。独立したlint・静的解析設定は今回の探索範囲では見つかっていない。PMは凍結時に設定を再確認し、未設定と未実行を区別する。

`docs/agent-output/task-41.md` に、導出契約の実装状況、実行コマンド・結果、未検証事項、変更パスを記録する。製品にも検証にも実claude／codex／cursorセッションの起動を要求しない。

## レビュー観点（Rubric）

- **文字列契約**：除外順序、フェンス対応、幅変換、32／33 Character境界が期待値どおり。
- **純粋性**：入力を変更せず、I/O・設定・追加AI呼び出しに依存しない。
- **責務境界**：名前状態、保存、View、呼び出し元を変更していない。
- **検証の独立性**：Swift Testingが実関数を検査し、凍結blob・`--selftest` が検査の改変と自己比較を拒否する。
- **報告の正確さ**：task-41の成立をUX-01全体の完了と報告していない。

=== FILE: tasks/task-44.md ===
---
id: task-44
difficulty: deep
depends_on: [task-41]
user_visible: true
acceptance_tests:
  - macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleStateTests.swift
  - macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDescriptorTests.swift
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionTitleLifecycleTests.swift
  - macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceSessionTitlePersistenceTests.swift
  - .claude/scripts/task44-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleState.swift
  - macos/Packages/AgentDomain/Sources/AgentDomain/PersistedSessionDescriptor.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ControllableSession.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/SessionViewModel.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionRestoreCoordinator.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionPersistenceCoordinator.swift
  - docs/agent-output/task-44.md
---

## 目的

UX-01 の名前状態を **手動名 > 導出名 > 花名** に統一し、チャットの最初の適格なユーザー発言、リネーム、保存・復元を接続する。旧データと手動名を保護し、非同期処理の順序によって名前が巻き戻らないようにする。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:78`。文字列導出は成立済みのtask-41を利用する。主名・補助名の描画、tooltip、アクセシビリティ表示はtask-45が担当する。

本契約の難しさは、復元待ち中の手動変更、初回保存前の変更、削除との競合、descriptorの後方互換にある。調査対象HEADは `cb17de2193f80010a5126e19b2265b018452a2d7`。今回の起草でファイル変更・テスト実行・ビルド・GUI確認は行っていない。

## 入出力契約

### 担当・依存・実コードの起点

Cursorは `allowed_paths` 内の製品と開示レポートのみ実装する。PMがSwift TestingとRuby検査を先に作成・red確認・凍結し、別モデルがレビューする。Appターゲットにテストを置かず、新規依存・パッケージを追加しない。

task-41成立後に本契約を凍結する。基準コミットにはtask-41の製品と本タスクの受け入れテスト・Ruby検査を含め、task-44の製品実装を含めない。task-41、task-45との変更許可パスの交差はない。

以下は今回実ファイルで再確認した起点である。パッケージ内の相対パスは表中に示す。

| 対象 | 確認した起点 |
|---|---|
| 共通の名前窓口 | SessionFeatureの `ControllableSession.swift:20` に `name`、`:21` に `displayName`。同ファイルの `SessionNode` が中継 |
| 現在の表示名 | `ChatSessionViewModel.swift:578`、`SessionViewModel.swift:75`。トリム後の空名は短縮ID |
| 短縮ID | `SessionViewModel.shortID(for:)`、`SessionViewModel.swift:80` |
| ユーザー入力 | `ChatSessionViewModel.sendText(_:submit:)`、`:2792`。本文は `pendingInput + text`、送信用の補足付き文字列は `clientInput` |
| transcript格納・復元 | `appendOrReplace`、`:2366`。`applyRestoredTranscript`、`:2402` |
| ユーザー発言抽出 | `InputHistoryPolicy.entries(from:)`、`InputHistoryPolicy.swift:13` |
| 別のユーザー本文格納経路 | `ChatSessionViewModel.sendSubAgentFollowUp`。メインtranscriptへユーザー本文を格納し、送信用の組み立て文字列と分けている |
| PTY | `SessionViewModel.sendText(_:submit:)`、`:796`。直接入力の `sendInput(_:)` も存在 |
| 名前生成 | DashboardFeatureの `Dashboard/DashboardViewModel.swift:1019` から既存名集合を作り、次行で `FlowerNameGenerator.random(avoiding:)` |
| リネーム | `DashboardViewModel.renameSession(_:to:)`、`:827` |
| 保存 | `SessionPersistenceCoordinator.enqueue`、`:64`。`persistSessionName`、`:121`。`persistSessionWorkspace`、`:178` |
| 保存待ち | `SessionPersistenceCoordinator.waitForPendingWrites()`、`:84` |
| 復元失敗 | `SessionSpawnService.makeRestoreErrorSession`、`:721`。`makeRestoreErrorChatSession`、`:770` |
| CLI／認可 | `macos/scripts/phlox:331` の `cmd_rename` → Control API → `AppBootstrap/ControlActionHandler.swift:386` の `handleRename` → 同じ `renameSession` |
| 空名の既存テスト | `DashboardViewModelTests.swift:735` の `renameSession_emptyNamePersistsAndRestoresShortID` |

`PersistedSessionDescriptor` の両initializer、CodingKeys、decode、encode、値コピーによる `updating` 群も確認した。

### 依存先の入力契約

task-41は次を供給する。

```swift
SessionTitleDeriver.derive(from: String) -> DerivedSessionTitle?
```

`DerivedSessionTitle` は `title` と `fullTitle` を持つ。最初の適格な候補行を幅変換・空白整理し、32 Character以内は維持、33以上は先頭31 Characterと `…` にする。導出不可なら `nil`。

本タスクは導出規則を複製・変更しない。例として `ログイン画面を修正\n詳細` は `ログイン画面を修正`、`/review` は `nil` になる。

### 新規の名前状態API

以下は新規契約であり、`AgentDomain/SessionTitleState.swift` に置く。

```swift
public enum SessionTitleSource: String, Codable, Hashable, Sendable {
    case flower
    case derived
    case manual
}

public struct SessionTitleState: Equatable, Sendable {
    public let name: String
    public let source: SessionTitleSource
    public let flowerName: String?
    public let fullDerivedTitle: String?

    public init(
        name: String,
        source: SessionTitleSource,
        flowerName: String?,
        fullDerivedTitle: String?
    )

    public static func generated(flowerName: String) -> Self
    public static func legacy(name: String) -> Self
    public func receivingUserMessage(_ text: String) -> Self
    public func renamed(to name: String) -> Self
    public func effectiveName(fallback: String) -> String
}
```

このファイルは状態と有効名だけを扱う。task-45の `SessionTitlePresentation` やViewには依存しない。

| 操作・状態 | 結果 |
|---|---|
| 新規生成 | `.flower`。nameとflowerNameは生成した花名、fullDerivedTitleはnil |
| `.flower` に適格な本文 | `.derived`。nameは短縮済みtitle、fullDerivedTitleは候補行全文、flowerNameを維持 |
| `.flower` に導出不可の本文 | 無変更。次の適格なユーザー本文を候補にできる |
| `.derived`／`.manual` に本文 | 無変更 |
| 明示的リネーム | `.manual`。前後の空白・改行だけを除き、花名を維持、導出全文を解除 |
| 花名と同じ文字列へリネーム | `.manual`。文字列一致で自動状態に戻さない |
| 空欄へリネーム | `.manual`、nameは空。以後も自動命名しない |
| `legacy(name:)` | 保存名を手動扱いで保持。花名と導出全文はnil |
| `effectiveName(fallback:)` | nameの前後の空白・改行を除き、空ならfallback。文字数による短縮はしない |

手動名の内部改行・空白・長さを表示都合で破壊しない。空の補助花名はnilとして扱う。

### VM・共通窓口

- 両VMに現在の `SessionTitleState` を保持し、公開読み取り窓口 `titleState` を新設する。
- `ControllableSession` に `var titleState: SessionTitleState { get }` を追加する。既存の適合型を壊さないよう、既定実装は `.legacy(name: name)` とする。実製品の両VMは保持状態を返す。
- `SessionNode.titleState` は実VMの状態を中継する。花名・導出全文を別々のView用状態として複製しない。
- `name` の読み取りは状態のnameを返す。通常の代入は `renamed(to:)` による手動変更とする。
- `displayName` は `titleState.effectiveName(fallback:)` に接続し、fallbackには既存 `SessionViewModel.shortID(for:)` を渡す。
- 新規生成・通常復元・復元失敗は専用の状態設定経路を使う。生成した花名を通常の `name` 代入で設定して手動状態にしない。
- 自動導出と通常の手動変更から保存へ到達する。復元状態を取り付けただけでは移行保存しない。
- 表示モデルをtask-45が利用できるよう、この読み取りAPIまで本タスクで成立させる。task-45でVM・protocolの追加変更を要求しない。

### チャットの接続

対象は、そのセッションのメインtranscriptに確定した `.userMessage` の本文。アシスタント回答、ツール結果、エラー、質問回答カード、別サブエージェントのtranscriptは対象外。

- `sendText` の格納本文を使い、`clientInput` の補足、スキルファイル本文、画像パス・ファイル名から導出しない。
- `submit == false`、入力途中、送信前検証で拒否された入力では命名しない。
- 添付だけの本文が空の入力は命名しない。
- ローカルtranscriptへの確定後に通信が失敗した場合は導出名を保持する。送信成功を意味する状態にはしない。
- 追加・置換・復元の実経路から最初の適格な本文へ到達する。別々の経路に異なる導出規則を置かない。
- `sendSubAgentFollowUp` がメインtranscriptへ保存するユーザー本文も対象とする。送信用に付加するサブエージェント識別文は混入させない。別サブエージェントのtranscript自体は走査しない。
- 復元の抽出には既存 `InputHistoryPolicy.entries(from:)` を再利用できる。
- `.derived`／`.manual` 確定後はタイトル目的の全件走査を行わない。
- `await` 後の適用時点で現在状態を再評価し、待機中に行われた手動リネームを古い導出結果で上書きしない。
- 重複イベント、履歴再読込、会話巻き戻しで確定済みの名前を変更しない。

### descriptorの後方互換

`PersistedSessionDescriptor` に、両initializerで既定値nilの任意フィールドを追加する。

```swift
titleSource: SessionTitleSource?
flowerName: String?
fullDerivedTitle: String?
```

さらに、新規読み取り窓口 `titleState: SessionTitleState` と、一体更新用の `updating(titleState:)` を設ける。既存の `name` はCLI・既存クライアントが読む有効な名前として維持する。

- 両initializer、CodingKeys、decode、encode、workspace変更時の再構築で新規フィールドを扱う。
- `titleSource` 不在／nullの旧データは手動名として保護する。`Rose`、通常名、空名を同じ規則で扱う。
- 花名一覧や番号接尾辞から旧名の由来を推測しない。旧データに花名を生成して補わない。
- 未知の `titleSource` 文字列だけを理由にdescriptor全体を破棄しない。保存名を手動扱いで保持し、既存診断方式で記録する。
- `.derived` はfullDerivedTitleが適格な候補行であり、それから得られるtitleが保存nameと一致する場合だけ採用する。不整合なら保存nameを手動扱いで保護し、診断を記録する。
- `.flower` は非空のflowerNameとnameが一致し、導出全文がない場合だけ採用する。不整合なら保存nameを手動扱いで保護する。
- 手動状態では導出全文を使用しない。不整合から手動へ退避しても、有効な元の花名は保持する。
- 読み込みだけで一括移行保存しない。
- 既存 `updating(name:)` を手動変更として扱い、由来がderivedのまま名前だけ変わる状態を作らない。他の `updating` は名前の4フィールドを保持する。
- `token` をencodeしない規則、秘密情報をenvから除く規則、既存ID・backend・resume・親子関係・role・launchContext等を維持する。

### 保存・復元・rename

- UIとCLIの既存rename経路は、`DashboardViewModel.renameSession` から手動状態の一体更新へ到達する。Control APIの認可・HTTP仕様は変えない。
- name・source・flowerName・fullDerivedTitleを一つのdescriptor更新として保存する。フィールドごとの非同期保存に分けない。
- 保存順は既存 `SessionPersistenceCoordinator.enqueue` を使う。独自キュー・タイマー・debounceを追加しない。
- 初回descriptor保存前に名前が変わった場合も、初回保存には最新状態を反映する。未登録IDへの名前更新が捨てられ、古い花名が後から保存される状態を残さない。
- 導出直後の手動変更は、保存待ちを解消した後も手動名が勝つ。
- 削除後の遅延した名前更新でdescriptorを再作成しない。起動中削除を防ぐ既存の生存確認も維持する。
- 通常復元、PTY・チャット両方の復元失敗プレースホルダで名前状態を保持する。
- workspace移動と他フィールド更新でメタ情報を落とさない。
- 名前に関する保存失敗は既存のエラー記録経路へ伝える。初回保存に含まれる名前の失敗も黙殺しない。表示更新を保存成功として報告しない。
- 花名の重複回避は既存名に加え保持されたflowerNameも参照する。作業名への変更直後に同じ花名を再利用しない。`FlowerNameGenerator` 自体の抽選規則は変えない。

### PTY方針

PTYでは自動導出しない。新規は花名、明示的rename後は手動名とする。

`sendText` と直接入力の片方だけで命名しない。端末出力、エコー、端末タイトル、バイト列の蓄積から本文を推測しない。既存の送信内容、bracketed paste、待機時間、submit判定、フック、端末所有権・載せ替えを維持する。

## 成功基準

### 1. AgentDomainのSwift Testing

PMは以下をリテラル期待値で凍結する。

- `generated(flowerName: "Rose")` はflower状態、name／flowerNameが `Rose`、導出全文nil。
- `/review` では無変更。その後の `ログイン画面を修正\n詳細` でderivedへ遷移し、花名を保持。
- 二度目の適格な依頼・同じ本文の再配送で不変。
- 手動名 `通知を修正`、花名と同じ手動名 `Rose`、空の手動名は後続入力で不変。
- 空名の `effectiveName(fallback: "abc123")` は `abc123`。長い手動名は短縮しない。
- リネームは前後の空白・改行だけを除き、導出全文を解除する。
- 旧JSONの `Rose`、通常名、空名は手動扱い。元の花名を捏造しない。
- 新JSONの3状態、nil、未知の由来、derived／flowerの不整合を前記規則どおり扱う。
- 両initializerとencode/decode往復で名前状態を維持する。
- `updating(titleState:)`、`updating(name:)`、既存の他フィールド更新で、変更対象以外のフィールドを維持する。
- token非出力、秘密env除去、旧backend・native session IDの互換規則を維持する。

### 2. SessionFeature／DashboardFeatureのSwift Testing

実claude／codex／cursorを起動しない。既存 `StructuredAgentClient` のテスト用実装パターン、`InMemorySessionStore`、制御可能な非同期応答を利用する。追加のテスト用クライアント・ストアもPMが受け入れテスト内に作成し、Cursorへ作成を要求しない。

| 検査対象 | 固定する結果 |
|---|---|
| 未確定入力 | `submit == false` は状態を変えない |
| 確定入力 | `pendingInput + text` の保存本文から導出 |
| 補足・添付 | 再送補足、スキル本文、添付名が混入しない |
| 送信前拒否 | タイトルが確定しない |
| 通信失敗 | ローカル確定済み本文の導出名を保持 |
| transcript | 追加・置換・復元から到達し、重複・巻き戻しで確定名が揺れない |
| 対象外項目 | assistant・tool・error・質問回答・別サブエージェントtranscriptでは命名しない |
| follow-up | メインtranscriptのユーザー本文を使い、送信用の識別文を混入させない |
| 復元競合 | 復元待機中の手動renameが勝つ |
| 状態復元 | flower／derived／manual／空名が保存・復元後も一致 |
| 初回保存競合 | 初回保存前の自動名・手動名が最新状態で残る |
| 保存順 | 導出→手動renameの順で操作すると最終保存がmanual |
| 削除競合 | 削除後の遅延更新がセッションを再作成しない |
| workspace移動 | 名前状態と無関係なメタ情報を保持 |
| 保存失敗 | エラー記録へ到達する |
| 復元失敗 | PTY／チャット両プレースホルダの名前状態を保持 |
| PTY | sendText・直接入力とも自動導出なし |
| 花名重複 | 作業名へ変更済みのセッションのflowerNameも除外集合に含む |

待機時間の長さに依存させず、応答の解放順と `waitForPendingWrites()` で順序を固定する。既存の空名renameテストも維持する。

### 3. Ruby配線・凍結検査

`.claude/scripts/task44-wiring.rb` は次を検査する。

- 両VM・ControllableSession・SessionNodeの状態読み取りと有効名の接続。
- 新規生成、通常復元、両復元失敗経路の状態受け渡し。
- 実際のユーザー本文格納・復元経路から導出への到達。
- UI／CLI renameから手動状態と一体保存への接続。
- descriptorの両initializer・CodingKeys・decode・encode・workspace転記のフィールド網羅。
- 初回保存で最新状態を取得し、削除防止経路を維持していること。
- 名前関連以外の送信、認可、PTY、秘密情報除去を凍結blobと比較して維持していること。
- task-41の導出ソースを凍結blobと比較して保護すること。
- 命名専用のAI呼び出し・プロセス起動が追加されていないこと。

比較から除外するのは明示した名前関連差分だけとし、変更した関数全体を無条件に除外しない。コメント・文字列・未使用ヘルパー・`if false` の一致では合格にしない。対象不在・解析不能は非ゼロ終了。

凍結条件：

- `TASK44_BASELINE` は契約と完全SHAで一致するコミットSHA必須。HEAD等の参照名・ブランチ名・未設定時フォールバックは禁止。
- `git show <凍結SHA>:<path>` のblobを使う。
- 受け入れテストとRuby自身が基準コミットに存在し、現在の内容と一致する。
- 基準にtask-41が存在し、新規 `SessionTitleState.swift` とtask-44の配線が存在しないことを確認する。実装入り基準による自己比較を拒否する。
- 実装前に指定SHAとHEADが一致すること自体は拒否しない。

`--selftest` は実ファイルを変更せず、正例と、生成花名の手動代入、復元失敗のフィールド欠落、workspace転記漏れ、renameの手動化欠落、保存接続欠落、PTY・認可・秘密情報除去の改変、偽装コード、SHA／blob／凍結テストの各異常を検査する。

### 4. 既存契約との衝突解消・検証

現行 `.claude/scripts/task39-wiring.rb` の `UNCHANGED_PATHS` には `SessionViewModel.swift` が含まれる。本タスクを実装しながら現行の全ファイル不変検査をそのまま通すことはできない。

PMはtask-44凍結前に、task-39の端末所有権・載せ替え・入出力を保護しつつ、名前関連差分だけを許す検査へ正式に改訂する。旧凍結blobとの保護関係、検査自身の凍結整合、正例・負例、別モデルのレビューを記録する。task-45が変更する `SessionView.swift` と `PaneLayoutView.swift` も同じ衝突対象として扱う。基準SHAのすり替え、検査削除、失敗無視では解決しない。未解決なら本契約を凍結しない。

凍結時の受け入れ確認：

```sh
~/.agents/scripts/compact-test task44-models bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
~/.agents/scripts/compact-test task44-wiring-selftest ruby .claude/scripts/task44-wiring.rb --selftest
~/.agents/scripts/compact-test task44-wiring env TASK44_BASELINE=<凍結SHA> ruby .claude/scripts/task44-wiring.rb
```

実装後の統合確認：

```sh
~/.agents/scripts/compact-test task44-integration bash .claude/verify.sh
~/.agents/scripts/compact-test task44-appbootstrap bash macos/scripts/run-swift-tests.sh AppBootstrap
```

改訂したtask-39検査はPMが凍結した手順で実行する。AppBootstrapは現行verifyの8パッケージに含まれないため、rename認可の回帰確認として別実行する。

Appビルドは `macos` を作業ディレクトリにし、今回専用の出力先を指定する。

```sh
~/.agents/scripts/compact-test task44-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用の絶対パス> -destination platform=macOS build
```

プレースホルダはPMが実値へ置換する。lint・静的解析は凍結時に設定を再確認し、未設定・対象外・未実行を区別する。パッケージテスト・ビルド・GUI確認を読み替えない。

### 5. PMの可視動作ゲート

本タスクは既存の `displayName` とrename挙動を変えるため `user_visible: true` とする。task-45の表示レイアウト完成は本タスクの合格条件に含めない。

PM確認済みの復元失敗用 `sessions.json` を隔離先へ複製し、nameと必要な新規メタ情報を設定する。実行ファイル不在等の復元失敗条件を維持し、実AIクライアントを起動しない。

今回のDebug実行ファイルを、専用の `PHLOX_DATA_DIR`、`PHLOX_DEFAULTS_SUITE`、`PHLOX_AGENTS_JSON`、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` で起動する。通常のRelease／Debug保存先を使わず、既存インスタンスを停止する `debug-build-restart.sh` は使用しない。

既存の名前表示で旧名・derived名・空名を確認し、UIで手動rename、空欄rename、保存待ち、同じ隔離環境での再起動を行う。実PID・実行ファイル・ウィンドウ所有PIDを照合し、結果をPM専有の `docs/agent-output/visual-task-44.md` に残す。今回起動した不要なプロセスだけを終了する。

チャット画面は復元失敗プレースホルダで課金なしに表示できるが、transcript本文は表示されない。この目視を自動導出・正常なAI応答・実CLI送信の検証として扱わない。自動導出と非同期順序はSwift Testingが担う。

Cursorは `docs/agent-output/task-44.md` に各責務の実装状況、検証結果、未検証事項を記録する。PM目視レポートはCursorの変更許可パスに含めない。

## レビュー観点（Rubric）

- **優先順位**：旧名・花名と同じ手動名・空名を自動処理が上書きしない。
- **接続**：保存されたユーザー本文から到達し、送信用補足や別transcriptを混入させない。
- **非同期整合**：復元、初回保存、手動変更、削除の前後関係で最新状態を失わない。
- **後方互換**：未知の由来でセッションを破棄せず、コピー・workspace移動でも名前状態を保持する。
- **PTY・認可**：入力経路・所有権・HTTP認可・秘密情報除去を維持する。
- **分割境界**：表示モデルを先取りせず、task-45に必要な状態読み取りAPIが成立している。
- **証拠と費用**：Swift Testing、Ruby、Appビルド、隔離目視を区別し、課金セッションを要求しない。

=== FILE: tasks/task-45.md ===
---
id: task-45
difficulty: standard
depends_on: [task-44]
user_visible: true
acceptance_tests:
  - macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitlePresentationTests.swift
  - .claude/scripts/task45-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitlePresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/SessionView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift
  - docs/agent-output/task-45.md
---

## 目的

UX-01 の表示を完成させる。作業名を主、元の花名を補助として4表示面に示し、長い名前の省略表示とhelp・アクセシビリティからの全文確認を両立する。

仕様の正本は `macos/docs/specs/ui-ux-improvement-backlog.md:78`。名前状態と保存は成立済みtask-44を読み取り、表示処理から変更しない。UX-01の完了はtask-41、task-44、本契約の成立後とする。

調査対象HEADは `cb17de2193f80010a5126e19b2265b018452a2d7`。以下の起点を実ファイルで再確認した。今回の起草ではファイル変更、テスト実行、ビルド、GUI確認を行っていない。

## 入出力契約

### 担当・依存・境界

- Cursorは `allowed_paths` 内の製品と開示レポートだけを実装する。PMがSwift TestingとRuby検査を作成・red確認・凍結し、別モデルがレビューする。
- task-44成立後に凍結する。基準コミットにはtask-41・task-44の成立済み製品と本タスクのテスト・Ruby検査を含め、task-45の製品実装を含めない。
- 新規依存・パッケージ・Appターゲットのテストを追加しない。
- 3契約の `allowed_paths` は互いに交差しない。表示モデルを新規ファイルに置くため、task-44の状態ファイル・VM・protocolを編集する必要はない。
- 名前の導出、状態遷移、保存スキーマ、rename処理、PTY方針は変更しない。

### 実コードで確認した4表示面

| 表示面 | 現行の起点と本タスクの変更 |
|---|---|
| サイドバー行 | `DashboardSidebarView.swift:437` の `SessionSidebarRowView`。名前のTextは`:462`。主名・補助名の表示へ置換 |
| グリッドヘッダー | `SessionGridView` → `PaneLayoutView` → `PaneTileView.header`。ヘッダーは `PaneLayoutView.swift:324`、名前Textは`:330` |
| 単体PTYヘッダー | `DashboardDetailView.singleDetail` のPTY分岐 → `SessionView`。現状の上部はアイコンと開始日時。名前領域を追加 |
| 単体チャットヘッダー | 同じ `singleDetail` のチャット分岐 → `ChatSessionView.mainColumn(width:)`、`:117`。現状はApprovalBannerから始まる。名前領域を追加 |

草案で確認された4面を対象とする。チームカード等の追加表示面は、本契約の対象として実コード確認していないため追加しない。

サイドバーの名前Textは旧草案の456行目から現行462行目へ変わっている。実装時は行番号だけでなく上記シンボルから辿る。単体2面には既存の名前Textがあると仮定しない。

グリッドのチャット本文は `PaneLayoutView.swift:257` の `GridChatColumn` を使う。単体 `ChatSessionView` と区別し、単体用ヘッダーをグリッドへ二重に追加しない。

### 依存先の読み取り契約

task-44は以下を供給する。

```swift
SessionTitleState.name: String
SessionTitleState.source: SessionTitleSource
SessionTitleState.flowerName: String?
SessionTitleState.fullDerivedTitle: String?
SessionTitleState.effectiveName(fallback: String) -> String
```

sourceはflower／derived／manual。両VM・ControllableSession・SessionNodeから `titleState` を読み取れる。

- flowerは生成した花名。
- derivedは最初の適格な候補行から作った32 Character以内のnameと、省略前のfullDerivedTitle。
- manualは長さを切らない手動名。空名は短縮IDへフォールバックする。
- 旧データ・未知由来・不整合の保護はtask-44で処理済み。Viewはそれを再判定しない。

### 新規表示モデル

`AgentDomain/SessionTitlePresentation.swift` に以下を新設する。型・メンバー名は新規契約である。

```swift
public struct SessionTitlePresentation: Equatable, Sendable {
    public let primary: String
    public let secondary: String?
    public let fullTitle: String
    public let helpText: String
    public let accessibilityValue: String

    public init(
        state: SessionTitleState,
        fallback: String,
        workspacePath: String
    )
}
```

純粋な値変換とし、View・ファイル・設定・ネットワーク・プロセスに依存しない。

| 出力 | 規則 |
|---|---|
| primary | `state.effectiveName(fallback:)` |
| secondary | 非空のflowerNameがあり、primaryと異なる場合だけその花名 |
| fullTitle | derivedは保存されたfullDerivedTitle。それ以外はprimary |
| helpText | fullTitle、存在する場合の `花名: <flowerName>`、`作業場所: <workspacePath>` を改行で連結 |
| accessibilityValue | fullTitleそのもの |

fallbackには呼び出し側から既存 `SessionViewModel.shortID(for:)` を渡す。

flowerNameがprimaryと同じ場合は補助表示を出さないが、helpの花名行は保持する。元の花名がない旧データでは花名行を省く。空欄への手動renameでは主名と全文は短縮ID、元の花名があれば補助表示に使う。

「全文」はderivedでは候補行全文、manualでは手動名全文を指す。元の依頼全文・transcript全文をhelpに出さない。状態の正規化や導出を表示モデル内で再実行しない。

### 描画・全文確認

4面とも実際の状態から表示モデルを構築し、その結果を表示する。

- 作業名を先、花名を後に配置する。花名は既存の小さい文字と副次文字色を使う。
- 主名は `.lineLimit(1)` と `.truncationMode(.tail)`。表示モデルで手動名を切り詰めず、実幅による省略に任せる。
- 補助花名も1行、省略可。主名を押し出さず、主名を優先して幅を割り当てる。
- 名前領域の `.help` に `helpText` を渡す。既存のworkspaceだけのhelpが名前領域の全文helpを覆わないようにする。
- 名前領域をアクセシビリティ要素として全文へ到達可能にし、そのvalueへ `accessibilityValue` を渡す。
- サイドバーの行全体には既存の選択状態用AX valueがある。名前のAX valueは子の名前領域へ付け、行の `emphasis.accessibilityValue` を置換しない。
- 読み上げで省略前タイトルと既存の選択・状態が確認できること。装飾の花名が重複読み上げにならないようにする。
- 状態表示、エージェントアイコン、開始日時、workspace表示、選択・展開・ドラッグ・閉じる・rename操作を維持する。
- `PaneTileView.header` の `.draggable` と後続の `.simultaneousGesture` の順序を維持する。
- 単体チャットの名前領域追加に合わせ、「カラム内ヘッダー行は置かない」という同ファイル内の旧コメントも更新する。
- `body`、表示開始、hover、AX取得から導出・状態更新・保存を実行しない。
- 入力先表示、チーム役割、本文レンダリング、端末所有権・載せ替えは変更しない。

## 成功基準

### 1. 表示モデルのSwift Testing

PMは以下のリテラル期待値を固定する。状態はtask-44の公開APIから構築する。

| 状態、fallback=`abc123`、workspacePath=`/tmp/project` | primary／secondary／fullTitle |
|---|---|
| 新規花名 `Rose` | `Rose`／nil／`Rose` |
| `ログイン画面を修正` を導出、元花名 `Rose` | `ログイン画面を修正`／`Rose`／`ログイン画面を修正` |
| 手動名 `通知を修正`、元花名 `Rose` | `通知を修正`／`Rose`／`通知を修正` |
| 手動名 `Rose`、元花名 `Rose` | `Rose`／nil／`Rose` |
| 空の手動名、元花名 `Rose` | `abc123`／`Rose`／`abc123` |
| 旧名 `Rose`、元花名なし | `Rose`／nil／`Rose` |
| 旧空名、元花名なし | `abc123`／nil／`abc123` |
| 33文字の手動名 | primary／fullTitleとも33文字を維持 |
| 33文字からのderived状態 | primaryは31文字と `…`、fullTitleは33文字を維持 |

さらに次を固定する。

- 花名ありのhelpは `ログイン画面を修正\n花名: Rose\n作業場所: /tmp/project`。
- 花名なしの旧名 `Rose` のhelpは `Rose\n作業場所: /tmp/project`。
- 空workspaceは `作業場所: ` とし、別パスを推測しない。
- accessibilityValueはfullTitleと一致する。
- 日本語、長い英数字、複合絵文字、内部改行を含む手動名の全文を保持する。
- モデル構築を繰り返しても同じ結果で、入力状態を変更しない。
- 表示モデルの検査をSwiftUIソース文字列の一致だけで代替しない。

### 2. Ruby配線・凍結検査

PMが `.claude/scripts/task45-wiring.rb` を作成する。

検査対象：

- 4面の到達可能な名前領域が実セッションのtitleStateから表示モデルを使う。
- primary／secondaryの表示、主名の1行・末尾省略、全文help、名前のAX valueが接続される。
- 花名の表示条件をView側で別実装しない。
- サイドバーの既存選択用AX valueと状態表示を維持する。
- 単体PTY・単体チャットへ名前領域が追加され、グリッド本文へ単体用タイトルを重複追加していない。
- workspace・開始日時・状態・閉じるボタン・ドラッグと選択の既存接続を保護する。
- Viewから導出・rename・保存を呼ばない。
- task-41・task-44の製品ソースは本タスクの凍結blobから不変である。

比較は名前領域とそれに必要なレイアウト差分だけを許し、Viewやheader関数全体を比較対象から外さない。コメント・ダミー文字列・未使用ヘルパー・`if false` に名前を置いても合格にしない。対象不在・解析不能は非ゼロ終了。

凍結条件：

- `TASK45_BASELINE` は契約と完全SHAで一致するコミットSHA必須。HEAD等の参照名・ブランチ名・未設定時フォールバックは禁止。
- `git show <凍結SHA>:<path>` のblobを基準にする。
- 受け入れテストとRuby自身が基準コミットに存在し、現在の内容と一致する。
- 基準にはtask-44が存在し、新規 `SessionTitlePresentation.swift` とtask-45の表示配線が存在しないことを確認する。
- 実装入りHEADのSHAを渡す自己比較を拒否する。実装前に指定SHAとHEADが一致すること自体は拒否しない。

`--selftest` は実ファイルを変更せず、正例と次の負例を持つ。

- 4面それぞれを一面ずつ未接続にする。
- 全文の代わりに短縮済みprimaryをhelp／AXへ渡す。
- 1行・末尾省略・secondary条件の欠落。
- サイドバー行の選択用AX valueを名前で上書きする。
- グリッドへの二重ヘッダー追加。
- ドラッグ・選択順序、状態表示、端末接続の改変。
- Viewから保存する処理の追加。
- コメント・文字列・未使用コードによる偽装。
- SHA未設定・不正・契約不一致・blob欠落・実装入り基準・テスト／Ruby改変。

### 3. 既存契約・検証コマンド

task-39の現行全ファイル不変対象には `SessionView.swift` と `PaneLayoutView.swift` が含まれる。PMはtask-44で裁定した検査改訂が本タスクの名前領域変更も正当に許し、端末所有権・載せ替え・入出力を引き続き保護することを凍結前に確認する。未解決なら凍結せず、Cursorに検査変更を要求しない。

凍結時の受け入れ確認：

```sh
~/.agents/scripts/compact-test task45-models bash macos/scripts/run-swift-tests.sh AgentDomain
~/.agents/scripts/compact-test task45-wiring-selftest ruby .claude/scripts/task45-wiring.rb --selftest
~/.agents/scripts/compact-test task45-wiring env TASK45_BASELINE=<凍結SHA> ruby .claude/scripts/task45-wiring.rb
```

実装後は既存の統合ゲートと、先行契約の成立を確認する。

```sh
~/.agents/scripts/compact-test task45-integration bash .claude/verify.sh
~/.agents/scripts/compact-test task45-task41-wiring env TASK41_BASELINE=<task-41凍結SHA> ruby .claude/scripts/task41-wiring.rb
~/.agents/scripts/compact-test task45-task44-wiring env TASK44_BASELINE=<task-44凍結SHA> ruby .claude/scripts/task44-wiring.rb
```

改訂したtask-39検査もPMの凍結手順で実行する。Appビルドは `macos` を作業ディレクトリにして実行する。

```sh
~/.agents/scripts/compact-test task45-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用の絶対パス> -destination platform=macOS build
```

プレースホルダはPMが実値へ置換する。lint・静的解析設定は凍結時に再確認し、未設定・対象外・未実行を区別する。ビルド成功をGUI確認済みと扱わない。

### 4. PM目視ゲート

**sessions.jsonの復元失敗プレースホルダでチャット画面・入力欄を課金なしに表示できることはPM確認済み。transcript本文は表示されない。** 本契約の目視はこの方法だけで成立させ、実claude／codex／cursorセッションを要求しない。

1. 今回のDebugビルド、専用データディレクトリ、defaults suite、エージェント定義を用意する。通常のRelease／Debug保存先を使用しない。
2. PM確認済みの復元失敗用データを隔離先へ複製する。実行ファイル不在等の失敗条件を保ち、実AIクライアントへ接続しない。
3. アプリ停止中に隔離先の `sessions.json` のnameを編集する。同一プロジェクトに `ログイン画面を修正`、`通知の重複を修正`、長い日本語名、長い英数字名、空名を用意する。
4. 旧データ用は新規メタ情報なしとする。補助花名用にはtask-44と整合するtitleSource・flowerName・fullDerivedTitleを設定する。derivedのnameはtask-41の32 Character規則に合わせる。この注入を自動導出の実走証拠にしない。
5. `PHLOX_DATA_DIR`、`PHLOX_DEFAULTS_SUITE`、`PHLOX_AGENTS_JSON`、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を指定して今回の実行ファイルを隔離起動する。既存インスタンスを停止する `debug-build-restart.sh` は使わない。
6. 起動PID・実行ファイル・ウィンドウ所有PIDを照合する。サイドバー、グリッド、単体PTY、単体チャットの4面で主名・補助花名を確認する。
7. 通常幅とウィンドウ幅1024ptで撮影し、主名優先、末尾省略、重なり、ヘッダー重複、閉じる・選択・展開等の操作到達性を確認する。
8. 各面の名前をhoverし、helpから省略前タイトル・元花名・workspaceを確認する。AX valueから全文を確認し、サイドバー行の選択状態と既存状態の読み上げも維持されていることを確かめる。
9. UIで手動renameと空欄renameを行い、保存後に同じ隔離環境を再起動する。名前・補助花名・短縮IDの表示を再確認する。メッセージ送信は行わない。
10. PM専有の `docs/agent-output/visual-task-45.md` にコミット、fixture条件、PID、ウィンドウ寸法、画像、help／AX観測結果を記録する。通常保存先への変更がないことを確認し、今回起動した不要なプロセスだけを終了する。

復元失敗画面の確認を、正常なAI応答・transcript本文表示・実CLI送信の確認として報告しない。4面のいずれかが未観測なら、その面を未検証とし、本タスクの目視ゲートを通過扱いにしない。

Cursorは `docs/agent-output/task-45.md` に表示モデル、4面、省略、help、AXの実装状況と検証結果を記録する。PM目視レポートはCursorの変更許可パスに含めない。

## レビュー観点（Rubric）

- **識別性**：同じプロジェクトの異なる作業を一覧から区別でき、花名が主名を押し出さない。
- **4面の到達性**：確認済みの実描画経路に接続し、単体ヘッダー欠落・グリッド重複がない。
- **全文確認**：derived候補行・手動名全文がhelpとAX valueから確認でき、保存値を切り詰めない。
- **アクセシビリティ**：名前の全文と既存の選択・状態が共存する。
- **操作維持**：ドラッグ・選択・展開・閉じる・rename・端末接続を損なわない。
- **責務境界**：Viewと表示モデルが名前状態・導出・保存を変更しない。
- **証拠と費用**：表示モデルテスト、Ruby、Appビルド、4面の隔離目視を区別し、課金セッションを要求しない。