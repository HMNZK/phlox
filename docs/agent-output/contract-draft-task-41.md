---
id: task-41
difficulty: deep
depends_on: []
user_visible: true
acceptance_tests:
  - macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleDeriverTests.swift
  - macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitleStateTests.swift
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceSessionTitleLifecycleTests.swift
  - macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/Acceptance/AcceptanceSessionTitlePersistenceTests.swift
  - .claude/scripts/task41-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleDeriver.swift
  - macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitleState.swift
  - macos/Packages/AgentDomain/Sources/AgentDomain/PersistedSessionDescriptor.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ControllableSession.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionViewModel.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/SessionViewModel.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/SessionView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatSessionView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionSpawnService.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionRestoreCoordinator.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SessionPersistenceCoordinator.swift
  - docs/agent-output/task-41.md
---

## 目的

UX-01 / P1「セッション名を作業内容で見分けられるようにする」。同じプロジェクトのセッションを一覧から区別できるよう、作業名を主、生成時の花名を補助として表示する。長い名前は省略し、全文を確認できるようにする。

仕様の正本は `macos/docs/specs/ui-ux-improvement-backlog.md:78`。名前の優先順位は **手動名 > 最初の適格なユーザー依頼から導出したタイトル > 花名**。命名専用の AI 呼び出し、外部通信、CLI セッションの起動は追加しない。

保存予定先は `docs/agent-output/contract-draft-task-41.md`。本草案は read-only 調査の成果であり、ファイルには保存していない。調査対象 HEAD は `bb8006cefd64d9dac21c1c19eaf148145b2db5e5`。製品変更、テスト作成・実行、ビルド、GUI 検証は未実施。

## 入出力契約

### 実コードで確認した起点

以下の行番号は調査時点のもの。新設する型・メンバーは後段で「新規契約」として定義する。

| 関心事 | 確認した実装 |
|---|---|
| 花名生成 | 定義は DashboardFeature ではなく `macos/Packages/AgentDomain/Sources/AgentDomain/FlowerNameGenerator.swift` の `FlowerNameGenerator`。DashboardFeature の `DashboardViewModel.swift:1020` が `random(avoiding:)` を呼ぶ |
| 名前の共通窓口 | `ControllableSession.swift:20` の `name`、同`:21` の `displayName`。`SessionNode` もこれらを中継する |
| 現在の表示名 | `ChatSessionViewModel.swift:578`、`SessionViewModel.swift:75`。現在は `name` をトリムし、空なら短縮 ID |
| サイドバー | `DashboardSidebarView.swift` の実際の型名は **`SessionSidebarRowView`**。名前の `Text` は`:456`。指定された `SidebarSessionRow` という型名ではない |
| グリッド | `SessionGridView` → `PaneLayoutView` → `PaneTileView.header`。名前の `Text` は `PaneLayoutView.swift:330` |
| 単体表示 | `DashboardDetailView.singleDetail` → PTY は `SessionView`、チャットは `ChatSessionView`。現在の `SessionView` 上部はアイコンと開始日時。`ChatSessionView.mainColumn(width:)` は承認表示から始まり、調査対象の両 View にセッション名の `Text` はない |
| UI リネーム | `DashboardView.swift:166` → `DashboardViewModel.renameSession(_:to:)`（`:827`）→ `SessionPersistenceCoordinator.persistSessionName(id:name:)` |
| CLI リネーム | 実ファイルは `macos/scripts/phlox`。`cmd_rename`（`:331`）が `PATCH /sessions/<id>` を送り、`AppBootstrap/ControlActionHandler.handleRename` が認可後に同じ `renameSession` を呼ぶ |
| チャット入力 | `ChatSessionViewModel.sendText(_:submit:)`（`:2792`）。`pendingInput + text` をユーザー本文として保存し、内部の再送用補足文を加えた `clientInput` と区別している |
| transcript | `ChatSessionViewModel.appendOrReplace`（`:2366`）、`applyRestoredTranscript`（`:2402`）。`InputHistoryPolicy.entries(from:)` は既に `.userMessage` だけを入力順で抽出する |
| PTY 入力 | `TerminalCoordinator.send(source:data:)` はバイト列を通知。`SessionViewModel.sendInput(_:)`（`:452`）は入力を PTY へ渡し、`onInputSubmitted` に本文は渡さない。`sendText(_:submit:)`（`:796`）では引数の文字列を取得できる |
| 永続化 | `PersistedSessionDescriptor.name`。`SessionPersistenceCoordinator.persistSessionWorkspace` は descriptor を全フィールド転記で再構築する |
| 復元失敗 | `SessionSpawnService.makeRestoreErrorChatSession` は切断状態のクライアントで VM を作り、`startNew`・`restore` を呼ばない |

### 実装・凍結の担当

- PM が本契約の期待値から Swift Testing と Ruby 配線検査を作成し、実装前に凍結する。Cursor は製品実装のみ担当し、テスト・配線検査・契約・検証ゲートを変更しない。
- レビューは Cursor の実装に使ったモデルとは別モデルが行う。
- 本件の難しさは文字列短縮ではなく、名前の由来、旧データ、復元、非同期保存の整合にある。
- `baseline_commit` と `TASK41_BASELINE` は、受け入れテストと Ruby 検査を含み、task-41 の製品実装を含まないコミットへ固定する。
- 新規パッケージ・依存は追加しない。既存の AgentDomain、SessionFeature、DashboardFeature のテストターゲットを使う。App ターゲットにテストを置かない。

### 新規契約：タイトル導出

`AgentDomain/SessionTitleDeriver.swift` に次の公開面を新設する。

```swift
public struct DerivedSessionTitle: Equatable, Sendable {
    public let title: String
    public let fullTitle: String
}

public enum SessionTitleDeriver {
    public static func derive(from text: String) -> DerivedSessionTitle?
}
```

入力は一つのユーザーメッセージ本文。出力は省略済みタイトルと、省略前の候補行。`fullTitle` は依頼全文や transcript 全文ではない。

導出規則を次の順序に固定する。

1. CRLF・CR を LF として扱い、元の行順で走査する。
2. コードフェンスの開始・終了行と、その内部を除外する。フェンスはバッククォートまたはチルダが3個以上。閉じていない場合は末尾まで除外する。
3. 元の行がタブまたは半角空白4個以上で始まる場合は、貼り付けコードとして除外する。
4. 行の前後の空白を除き、全角・半角の幅の違いを Foundation の幅変換で揃える。大文字・小文字は変えず、ユーザーのロケールに依存させない。
5. 行内の連続する空白・タブ・全角空白を半角空白1個にする。
6. 空行と次の定型行を除外する。除外後は次の行へ進む。
   - `/` で始まるスキル／コマンド行。引数付きも行全体を除外する。
   - コード候補の接頭辞：`import `、`from `、`func `、`def `、`class `、`struct `、`enum `、`let `、`var `、`const `、`function `、`return `、`#include `、`#!/`、`$ `。
   - `{`、`}`、`[`、`]` で始まる行。
7. 最初に残った行を `fullTitle` とする。一つも残らなければ `nil`。
8. Swift の `Character` 単位で32文字以内なら `title == fullTitle`。33文字以上なら先頭31文字と `…` を結合する。絵文字・結合文字を途中で切らない。

コード判定はこの固定規則による限定的な判定であり、任意のプログラミング言語を識別するものではない。製品コメントに `ponytail:` としてこの限界を記し、拡張は実例とテストが必要になった時点で行う。

関数は Foundation と標準ライブラリだけに依存する。ファイル、時計、設定、乱数、ネットワーク、プロセス、View に依存しない。元の送信本文・添付・transcript を書き換えない。

### 新規契約：優先順位と表示モデル

`AgentDomain/SessionTitleState.swift` に名前の状態と表示結果を置く。以下の型・メンバー名は新規契約である。

```swift
public enum SessionTitleSource: String, Codable, Sendable {
    case flower
    case derived
    case manual
}

public struct SessionTitlePresentation: Equatable, Sendable {
    public let primary: String
    public let secondary: String?
    public let fullTitle: String
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
    public func presentation(fallback: String) -> SessionTitlePresentation
}
```

状態遷移と出力は次に固定する。

| 入力・状態 | 結果 |
|---|---|
| 新規生成 | `.flower`。`name` と `flowerName` は生成した花名、`fullDerivedTitle == nil` |
| `.flower` で適格なユーザー本文 | `.derived`。`name` は導出済みの短いタイトル、花名は維持、省略前の候補行を保存 |
| `.flower` で導出不可 | 無変更。次のユーザーメッセージを候補にできる |
| `.derived` で追加の本文・同じイベントの再配送 | 無変更 |
| `.manual` で任意の本文 | 無変更 |
| 明示的なリネーム | `.manual`。前後の空白・改行を除いた名前を保存し、元の花名を維持。導出全文は解除 |
| 手動名が花名と同じ | `.manual` のまま。文字列一致で `.flower` に戻さない |
| 空欄への明示的リネーム | `.manual`、`name == ""`。主表示は短縮 ID。後続入力で自動命名しない |
| `.derived` の表示 | 主表示は `name`、全文は `fullDerivedTitle` |
| `.manual` の表示 | 主表示・全文は手動名。名前自体を32文字に切らない |
| `.flower` の表示 | 主表示・全文は花名。補助に同じ花名を重複表示しない |

補助表示は、保存された花名が存在し、主表示と異なる場合だけ出す。空欄へのリネームでも主表示は短縮 ID、花名が残っていれば補助表示に使う。花名も名前もない場合の短縮 ID は、既存の `SessionViewModel.shortID(for:)` を呼び出し側から `fallback` として渡す。

空欄を短縮 ID に戻す挙動は、既存の `renameSession_emptyNamePersistsAndRestoresShortID` が保証している。これを自動命名への復帰操作に変更しない。既存リネーム画面の説明とも整合させる。

### 名前の由来と旧データ

`PersistedSessionDescriptor` に、既定値 `nil` の次の任意フィールドを追加する。

- `titleSource: SessionTitleSource?`
- `flowerName: String?`
- `fullDerivedTitle: String?`

既存の `name` は、CLI・既存クライアントが読む有効な名前として維持する。新規フィールドは両 initializer、CodingKeys、decode、encode、および descriptor の再構築経路で扱う。

旧データには手動名と花名を区別する情報がない。したがって次を守る。

- `titleSource` がない既存 descriptor は `legacy(name:)` として復元し、**名前が `Rose` でも手動扱いで保護**する。
- 花名一覧との一致や接尾番号から、旧名を自動生成名だと推定しない。
- 旧データに元の花名がなければ補助表示を出さない。ランダムな花名を後付けしない。
- 未知の `titleSource` は既存の名前を手動扱いで保持する。未知値だけを理由にセッション全体を破棄しない。
- `.derived` として復元するには、省略前タイトルと `name` の整合が必要。不整合なら保存済み `name` を手動扱いで保護し、不整合を既存の診断経路へ記録する。
- 旧データの読み込みだけで一括移行保存を行わない。

この方針では、旧来の花名セッションも自動で改名されない。手動名を上書きしないための意図した互換動作である。

### チャットへの接続

- 両 VM の `name`／`displayName` は同じ純粋モデルに従う。View 内で名前の由来や優先順位を判定しない。
- 公開 `name` への通常の代入は手動名として扱う。新規生成・復元では専用の状態設定を行い、花名を `name` に代入した結果として手動扱いにしない。
- `SessionNode` の表示も同じ結果を中継する。既存の `ControllableSession` 実装・テスト用実装を不要に破壊しない。
- 対象は当該セッションのメイン transcript に保存された `.userMessage`。アシスタント回答、ツール結果、エラー、質問回答カード、別のサブエージェント transcript から導出しない。
- 新規送信では `sendText` が保存するユーザー本文を使う。`clientInput` の補足文、スキルファイル本文、画像パス・ファイル名を候補にしない。
- `submit == false`、入力途中、送信前検証で拒否された入力では命名しない。
- ローカル transcript にユーザーメッセージを確定した後、通信が失敗した場合は導出名を保持する。「送信成功」という意味にはしない。
- transcript の追加・置換・復元経路で、最初の適格なユーザーメッセージに到達する。復元時の抽出には既存の `InputHistoryPolicy.entries(from:)` を再利用できる。
- `.derived`／`.manual` 確定後はタイトルのために transcript 全件を繰り返し走査しない。
- 復元やイベント処理が `await` をまたぐ場合、適用時点の状態を再評価する。処理開始時の古い状態で、その間に行われた手動リネームを上書きしない。
- 会話の巻き戻し・履歴再読み込みで、確定済みタイトルを自動的に変更しない。

### PTY の扱い

今回は **PTY では自動導出しない**。新規は花名、明示的リネーム後は手動名を使用する。

`sendText` の引数は取得できるが、直接タイピングは編集・制御キーを含む断片であり、共通の「最初に確定した依頼文」として扱えない。片方の入力経路だけで自動命名する実装も行わない。

画面出力、エコー、端末タイトル、バイト列の蓄積から依頼文を推測しない。PTY の入出力、送信待機時間、bracketed paste、submit 判定、フック処理は変更しない。

### 保存・復元・リネーム

- UI と `macos/scripts/phlox rename` は、既存の `DashboardViewModel.renameSession` を通じて手動状態へ遷移する。Control API の認可と HTTP 仕様を維持する。
- 名前と由来・花名・導出全文を、一つの descriptor 更新として保存する。別々の非同期書き込みに分けない。
- 保存は既存 `SessionPersistenceCoordinator.enqueue` の直列経路を使う。独自キュー・タイマー・debounce を追加しない。
- 自動名確定直後の手動リネームでは、保存完了後も手動名が勝つ。
- 初回 descriptor 保存前に名前が変わった場合も、初回保存で最新状態が残る。存在しない descriptor への更新を捨てたまま古い花名を保存しない。
- 削除後に届いた保存処理がセッションを再作成しない。
- 通常復元と PTY／チャット両方の復元失敗プレースホルダへ、名前の状態を渡す。
- workspace 移動時の descriptor 全フィールド転記で新規メタ情報を落とさない。その他の `updating` によるコピーでも維持する。
- 保存失敗は既存のエラー記録経路へ伝える。表示更新を永続化成功と報告しない。
- `token` を encode しない規則、秘密情報を `env` から除く規則、既存 ID・backend・resume 情報を維持する。
- 新規花名の重複回避には、保持された `flowerName` と既存名を使う。作業名に変わった結果、同じ花名を直ちに再利用しない。`FlowerNameGenerator` 自体の抽選規則は変えない。

### 表示・全文確認

対象は次の4か所とする。

1. `SessionSidebarRowView` の名前領域。
2. `PaneTileView.header` の名前領域。
3. 単体 PTY の `SessionView` 上部。
4. 単体チャットの `ChatSessionView.mainColumn(width:)` 上部。

単体表示の2か所は、既存の名前表示があるという前提で作業しない。そこへ同じモデル結果による名前領域を追加する。

- 作業名を先、花名を後に配置し、花名は既存の副次文字色・小さい文字で示す。
- 主表示は `.lineLimit(1)` と `.truncationMode(.tail)`。幅に応じた省略で、保存した手動名を切り詰めない。
- 花名は主表示を押し出さない。補助表示も1行、省略可とする。
- 名前領域の `.help` で、省略前タイトル、元の花名、workspace パスを確認できるようにする。花名がなければその行を省く。
- 名前の AX ラベルにも省略前タイトルを渡す。サイドバーの選択状態を伝える既存 AX value を上書きしない。
- `.derived` の「全文確認」は省略前の候補行、`.manual` は手動名全文を意味する。元の依頼全文や transcript 全文は tooltip に出さない。
- 既存の状態表示、エージェントアイコン、選択・展開・ドラッグ・リネーム操作を維持する。
- View の `body`、表示開始、hover から導出・保存を実行しない。
- グリッド内で単体用タイトルを重複描画しない。`GridChatColumn` と単体 `ChatSessionView` の経路を区別する。
- 入力先表示、チームの役割表示、本文レンダリングの変更は UX-03／UX-05 等の別関心事であり、本件では扱わない。

## 成功基準

### 1. 純粋モデルの受け入れテスト

PM が前記の Swift Testing ファイルを作成する。期待値は次のリテラルから固定し、製品の戻り値から生成しない。

| 入力 | 期待する候補 |
|---|---|
| `ログイン画面を修正\n詳しい条件` | `ログイン画面を修正` |
| `\r\n  API\t の　接続を修正  \r\n次の行` | `API の 接続を修正` |
| `ＡＰＩ　１２３を修正` | `API 123を修正` |
| 空文字、空白のみ、改行のみ | `nil` |
| `/review` | `nil` |
| `／review 引数` | `nil` |
| `/review\nログイン画面を修正` | `ログイン画面を修正` |
| コードフェンスだけのメッセージ | `nil` |
| 閉じたコードフェンスの後に `ログインを修正` | `ログインを修正` |
| 閉じていないコードフェンス | フェンス開始後から候補を採らない |
| `    let value = 1\nログインを修正` | `ログインを修正` |
| `import Foundation\nログインを修正` | `ログインを修正` |
| `abcdefghijklmnopqrstuvwx12345678` | 32文字を維持 |
| `abcdefghijklmnopqrstuvwx123456789` | `abcdefghijklmnopqrstuvwx1234567…`。全文は入力の33文字 |
| 複合絵文字を含む32／33 Character の文字列 | 同じ境界規則。絵文字の途中を切らない |

状態モデルでは最低限、次を固定する。

- 花名のみ、導出成功、導出不可後の次の適格入力、二度目の依頼で不変。
- 手動名が導出に勝つ。花名と同じ手動名も勝つ。
- 空欄への手動リネームは短縮 ID、以後自動命名しない。
- 旧データの `Rose`、通常名、空名を手動扱いで保護する。
- 長い手動名を保存時に短縮しない。
- 補助花名の有無・重複抑止、導出全文と表示用タイトルの区別。
- 同じ入力で同じ結果、入力値が変わらないこと。
- descriptor の新旧 JSON、未知の由来、導出情報不整合、encode/decode 往復。
- 名前更新と他の `updating` で無関係なフィールドが維持されること。

### 2. 課金なしのライフサイクル・保存テスト

SessionFeature と DashboardFeature の Swift Testing で、既存のインメモリストア・制御可能なクライアントを用いる。実 claude／codex／cursor は起動しない。

- `submit == false` の断片は命名せず、確定したユーザー本文から導出する。
- 内部の再送用補足文はタイトルに混入しない。
- 添付だけ、送信前検証拒否、ツール出力だけでは命名しない。
- ローカル transcript 確定後の通信失敗では導出名を維持する。
- transcript 復元、項目置換、重複イベントで名前が揺れない。
- 復元の完了前に手動リネームした場合、古い導出候補が上書きしない。
- 新規 `.flower` 状態、導出名、手動名、空名が保存・復元後も同じ表示になる。
- 元の花名と導出全文が、workspace 移動後も残る。
- 初回保存と名前変更の順序、導出直後の手動変更、削除との前後関係を制御して検査する。
- 保存エラーを注入し、エラー記録を確認する。
- 復元失敗プレースホルダも同じ名前モデルを使う。
- PTY の `sendText` と直接入力では自動導出しない。

時間待ちの長さに依存させず、既存の `waitForPendingWrites()` や制御可能な非同期応答で順序を固定する。

### 3. 配線検査

PM が `.claude/scripts/task41-wiring.rb` を作成し、実装前に凍結する。Ruby は配線と不変条件の検査を担当し、タイトル導出・優先順位のテスト本体を代替しない。

検査対象：

- 両 VM と `SessionNode` が純粋モデルを参照している。
- 新規生成、通常復元、両復元失敗経路で名前の由来を渡している。
- 実際のユーザーメッセージ格納・復元経路から導出へ到達する。
- UI／API の既存 rename 経路が手動状態への更新と一体保存へ到達する。
- descriptor の initializer・CodingKeys・decode・encode・workspace 転記で新規フィールドが欠けていない。
- 対象4表示面の到達可能な描画経路がモデルを使い、1行省略・全文 help・AX ラベルを持つ。
- 名前以外の送信処理、認可、PTY 入出力、秘密情報除去を凍結 blob と比較して保護する。
- 純粋モデルにプロセス起動・ネットワーク・I/O がなく、命名経路に追加 AI 呼び出しがない。
- 許可した名前関連の変更だけを既存処理の比較対象から除外する。関数全体を無条件に比較除外しない。

検査はコメントを除去し、文字列と括弧対応を保持して宣言・呼び出しを確認する。コメント、未使用ヘルパー、ダミー文字列、`if false` に一致文字列を置いても合格にしない。対象不在・解析不能は非ゼロ終了とする。

固定基準：

- `TASK41_BASELINE` 必須。契約の `baseline_commit` と完全 SHA に解決して一致を確認する。
- `HEAD`、`HEAD~1`、`@`、ブランチ名、未設定時のフォールバックは禁止。
- `git show <凍結SHA>:<path>` の blob を基準にする。現在のソースから基準を作らない。
- 基準コミットに受け入れテストと rb 自身が存在し、現在の内容と一致することを確認する。
- 基準時点に task-41 の製品実装が入っていたら失敗にする。実装後 HEAD の SHA を指定する自己比較もこれで拒否する。
- 実装前の凍結直後は、指定 SHA が HEAD と同じでもよい。単なる SHA 同値禁止で実装前の検査を壊さない。

`--selftest` は実ファイルを変更せず、正例と次の負例を持つ。

- 一つの表示面だけモデル未接続、全文欠落、省略指定欠落。
- 生成時の花名を手動代入で初期化する誤配線。
- 復元失敗経路だけ新規フィールド欠落。
- workspace 更新でメタ情報を落とす変更。
- rename が自動状態を残す変更、保存接続の削除。
- PTY 入出力・認可・秘密情報除去の変更。
- コメント・文字列・未使用コードによる偽装。
- SHA 未設定、不正、契約不一致、blob 不在、実装入り基準、テスト／rb 改変。

### 4. 既存契約との整合と検証コマンド

現行 `task39-wiring.rb` の `UNCHANGED_PATHS` には、今回変更する `SessionView.swift`、`PaneLayoutView.swift`、`SessionViewModel.swift` が含まれる。**現行検査を無変更で通すことと本件の実装は両立しない。**

PM は task-41 の凍結前に、task-39 が守る端末の所有権・載せ替え・入出力の不変条件を維持しつつ、名前関連の変更だけを許す比較へ改訂する。その正例・負例と独立レビューを残す。基準 SHA のすり替え、検査削除、失敗無視で解決しない。Cursor の `allowed_paths` に既存検査は含めない。

実行はすべて `compact-test` を経由する。

```sh
~/.agents/scripts/compact-test task41-models bash macos/scripts/run-swift-tests.sh AgentDomain SessionFeature DashboardFeature
~/.agents/scripts/compact-test task41-wiring-selftest ruby .claude/scripts/task41-wiring.rb --selftest
~/.agents/scripts/compact-test task41-wiring env TASK41_BASELINE=<凍結SHA> ruby .claude/scripts/task41-wiring.rb
~/.agents/scripts/compact-test task41-integration bash .claude/verify.sh
~/.agents/scripts/compact-test task41-appbootstrap bash macos/scripts/run-swift-tests.sh AppBootstrap
```

`<凍結SHA>` は説明用プレースホルダ。PM が実値に置換してから実行する。改訂した task-39 検査も、その契約の固定 SHA で実行する。

確認した `.claude/verify.sh` は8パッケージ、更新隔離検査、`git diff --check` を実行する。AppBootstrap は含まれないため、rename の認可経路の回帰として別途指定する。

App ビルドは `macos` を作業ディレクトリとし、今回専用の出力先で実行する。

```sh
~/.agents/scripts/compact-test task41-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用の絶対パス> -destination platform=macOS build
```

lint・静的解析の専用設定は今回の探索範囲では発見していない。凍結時に PM が設定を再確認し、未設定・対象外・未実行を区別して記録する。パッケージテスト、App ビルド、GUI 確認を互いに読み替えない。

### 5. PM 目視ゲート

**sessions.json の復元失敗プレースホルダで、入力欄とチャット画面を課金なしに表示できることは PM 確認済み。** 本契約ではこの方法を使う。transcript 本文は表示されないため、自動導出の正しさは Swift Testing で検証する。

手順：

1. 今回の製品を Debug ビルドし、専用のデータディレクトリ、defaults suite、エージェント定義を用意する。既存の Release／通常 Debug の保存先は使わない。
2. PM 確認済みの復元失敗用データを隔離先へ複製する。実行ファイル不在などの復元失敗条件を保ち、実 AI クライアントへ接続しない。
3. アプリ停止中に隔離先の `sessions.json` の `name` を変更し、同一プロジェクトに「ログイン画面を修正」「通知の重複を修正」、長い日本語名、長い英数字名を用意する。旧データ確認用は新規メタ情報なしとする。
4. 補助花名の表示確認用には、新規契約に整合する `titleSource`・`flowerName`・`fullDerivedTitle` も設定する。導出名の fixture は32文字省略規則に合わせる。この注入は自動導出の実走証拠にはしない。
5. `PHLOX_DATA_DIR`、`PHLOX_DEFAULTS_SUITE`、`PHLOX_AGENTS_JSON`、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` を設定し、今回の実行ファイルを隔離起動する。既存 `debug-build-restart.sh` は既存インスタンスを停止するため使用しない。
6. 自 PID・実行ファイル・ウィンドウ所有 PID を照合する。サイドバー、グリッド、単体チャット、単体 PTY で主名と花名を確認する。通常幅とウィンドウ幅1024ptで、省略・重なり・操作到達性を撮影する。
7. 名前領域の hover と AX で省略前タイトルを確認する。既存の状態・選択の読み上げを損なっていないことも確認する。
8. プレースホルダを UI で手動リネームし、反映と保存を確認する。空欄では短縮 ID に戻る。同じ隔離環境を再起動し、名前と補助花名を再確認する。メッセージ送信は行わない。
9. `docs/agent-output/visual-task-41.md` にコミット、データ条件、PID、ウィンドウ寸法、画像、help／AX の観測結果を記録する。通常保存先への変更がないことを確認し、今回起動した不要なプロセスだけを終了する。

復元失敗画面の表示確認を、正常な AI 応答・transcript 表示・実 CLI 送信の確認として報告しない。CLI rename は配線とパッケージテストで確認し、目視ゲートのために認証済み課金セッションを作らない。

今回の調査では、この手順を再実行していない。

## レビュー観点（Rubric）

- **作業の識別**：同じプロジェクトの異なる依頼を開かずに区別できる。花名が主名と競合しない。
- **純粋性と境界**：導出規則・文字数境界・定型文除外を Swift Testing が直接検証し、View や rb に判定本体を隠していない。
- **手動名保護**：旧名、花名と同じ手動名、明示的な空名を自動処理が上書きしない。
- **保存の整合**：初回保存、導出後の手動変更、復元、削除、workspace 移動で名前と由来が食い違わない。
- **全文確認**：省略前タイトルに help と AX から到達でき、保存値を表示都合で破壊していない。
- **PTY の誠実な扱い**：取得できない依頼文を推定せず、既存入出力を維持する。
- **既存機能**：認可、秘密情報除去、通知・状態・選択・端末載せ替えを損なわない。
- **証拠**：凍結 blob 比較、`--selftest`、モデル・ライフサイクルテスト、App ビルド、PM 目視を区別して報告する。
- **費用**：製品にも PM ゲートにも、命名だけの追加 AI 呼び出し・実 CLI セッション起動を要求しない。

### 凍結前の分割案

本草案には、独立に失敗しうる「タイトル導出」「名前の由来と保存」「表示」が含まれる。**そのまま一つの実装契約として凍結するより、次の3契約へ分割することを推奨する。**

| 契約 | 責務 | 依存 |
|---|---|---|
| task-41 | `SessionTitleDeriver` の文字列契約と Swift Testing | なし |
| 後続タスクA・番号未設定 | 名前状態、チャット接続、手動名保護、保存・復元、PTY 方針 | task-41 |
| 後続タスクB・番号未設定 | 表示モデル、4表示面、省略・全文確認、PM 目視 | 後続タスクA |

分割採用時は PM が各契約の frontmatter、allowed_paths、受け入れテスト、依存関係を分けて再凍結する。UX-01 の完了は3契約の成立後とし、導出関数だけの完成で完了扱いにしない。