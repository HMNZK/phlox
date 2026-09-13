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
