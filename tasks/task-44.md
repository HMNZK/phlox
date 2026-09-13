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
baseline_commit: "361f7fa"
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
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift
  - docs/agent-output/task-44.md
---

## 目的

UX-01 の名前状態を **手動名 > 導出名 > 花名** に統一する。チャットの最初の適格なユーザー本文、リネーム、保存・復元を接続し、旧データと手動名を保護する。非同期処理、初回保存、復元完了時の PID 書き戻しによって最新名を失わない。

仕様の正本は `macos/docs/specs/ui-ux-improvement-backlog.md:78`。文字列導出は task-41、主名・補助花名・help・アクセシビリティの描画は task-45 が担当する。

本契約は `docs/agent-output/task44-45-contract-adversarial.md` と 2026-09-13 の PM 裁定を統合した改訂案である。既存調査の HEAD は `cb17de2193f80010a5126e19b2265b018452a2d7`、敵対レビューの HEAD は `dcd9cf313b58e4f2e538e12acd6ac8b5ffae7dd1`。以下の既存行番号は調査時点の参照であり、現在行番号の保証ではない。実装時はシンボルから辿る。

改訂時に確認した HEAD は `412cb9efaa0a40531d002fe0d4f32d914e08e8cb`。その時点でも task-41 の実装には行全体の半角変換が残る。修正契約は確定済みだが、実装成立を前提にしない。本改訂では製品変更・テスト・ビルド・GUI確認を実施していない。read-only のため、連結出力先 `docs/agent-output/contract-rev-task-44-45.md` への保存も未実施。

## 入出力契約

### 担当・依存・変更境界

- Cursor は `allowed_paths` 内の製品と開示レポートのみ実装する。PM が受け入れテストと Ruby 検査を作成・RED 確認・凍結し、別モデルがレビューする。
- task-41 の幅正規化修正、受け入れテスト、変異検査が成立してから本契約を凍結する。現行の誤った半角化を期待値に採用しない。
- 基準コミットには task-41 の成立済み製品、本タスクの受け入れテスト、Ruby 検査を含める。task-44 の製品実装を含めない。
- テスト、Ruby 検査、契約、台帳、目視レポートは PM の管理対象であり、Cursor の変更許可パスではない。
- 新規依存・パッケージ・App ターゲットのテストを追加しない。
- task-41・task-45 と製品の変更許可パスを交差させない。表示モデル、View、名前専用 AI 呼び出しを追加しない。

### 実コードの起点

| 対象 | 既存調査・敵対レビューの起点 |
|---|---|
| 共通の名前窓口 | `ControllableSession.swift:20` の `name`、`:21` の `displayName`、同ファイルの `SessionNode` |
| 現在の表示名 | `ChatSessionViewModel.swift:578`、`SessionViewModel.swift:75` |
| 短縮 ID | `SessionViewModel.shortID(for:)`、`SessionViewModel.swift:80` |
| ローカルユーザー本文 | `ChatSessionViewModel.sendText(_:submit:)`、`:2792`。格納本文は `pendingInput + text`、送信用補足付き文字列は `clientInput` |
| transcript 追加・置換 | `ChatSessionViewModel.appendOrReplace`、`:2366` |
| transcript 復元 | `applyRestoredTranscript`、`:2402` |
| 履歴からのユーザー本文抽出 | `InputHistoryPolicy.entries(from:)`、`InputHistoryPolicy.swift:13` |
| follow-up | `ChatSessionViewModel.sendSubAgentFollowUp`。メイン transcript に保存する本文と送信用識別文を区別 |
| サーバーイベント反映 | `ChatSessionViewModel.swift:2014`、`chatItem(from:)` |
| サーバー履歴復元 | `ChatSessionViewModel.swift:877` → `:2462` → `:2484` |
| PTY 入力 | `SessionViewModel.sendText(_:submit:)`、`:796`、および `sendInput(_:)` |
| 花名生成 | `DashboardViewModel.swift:1019` の既存名集合と、その次の `FlowerNameGenerator.random(avoiding:)` |
| リネーム | `DashboardViewModel.renameSession(_:to:)`、`:827` |
| 保存キュー | `SessionPersistenceCoordinator.enqueue`、`:64` |
| 保存待ち | `SessionPersistenceCoordinator.waitForPendingWrites()`、`:84` |
| descriptor 全体保存 | `SessionPersistenceCoordinator.swift:104` 付近の同一 ID 置換 |
| 名前・workspace 保存 | `persistSessionName`、`:121`、`persistSessionWorkspace`、`:178` |
| 復元完了時の PID 保存 | `SessionRestoreCoordinator.swift:92`。旧 descriptor 由来のスナップショット生成は `:169`、`:221` |
| 復元失敗 | `SessionSpawnService.makeRestoreErrorSession`、`:721`、`makeRestoreErrorChatSession`、`:770` |
| CLI rename | `macos/scripts/phlox:331` → Control API → `ControlActionHandler.swift:386` → 同じ `renameSession` |
| 既存の空名テスト | `DashboardViewModelTests.swift:735` の `renameSession_emptyNamePersistsAndRestoresShortID` |

`PersistedSessionDescriptor` の両 initializer、CodingKeys、decode、encode、各 `updating` と workspace 再構築が変更対象となる。

### task-41 の入力契約

```swift
SessionTitleDeriver.derive(from: String) -> DerivedSessionTitle?
```

`DerivedSessionTitle` は `title: String` と `fullTitle: String` を持つ。最初の適格な候補行を正規化し、32 Character 以内は維持、33 以上は先頭 31 Character と `…` にする。導出不可は `nil`。

幅正規化は確定済み task-41 契約に従う。全角英数字・記号は ASCII、半角カナは全角カナへ変換し、全角カナを半角化しない。

固定例：

- `ログイン画面を修正\n詳細` → title／fullTitle とも `ログイン画面を修正`
- `ｶﾀｶﾅ修正` → `カタカナ修正`
- `ＡＢＣ１２３` → `ABC123`
- `/review` → `nil`

本タスクで導出規則を複製・変更しない。

### 公開名前状態 API

`AgentDomain/SessionTitleState.swift` に置く。

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

状態正規化の正本はこの型とする。公開 initializer は非 failable・非 throwing のまま、不整合入力を以下の規則で正規化する。表示側に不整合状態を渡さない。

#### 不変条件と正規化順序

1. `flowerName` は `.whitespacesAndNewlines` で前後を除去し、空なら `nil`。内部文字列は変更しない。
2. `.manual` は入力 `name` をそのまま保持し、正規化した花名を保持、`fullDerivedTitle` を必ず `nil` にする。旧名の内部改行・空白・長さを破壊しない。
3. `.flower` は正規化済み花名が非 nil、`name == flowerName`、`fullDerivedTitle == nil` の場合だけ成立する。不一致・空花名・空文字を含む非 nil の導出全文は不整合とする。
4. `.derived` は `fullDerivedTitle` が非 nil で、同値を task-41 に渡した結果が非 nil、結果の `fullTitle == fullDerivedTitle` かつ `title == name` の場合だけ成立する。これにより保存全文は正規化済みの単一候補行となる。花名は nil でもよい。
5. 不整合な `.flower`／`.derived` は `.manual` に退避する。入力 `name` と正規化済み花名を保持し、導出全文を解除する。名前を花名や再導出結果で置換しない。
6. 正規化済み状態を再び initializer に渡しても変わらない。

`generated(flowerName:)` は引数の前後を除去して name／flowerName に渡す。空白だけの引数は `(name: "", source: .manual, flowerName: nil, fullDerivedTitle: nil)` になる。

`legacy(name:)` は入力名をそのまま保持する手動状態で、花名・導出全文は nil。旧名から花名を推測しない。

`renamed(to:)` だけが指定名の前後の `.whitespacesAndNewlines` を除去する。内部改行・空白・長さは維持し、手動状態へ遷移、花名を保持、導出全文を解除する。

`effectiveName(fallback:)` は name の前後を除去して返し、空なら渡された fallback をそのまま返す。文字数による短縮はしない。

#### リテラル期待値

表の結果は `(name, source, flowerName, fullDerivedTitle)`。

| 入力 | 結果 |
|---|---|
| `generated(flowerName: " Rose \n")` | `("Rose", .flower, "Rose", nil)` |
| `generated(flowerName: " \n")` | `("", .manual, nil, nil)` |
| `init(name: "Rose", source: .flower, flowerName: " Rose ", fullDerivedTitle: nil)` | `("Rose", .flower, "Rose", nil)` |
| `init(name: "Lily", source: .flower, flowerName: "Rose", fullDerivedTitle: nil)` | `("Lily", .manual, "Rose", nil)` |
| `init(name: "Rose", source: .flower, flowerName: " \n", fullDerivedTitle: nil)` | `("Rose", .manual, nil, nil)` |
| `init(name: "Rose", source: .flower, flowerName: "Rose", fullDerivedTitle: "")` | `("Rose", .manual, "Rose", nil)` |
| `init(name: "修正", source: .derived, flowerName: "Rose", fullDerivedTitle: nil)` | `("修正", .manual, "Rose", nil)` |
| `init(name: "修正", source: .derived, flowerName: "Rose", fullDerivedTitle: "別件")` | `("修正", .manual, "Rose", nil)` |
| `init(name: "修正", source: .derived, flowerName: "Rose", fullDerivedTitle: "修正\n詳細")` | `("修正", .manual, "Rose", nil)` |
| `init(name: "修正", source: .derived, flowerName: " \n", fullDerivedTitle: "修正")` | `("修正", .derived, nil, "修正")` |
| `init(name: " 手動\n名 ", source: .manual, flowerName: " Rose ", fullDerivedTitle: "旧候補")` | `(" 手動\n名 ", .manual, "Rose", nil)` |
| `legacy(name: " Rose ")` | `(" Rose ", .manual, nil, nil)` |

#### 状態遷移

| 操作 | 結果 |
|---|---|
| flower に適格なユーザー本文 | derived。name は title、導出全文は fullTitle、花名を保持 |
| flower に導出不可の本文 | 無変更。次の適格な本文を候補にできる |
| derived／manual に本文 | 無変更。導出関数へ到達しない |
| 明示的 rename | manual。前後のみ除去、花名保持、導出全文解除 |
| 花名と同じ文字列へ rename | manual。文字列一致で flower に戻さない |
| 空欄へ rename | 空名の manual。以後も自動命名しない |
| 重複イベント・履歴再読込・巻き戻し | 確定済みの derived／manual を変更しない |

### VM・共通窓口

- 両 VM は `SessionTitleState` を保持し、公開読み取り窓口 `titleState` を提供する。
- `ControllableSession` に `var titleState: SessionTitleState { get }` を追加する。既存適合型向けの既定実装は `.legacy(name: name)`。製品の両 VM は保持状態を返す。
- `SessionNode.titleState` は実 VM を中継する。花名・導出全文の別キャッシュを作らない。
- `name` の読み取りは状態の name、通常代入は `renamed(to:)` による手動変更。
- `displayName` は `titleState.effectiveName(fallback:)` を使い、fallback は既存 `SessionViewModel.shortID(for:)`。
- 新規生成、通常復元、復元失敗は専用の状態設定経路を使う。花名を通常の name 代入で手動化しない。
- 自動導出と手動変更は保存へ到達する。復元状態の取り付けだけで移行保存しない。
- task-45 はこの読み取り API だけで表示できること。task-45 に VM・protocol の追加変更を要求しない。

### チャット本文の候補採用

タイトルに使うのは、メイン transcript に確定した**元のユーザー本文**。`.userMessage` という種別だけでは候補採用を許可しない。

| 経路 | 採用条件 | 不採用条件 |
|---|---|---|
| ローカル本文 | 送信前検証を通り、メイン transcript に格納された `pendingInput + text`。follow-up も格納前の元本文を使う | `submit == false`、入力途中、送信前拒否、本文のない添付 |
| サーバー開始・完了イベントの反映 | 対応するローカル入力をイベント／項目の識別子で特定できれば、その元本文を使う。独立した元本文フィールド等、補足を含まないと確認できる入力も可 | 送信用 `clientInput` の無条件採用、識別できない補足付き本文、対応関係を文字列の類似性で推測すること |
| ローカル履歴復元 | 保存された元本文と確認できる項目を時系列順に扱う | 送信用文字列や由来不明の項目を元本文扱いすること |
| サーバー履歴復元 | 元本文フィールド、保存済み対応情報等から元本文を識別できる項目だけ採用 | ローカル履歴がなく、返却された補足付き入力から元本文を識別できない場合。花名を維持する |

補足の文言を削るだけの推測や、既知の補足文字列が見つからないことだけを根拠に「元本文」と認定しない。識別不能な項目は飛ばし、後続の識別可能かつ適格な本文を候補にできる。すべて識別不能なら flower のままにする。

- アシスタント回答、ツール結果、エラー、質問回答カード、別サブエージェントの transcript は対象外。
- スキルファイル本文、画像パス・ファイル名、再送補足、サブエージェント識別文を混入させない。
- `sendSubAgentFollowUp` がメイン transcript に保存する元本文は対象とする。
- ローカル確定後の通信失敗では導出名を保持する。通信成功を意味する状態にはしない。
- 追加・置換・復元で共通の採用規則と状態遷移を使う。タイトル目的で transcript 自体の本文を改変しない。
- `InputHistoryPolicy.entries(from:)` は、元本文の採用条件を満たす対象に対して再利用できる。
- `.derived`／`.manual` では、タイトル目的の履歴抽出・全件走査・導出関数の呼び出しより前に終了する。状態遷移関数が最後に無変更を返すだけでは不合格。
- `await` 後は現在の状態を再評価する。待機中の手動 rename を古い抽出結果で上書きしない。

### descriptor の後方互換

両 initializer に既定値 nil の任意引数を追加する。

```swift
titleSource: SessionTitleSource?
flowerName: String?
fullDerivedTitle: String?
```

読み取り窓口 `titleState: SessionTitleState` と、一体更新 `updating(titleState:)` を追加する。

- 両 initializer、decode、`updating(titleState:)` は公開状態 API と同じ正規化を通す。descriptor の名前四フィールドと `titleState` が食い違わない。
- `titleSource` 不在／null は legacy 扱い。保存 name をそのまま手動名として保持し、花名・導出全文は nil。孤立したメタ情報から由来を推測しない。
- 未知の `titleSource` 文字列では descriptor 全体を破棄しない。保存 name を手動扱いで保持し、正規化できる花名は保持、導出全文は解除する。既存診断経路へ記録する。
- 既知 source の不整合も上記 initializer の規則で手動へ退避し、decode 時は診断を記録する。状態型自体にログ・I/O を持ち込まない。
- CodingKeys、decode、encode、workspace 再構築で名前四フィールドを扱う。
- 旧データを読んだだけで一括移行保存しない。旧名の由来を花名一覧・番号接尾辞から推定しない。
- `updating(name:)` は手動変更。名前だけ変えて source を derived のまま残さない。
- 他の `updating` は名前四フィールドを保持する。
- 既存 name フィールドを維持し、CLI・既存クライアントとの互換を保つ。空の手動名を保存時に短縮 ID へ置換しない。
- token 非 encode、秘密 env 除去、ID、backend、resume、親子関係、role、launchContext、native session ID 等の既存契約を維持する。

### 保存・復元・rename

名前四フィールドは `name`、`titleSource`、`flowerName`、`fullDerivedTitle` を指す。

- UI／CLI の既存 rename は `DashboardViewModel.renameSession` から手動状態の一体更新へ到達する。Control API の認可・HTTP 仕様は変えない。
- 四フィールドを一つの descriptor 更新として保存する。フィールド別の非同期保存に分割しない。
- 保存順は既存 `SessionPersistenceCoordinator.enqueue` を使う。独自キュー・タイマー・debounce を追加しない。
- 初回 descriptor 保存前の変更も最新状態で初回保存に含める。未登録 ID の名前更新を捨て、古い花名を後から保存しない。
- 導出後の手動 rename は、保留書き込みの完了後も manual が勝つ。
- 削除後の名前更新・初回保存・復元 PID 更新で descriptor を再作成しない。既存の生存確認を維持する。
- 通常復元、PTY／チャットの復元失敗プレースホルダとも名前状態を保持する。
- workspace 移動・他フィールド更新で名前メタ情報を落とさない。
- 名前保存の失敗は既存エラー記録へ伝える。名前を含む初回保存の失敗も黙殺しない。
- 花名の重複回避は既存名に加えて保持中の flowerName も参照する。`FlowerNameGenerator` の抽選規則は変更しない。

#### 復元完了時の PID 書き戻し

復元開始時の descriptor に PID を足した古い全体スナップショットで、最新の保存値を置換してはならない。

PID 更新も同じ保存キューへ入れ、その処理時点の現存 descriptor に PID の変更だけを反映する。既に削除された ID は更新せず、再作成しない。名前更新との前後関係にかかわらず、最新の名前四フィールドと他の更新済みメタ情報を保持する。

受け入れ検査で次の順序を固定する。

1. A、B を復元開始する。
2. A の復元を完了し、B は制御可能な待機点で停止する。A の PID 更新は復元完了待ち。
3. A を導出名へ変更し、`waitForPendingWrites()` で保存を完了する。
4. A を `通知を修正` へ手動 rename し、再度保存完了まで待つ。
5. B を解放し、全体復元完了と PID 書き戻しを実行する。
6. `waitForPendingWrites()` 後、A は新 PID と `("通知を修正", .manual, "Rose", nil)` を保持する。

同じ検査を「手動 rename なし」「空欄 rename」「手順4後に A を削除」の独立ケースでも行う。削除ケースでは A が存在しないことを確認する。PTY／チャットそれぞれの PID 登録経路を対象とする。

### PTY 方針

PTY では自動導出しない。新規は花名、明示的 rename 後は手動名とする。

`sendText`、直接入力 `sendInput`、端末出力、エコー、端末タイトル、蓄積バイト列から命名しない。送信内容、bracketed paste、待機時間、submit 判定、フック、端末所有権・載せ替えを維持する。

## 成功基準

### 1. AgentDomain の Swift Testing

PM は実 API に対して次を固定する。期待値を被検査関数から生成しない。

- 公開 initializer の全リテラル例、正規化の冪等性、generated／legacy の境界。
- `/review` では flower 維持、その後の `ログイン画面を修正\n詳細` で derived、花名保持。
- 二度目の適格本文、再配送、derived／manual への入力で不変。
- 通常手動名、花名と同じ手動名、空手動名を保護。
- 空名の fallback `abc123`、長い手動名、内部改行・空白の保持。
- 両 descriptor initializer と JSON 往復で同じ正規化結果。
- 旧 JSON の `Rose`、通常名、空名、不在／null source、未知 source、不整合 derived／flower。
- `updating(titleState:)`、`updating(name:)`、既存の他フィールド更新と workspace 再構築。
- token 非出力、秘密 env 除去、backend・native session ID の互換。

### 2. SessionFeature／DashboardFeature の Swift Testing

実 claude／codex／cursor は起動しない。既存 `StructuredAgentClient` のテスト用実装、`InMemorySessionStore`、制御可能な非同期応答を使う。追加のテスト用クライアント・ストアは PM が凍結テスト内に用意する。

| 検査 | 固定結果 |
|---|---|
| 未確定入力・送信前拒否・添付のみ | flower を維持 |
| ローカル確定 | `pendingInput + text` の元本文から導出 |
| ローカル確定後の通信失敗 | 導出名を保持 |
| follow-up | メイン transcript の元本文だけを使用 |
| 対象外項目 | assistant・tool・error・質問回答・別 transcript から導出しない |
| 追加・置換・復元 | 採用可能な最初の本文から到達 |
| 復元待機中の rename | await 後も手動名を保持 |
| 状態復元 | flower／derived／manual／空名を保持 |
| 初回保存前の導出・rename | 最新四フィールドを保存 |
| 導出→manual の保存順 | 最終保存は manual |
| 復元完了 PID 更新 | 前節の順序で最新名、新 PID、他メタ情報を保持 |
| 削除競合 | 名前更新・初回保存・PID 更新で再作成しない |
| workspace 移動 | 名前状態を保持 |
| 保存失敗 | 初回保存を含め既存エラー記録へ到達 |
| 復元失敗 | PTY／チャット両プレースホルダが状態を保持 |
| PTY | sendText／直接入力とも導出しない |
| 花名重複 | 改名済みセッションの flowerName も除外集合に入る |

本文由来について、次を独立ケースで固定する。

- ローカル `/review` の送信文字列に `\nログイン画面を修正` という補足を付け、サーバー開始・完了イベントで返しても flower `Rose` のまま。
- ローカル本文と対応付くサーバー反映はローカル元本文を使う。補足の採用で先に確定しない。
- ローカル履歴なしのサーバー復元で、同じ補足付き文字列の元本文を識別できなければ flower `Rose` のまま。
- 元本文が独立して識別できるサーバー履歴の `ログイン画面を修正` は採用できる。
- 識別不能項目の後に識別可能な `通知を修正` があれば、後者を採用する。
- 元本文 `/review` と補足を識別できる場合も、補足だけを候補にしない。
- 確定後の履歴再読込・置換・巻き戻しは名前を変更しない。

sleep の長さに依存せず、応答の解放と `waitForPendingWrites()` で順序を固定する。既存の空名 rename テストを維持する。

### 3. Ruby 検査の分離と凍結

`.claude/scripts/task44-wiring.rb` は、task-41 方式で次の二層を分離する。

#### 恒久回帰検査：通常実行で必須

- 両 VM、ControllableSession、SessionNode の状態・有効名の接続。
- 新規生成、通常復元、両復元失敗経路の状態受け渡し。
- ローカル本文・サーバー反映・履歴復元ごとの採否と実経路の到達性。
- UI／CLI rename、四フィールド一体保存、初回保存の最新状態取得。
- descriptor の両 initializer、CodingKeys、decode、encode、workspace 転記。
- PID 更新が既存 descriptor を更新し、古い全体スナップショットによる名前上書き・削除済み ID の upsert をしないこと。
- **derived／manual のガードがタイトル目的の履歴抽出・全件走査より前にあり、各到達経路を支配すること。** 無条件抽出後に状態だけ戻す実装は拒否する。
- task-44 の `allowed_paths` 内にある `TranscriptTypography` への参照、および既存の typography 委譲経路を維持する。凍結時に呼び出し元・対象シンボル・引数・適用位置を記録し、定数直書き、別フォントによる上書き、コメント化、未使用化を拒否する。直接参照がないファイルにダミー参照を追加しない。
- 名前目的の AI 呼び出し・プロセス起動を追加しない。
- 送信・認可・PTY・秘密情報保護の指定された契約を維持する。

恒久検査では後続タスクの正当な変更まで禁止する全ファイル不変比較を行わない。保護する経路・式・操作順序を限定し、指定した領域を凍結 blob と照合する。

#### 着手時の変更範囲検査：`TASK44_SCOPE_CHECK=1` のときのみ

- task-44 の製品差分が `allowed_paths` 内に収まる。
- 許可ファイルでも明示した名前関連差分以外を凍結 blob と比較する。変更関数全体を除外しない。
- task-41 の製品ソースと、名前関連変更を許可していない送信・認可・PTY 等のソースを凍結 blob と比較する。
- PM 管理の契約・台帳等は、製品差分と区別した明示的な管理対象として扱う。ディレクトリ全体を比較除外しない。

この層は task-44 自身の実装確認までに適用する。task-45 以後の回帰では付与しない。scope を外しても恒久検査・凍結検査は必ず実行する。

#### 共通の凍結条件

- `TASK44_BASELINE` は `baseline_commit` と一致する完全コミット SHA 必須。HEAD、ブランチ名、参照名、未設定時フォールバックは禁止。
- 比較元は `git show <凍結SHA>:<path>` の blob。
- 受け入れテストと Ruby 自身が基準に存在し、現在内容と一致する。
- 基準に成立済み task-41 があり、`SessionTitleState.swift` と task-44 の配線が存在しないことを確認する。
- 実装入り HEAD の SHA を渡す自己比較を拒否する。実装前に指定 SHA と HEAD が一致することだけは拒否理由にしない。
- 対象不在、blob 欠落、解析不能は非ゼロ終了。コメント、文字列、未使用ヘルパー、`if false` による偽装を拒否する。

#### `--selftest` と変異

実ファイルを変更せず、同じ検査器へ正例と単一違反の負例を渡す。負例ごとに期待するエラー集合を固定し、別の失敗で偶然落ちただけでは合格にしない。

必須負例：

- initializer の不整合 derived／flower の正規化欠落。
- 生成花名の通常 name 代入、復元失敗・workspace 転記のフィールド欠落。
- サーバーの補足付き本文を無条件採用。
- rename の手動化欠落、保存接続欠落、初回保存で古い状態を使用。
- PID 更新で古い descriptor 全体を保存、削除済み ID を復活。
- **確定状態の早期ガードだけを削除し、履歴抽出を実行する変異。名前結果は不変でも必ず失敗する。**
- 各 protected typography 参照の削除・定数化・未使用化。
- PTY・認可・秘密情報除去の改変、偽装コード。
- SHA 未設定・不正・契約不一致、blob 欠落、実装入り基準、テスト／Ruby 改変。
- scope のみで拒否すべき範囲外変更が、scope なしでは範囲違反にならず、恒久契約の破壊は scope なしでも失敗すること。

実装後の変異検査でも、早期ガード単独削除を独立ケースとして実施する。Swift のコンパイル失敗や名前の変化ではなく、履歴抽出への到達を検出した Ruby エラーで落ちることを記録する。

### 4. 先行契約との整合

task-40 の Ruby にある全ファイル不変・残余比較は、**task-40 完了時点の着手時検査**であり、本タスクへ適用しない。PM は task-40 契約への同旨の注記を管理する。本タスクから task-40 の旧全体比較を再実行する条件を置かない。

その代わり、本タスクが変更できるファイル内の `TranscriptTypography` 参照維持を task44-wiring.rb の恒久検査で保護する。先行テストを削除したり、基準 SHA を実装後へすり替えたりして解決しない。

task-39 の `UNCHANGED_PATHS` には `SessionViewModel.swift`、task-45 が変更する `PaneLayoutView.swift` が含まれる。PM は task-44 凍結前に、名前関連差分を許しつつ端末所有権・載せ替え・入出力を保護する検査へ正式改訂する。旧 blob との関係、検査自身の凍結、正例・負例、独立レビュー、実行手順を記録する。未解決なら凍結しない。Cursor に検査変更を要求しない。

task-41 の回帰は `TASK41_SCOPE_CHECK` を外して実行する。

### 5. 検証コマンド

`<凍結SHA>` 等は PM が実値へ置換する。新規 API 不在によるコンパイル RED は、その事実を明記し、実装後にアサーションと変異の検出力を確認する。

```sh
~/.agents/scripts/compact-test task44-models bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
~/.agents/scripts/compact-test task44-wiring-selftest ruby .claude/scripts/task44-wiring.rb --selftest
~/.agents/scripts/compact-test task44-wiring-scope env TASK44_BASELINE=<task-44凍結SHA> TASK44_SCOPE_CHECK=1 ruby .claude/scripts/task44-wiring.rb
~/.agents/scripts/compact-test task44-wiring-regression env -u TASK44_SCOPE_CHECK TASK44_BASELINE=<task-44凍結SHA> ruby .claude/scripts/task44-wiring.rb
~/.agents/scripts/compact-test task44-task41-regression env -u TASK41_SCOPE_CHECK TASK41_BASELINE=<task-41凍結SHA> ruby .claude/scripts/task41-wiring.rb
~/.agents/scripts/compact-test task44-integration bash .claude/verify.sh
~/.agents/scripts/compact-test task44-appbootstrap bash macos/scripts/run-swift-tests.sh AppBootstrap
```

改訂した task-39 検査は PM が凍結した手順で別途実行する。確認した `.claude/verify.sh` の対象は8パッケージ、更新隔離検査、`git diff --check`。AppBootstrap は含まれないため別実行する。

App ビルドは `macos` を作業ディレクトリとする。

```sh
~/.agents/scripts/compact-test task44-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用の絶対パス> -destination platform=macOS build
```

PM は凍結前に品質設定を列挙し、対象の lint・型チェック・静的解析・ビルド・テスト設定を確認する。専用ゲートを正本として実行し、未設定・対象外・未実行を区別する。ビルドをテストや GUI 確認と読み替えない。

### 6. PM の課金なし目視ゲート

task-44 は既存の表示名と rename を確認する。task-45 の補助花名レイアウト完成は要求しない。

- チャット面の正本は `docs/agent-output/visual-task-27-35-composer.md`。PATH 不在 binaryName の custom `ui-chat-probe`、descriptor は `kind: {type: custom, id: ui-chat-probe}`、`backend: appServer`、pid キーなし。`customBinaryNotFound` による復元失敗プレースホルダを使う。
- PTY 面は `/tmp/phlox-t13-visual.SPfR9c/agents-t30.json` の custom `ui01-probe` を使う。`binaryName: cat`、`baseArgs: []`。隔離 fixture の descriptor は `backend: pty`、`kind: {type: custom, id: ui01-probe}`、`command: /bin/cat`、`args: []`、`env: {}`、pid キーなし、workingDirectory は今回専用の絶対パス。課金 CLI の保存済み command を持ち込まない。
- 不在 binary を PTY の安全保証として使わない。PTY は描画・サイズ変更で遅延起動し得るため、起動後とサイズ変更後の子孫プロセスを確認する。
- 今回の Debug バイナリ、専用 `PHLOX_DATA_DIR`、`PHLOX_DEFAULTS_SUITE`、`PHLOX_AGENTS_JSON`、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を使う。通常保存先と既存インスタンスを変更・停止しない。
- 旧名、derived、manual、空名を fixture に用意し、既存の名前位置で表示、手動 rename、空欄 rename、保存待ち、再起動後の保持を確認する。
- 明色 `phlox-light` と暗色 `dracula`、通常／選択／注意状態、深い階層、実幅240ptのグリッドペインで、名前・操作領域の重なりや欠けを確認する。主名は実際の背景とのコントラスト4.5:1以上。補助花名の同条件は task-45 で確認する。
- チャット専用起動では子プロセス0件を確認する。PTY 起動では `/bin/cat` と実際の起動経路を記録し、claude／codex／cursor 等の課金プロセスがないことを子孫一覧で確認する。混在起動を子プロセス0件とは報告しない。
- PID、実行ファイル、ウィンドウ所有 PID、fixture 条件、テーマ、寸法、画像、保存・再起動結果を PM 専有の `docs/agent-output/visual-task-44.md` に記録する。
- 終了時は起動元と親子関係を確認し、今回起動した不要なアプリ・cat・ハーネスだけを停止、`ps` で残存確認する。

チャットプレースホルダは transcript 本文を表示しない。この目視を自動導出、正常 AI 応答、実 CLI 送信の証拠にしない。自動導出と非同期順序は Swift Testing が担う。ハーネス不在や画面未到達は未検証として記録し、課金セッションで代替しない。

Cursor は `docs/agent-output/task-44.md` に責務ごとの実装状況、実行結果、未検証事項を記録する。

## レビュー観点

- 公開 initializer から不整合状態を流出させず、旧名・手動名・空名を保護しているか。
- 元本文の由来を経路別に判定し、補足付きサーバー本文を混入させていないか。
- 確定状態ではタイトル目的の履歴抽出へ到達しないか。
- 初回保存、復元待ち、PID 書き戻し、削除の競合で最新四フィールドを維持するか。
- descriptor 互換、workspace 転記、秘密情報保護、PTY・認可を維持するか。
- scope 検査と恒久検査を分離し、後続タスクを旧全体比較で妨げていないか。
- task-45 に必要な読み取り API が成立し、表示責務を先取りしていないか。
- テスト、Ruby、ビルド、隔離目視の証拠を区別し、課金を要求していないか。

## 受け入れ検査の敵対レビュー反映（2026-09-13、`docs/agent-output/task44-acceptance-adversarial.md` を PM 裁定）

- M1（サーバー履歴テストがローカル TranscriptStore で由来情報を持たない）: 採択。ローカル履歴とサーバー履歴を分離し、後者は実 `threadRead` 経路へ注入。由来情報の有無だけを変えた同一本文で採否を固定。本文の見た目で推測させない。
- M2（task-39 rb の全体比較との衝突）: PM 裁定で解消。task-39 の `task39-wiring.rb`（`SessionViewModel.swift`・`PaneLayoutView.swift` の全体比較）は task-40 と同じく **task-39 の着手時検査**であり、task-39 done 以降の後続タスクには適用しない（tasks/task-39.md に注記）。統合 verify.sh は rb を実行しない。よって task-44 の凍結条件は満たす。
- M3（verify 入口未登録）: 採択。PM が実装ディスパッチ前に `ui-ux-verify-task.sh` に task-44 分岐を登録する。
- H1（別種イベント）: 採択。ユーザー項目は `.itemStarted/.itemCompleted` → `chatItem` → `appendOrReplace` の実経路で反映し、処理完了を待ってから名前を検査。質問回答も独立ケース。
- H2（置換・巻き戻し・復元競合）: 採択。VM の実際の置換・再読込・巻き戻し経路を呼ぶ。競合は適格本文を返す履歴取得を停止→rename→解放で derived/manual を固定。
- H3（初回保存前の変更・削除）: 採択。`livePIDProvider` 等の待機点で spawn を止め、未保存区間の導出・rename・削除を PTY/チャット別に検査。
- H4（PID ゲートの取りこぼし）: 採択。A の復元完了と B の待機到達を明示的に待ち、解放済み状態を記録、期限付き。B 待機中の role 更新と最終 descriptor の保持検査。
- H5（復元中削除と ADR 0024）: PM 裁定。**復元中の明示削除は復元終了後へ繰り越して反映する**（既存の件数減少抑止は維持。`SessionPersistenceCoordinator` は allowed_paths 内）。テストは要求時点・保存時点・PID 更新の順序を固定し、最終ストアから消えることを期待。契約本文にこの要件を追加。
- H6〜H10・D1〜D3（rb と被覆）: 採択。実経路と支配ガードの限定検査（同等の正しいガードは許容）、入口→状態設定→四フィールド→保存キューの接続検査、基準差分からの製品変更ファイル列挙、認可・送信・PTY・秘密情報の恒久検査、`logError` 受信観測、花名は rename 前の値と比較し重複検査は全予約で決定的に、typography 検査は凍結 blob 比較、33 文字以上の derived・source 不在 JSON・descriptor 実フィールド・既存更新後の保持、両プレースホルダへ 4 状態を descriptor 経由、送信前拒否と通信失敗の分離。
- D4（完全 SHA）: 却下・契約修正。本 run の他タスクと同じく `TASK44_BASELINE` は短い SHA を許し、契約 `baseline_commit` と解決後の一致を検査する（frontmatter 記述を短 SHA に統一）。

## 契約の曖昧点の確定（2026-09-13、レビュー r2 後の PM 裁定）

- 由来情報の保持方法: `static` な共有状態、SessionID を含まない辞書、保存 transcript 本文へのマーカー埋め込み（205 行違反）はいずれも不可。ライブ経路の対応付け（ローカル送信 ↔ サーバー item）は VM インスタンス内の状態だけで行い、terminate で解放する。`ChatItem`・`TranscriptStore`・descriptor のスキーマは変更しない（allowed_paths 外）。
- 復元・履歴再開（由来不明の項目）の採否: **保存 transcript／ローカル履歴**から取り込んだユーザー項目で `originalText` 等の元本文情報が無いものは、**本文の先頭行だけを元本文候補**とし、先頭行がスラッシュコマンド（`/` 始まり）なら「補足付き入力」として不採用（花名を維持）。先頭行が適格なら採用する（`ローカル履歴の識別可能本文は採用しサーバー履歴とは分離する` と `ローカル_review_のサーバー補足受信後に保存transcriptから復元してもflowerのまま` の両立条件）。`isMeta` が判る項目は不採用。
- 履歴再開で取り込んだ項目は上記規則で評価し、無印のまま「元本文」として後続の保存・復元で採用してはならない（採用規則は復元・履歴・追加で共通）。
- 訂正（レビュー r3 後）: サーバー履歴（threadRead 等）は 197 行どおり `originalText` 等で元本文を識別できる項目だけを採用し、由来不明項目は先頭行候補にも**しない**（`ローカル履歴なしのthreadReadで由来の無い同一本文はflowerのまま` が正）。上記の先頭行規則は保存 transcript とローカル履歴に限る。r3 の MEDIUM は本契約文の誤りであり実装欠陥ではない。
- 訂正（レビュー r3 後）: サーバー item の `isMeta`（`ThreadItem.raw`）が真なら `originalText` があっても不採用。履歴再開で loader が `isMeta` 項目を `userMessage` に変換して transcript に取り込むと再復元時に先頭行候補になるため、loader 側で `isMeta` のユーザー項目を transcript へ変換しない（task-51 の `titleUserMessages` の除外と同じ判定）。このため `allowed_paths` に `macos/Packages/DashboardFeature/Sources/DashboardFeature/Spawn/ClaudeSessionHistory.swift` を追加する（変更はこの除外のみ。`titleUserMessages`／`titleSummary`／preview／firstUserLine は不変）。
- 再訂正（3 回目差し戻し中の ESCALATION、PM 裁定）: loader（`ClaudeSessionHistory.swift`）で `isMeta` 項目を transcript から除外すると task-51 の凍結テスト `AcceptanceHistoryTitleSourcesTests`（transcript 変換の件数）が RED になる＝task-51 の確定済み契約と衝突する。よって (b) は**撤回**し loader は変更しない（`allowed_paths` の `ClaudeSessionHistory.swift` は不使用）。(a)（サーバー item の `raw.isMeta` が真なら不採用）のみ実装する。残る既知の限界: Claude 履歴から再開したセッションで、再開時点に実ユーザー本文が無く meta 項目だけが transcript に転写された場合、後日の復元で先頭行規則が meta 本文を採用しうる（再開時の導出は `titleUserMessages` が meta を除外するため正しい）。フェーズ 5 で後続項目として記録する。
