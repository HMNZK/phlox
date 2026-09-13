---
id: task-45
difficulty: standard
depends_on: [task-44]
user_visible: true
acceptance_tests:
  - macos/Packages/AgentDomain/Tests/AgentDomainTests/Acceptance/AcceptanceSessionTitlePresentationTests.swift
  - .claude/scripts/task45-wiring.rb
baseline_commit: "e3dd2fb45aeec5d305995826885e15663a9dd6be"
contract_tests: []
allowed_paths:
  - macos/Packages/AgentDomain/Sources/AgentDomain/SessionTitlePresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/PaneLayoutView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardTopBarControls.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/TeamTimelineView.swift
  - macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/AgentChatRowPolicy.swift
  - docs/agent-output/task-45.md
---

## 目的

UX-01 の表示を完成させる。作業名を主、元の花名を補助として既存の名前位置に表示し、狭い領域での省略と help・アクセシビリティからの全文確認を両立する。

仕様の正本は `macos/docs/specs/ui-ux-improvement-backlog.md:78`。名前状態・保存・自動導出は成立済み task-44／task-41 を読み取る。UX-01 全体の成立には3タスクの成立が必要となる。

本契約は `docs/agent-output/task44-45-contract-adversarial.md` と 2026-09-13 の PM 裁定を統合する。既存調査 HEAD は `cb17de2193f80010a5126e19b2265b018452a2d7`。既存行番号は当時の参照として再利用し、追加の表示経路は改訂時 HEAD `412cb9efaa0a40531d002fe0d4f32d914e08e8cb` で確認した。実装時はシンボルから辿る。

本改訂では製品変更・テスト・ビルド・GUI確認を実施していない。read-only のため連結出力先への保存は未実施。

## 入出力契約

### 担当・依存・境界

- Cursor は `allowed_paths` 内の製品と開示レポートだけを実装する。PM が Swift Testing と Ruby 検査を作成・RED 確認・凍結し、別モデルがレビューする。
- task-44 成立後に凍結する。基準には task-41・task-44 の成立済み製品、本タスクの受け入れテストと Ruby を含め、task-45 の製品実装を含めない。
- task-41 の幅正規化修正・再検証の成立を task-44 経由で確認する。
- 新規依存・パッケージ・App ターゲットのテストを追加しない。
- 名前状態、VM、protocol、保存スキーマ、rename、導出、PTY 方針は変更しない。
- 旧契約で許可していた `SessionView.swift` と `ChatSessionView.swift` は変更対象から外す。新しい単体ヘッダーを作らない。
- 追加したトップバーとチーム表示のファイル内でも、変更は名前表示と必要な読み取り受け渡しに限定する。本文レンダリング・討論・送信・活動判定を変更しない。
- task-41・task-44 と製品の変更許可パスを交差させない。

### 表示位置と到達経路

名前表示の対象は次の4箇所。単体トップバーは PTY／チャット双方で確認するため、目視の到達ケースは5つになる。

| 表示位置 | 起点・変更 |
|---|---|
| サイドバー行 | `DashboardSidebarView.swift:437` の `SessionSidebarRowView`、名前 Text は `:462`。既存名領域を主名・補助花名へ置換 |
| グリッドタイルヘッダー | `SessionGridView` → `PaneLayoutView` → `PaneTileView.header`、`PaneLayoutView.swift:324`、名前 Text は `:330` |
| 単体のトップバー選択名領域 | `DashboardView.swift:275` の `DashboardLeadingTopBarControls`、実装ファイルは `DashboardTopBarControls.swift`。選択セッションを router／viewModel から解決し、ADR 0042 の既存トップバー内へ配置 |
| チームカードの既存名前領域 | `TeamTimelineView` → `TeamTimelineSourceChip` の `source.displayName`（改訂時 `:523`）、`AgoraTimelineRow.speakerHeader` の `item.sessionDisplayName`（`:582`）、`AgentChatRowPolicy.swift` の `AgoraThinkingIndicatorRow` の既存セッション名（`:91`） |

改訂時の `DashboardLeadingTopBarControls` には選択名の Text が存在しない。既存 Text の置換と偽らず、**既存トップバー内の集約位置へ名前内容を配置する**変更とする。トップバーそのものや独立したヘッダー行は新設しない。

単体の到達は `DashboardDetailView.singleDetail` の PTY／appServer 分岐。単体本文の `SessionView`／`ChatSessionView.mainColumn(width:)` にタイトルを追加しない。グリッドのチャット本文は `PaneLayoutView.swift:257` の `GridChatColumn` であり、そこにも追加しない。

チームの source chip、発言カード、Thinking 行は既存の名前領域だけを更新する。チーム役割、入力先表示、討論参加者チップの仕様、エージェント表示名を作業名へ置換しない。新しいチームヘッダー・カードを作らない。

### ADR 0042／0073 との整合

- ADR 0042 の「選択セッション名を設定ギア等と同じトップバー行へ集約」を維持する。
- 単体チャット／PTY の本文側に独立した名前ヘッダーを追加しない。「カラム内ヘッダー行は置かない」という現行コメントを反転させない。
- ADR 0073 の実測高から本文余白を決める一方向依存、既存 `TopBarInsetPolicy`、メイン／サブペインの共有ヘッダー高さを維持する。
- 補助花名のためにヘッダーを2段化したり、固定余白を増量したりしない。既存の行内で主名を優先し、必要に応じて省略する。
- トップバーの操作ボタン・使用量表示を名前が押し出さない。既存バーの高さを増やさず、利用可能幅内へ収める。
- 本タスクで ADR 本文を変更する必要はない。新設ヘッダーを前提とした旧契約の条項は撤回する。

### 読み取り契約

task-44 が供給する API：

```swift
SessionTitleState.name: String
SessionTitleState.source: SessionTitleSource
SessionTitleState.flowerName: String?
SessionTitleState.fullDerivedTitle: String?
SessionTitleState.effectiveName(fallback: String) -> String
```

両 VM・ControllableSession・SessionNode から `titleState` を読み取れる。

- flower は非空の花名と一致する name を持つ。
- derived は32 Character以内の name と、非 nil の正規化済み候補行全文を持つ。
- manual は手動名または保護された旧名。空名は短縮 ID へフォールバックする。
- 公開 initializer の不整合入力、未知 source、旧データは task-44 で正規化済み。
- 表示側で source を推測し直したり、不整合を補修したり、導出を再実行しない。

チーム表示は ID から現在の SessionNode を解決し、その titleState・workspacePath を読む。タイムラインの過去の `displayName` だけを使って最新名を失わない。表示モデルを引数または読み取りクロージャで既存子 View に渡し、名前状態をタイムライン保存モデルへ複製しない。

対応する現在セッションがない履歴カードでは、既存の保存済み表示名を `.legacy(name:)` として表示できる。花名・導出全文・作業場所を推測しない。workspace が取得できなければ空文字を渡す。削除済みセッションを表示目的で復活させない。

### 新規表示モデル

`AgentDomain/SessionTitlePresentation.swift` に置く。

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
| secondary | 非 nil の flowerName が primary と異なる場合だけその花名 |
| fullTitle | derived は保存された fullDerivedTitle、それ以外は primary |
| helpText | fullTitle、花名があれば `花名: <flowerName>`、`作業場所: <workspacePath>` を改行連結 |
| accessibilityValue | fullTitle そのもの |

fallback は既存 `SessionViewModel.shortID(for:)`。derived の全文が非 nil であることは task-44 の不変条件に依存する。表示側で task-41 を呼び直さない。

花名と primary が同じなら補助表示は出さないが、help の花名行は保持する。花名を持たない旧データは花名行を省略する。空手動名は主名・全文とも短縮 ID、花名があれば補助として表示する。

全文は derived の候補行全文、manual の有効な手動名全文を指す。元依頼全文・transcript 全文を help へ出さない。

### 描画・全文確認

対象の既存名前領域は同じ表示モデルを使う。

- 主名を先、補助花名を後に配置する。補助には既存の小さい文字を使う。
- 主名は `.lineLimit(1)`、`.truncationMode(.tail)`。保存値や表示モデルで手動名を切らない。
- 補助花名も1行、省略可。主名を押し出さず、操作ボタンの幅も確保する。
- 主名・補助花名とも、通常／選択／注意状態の実背景に対して4.5:1以上の文字コントラストを満たす。
- `textSecondary`／`textTertiary` というトークン名だけで合格にしない。既存トークンの実色を確認し、不足する組合せでは既存の十分なコントラストを持つ文字色を選ぶ。補助性は文字サイズ・配置でも表現する。新しいテーマ設定や依存を作らない。
- 名前領域の `.help` に `helpText` を渡す。行全体の workspace help、チームカードの「シングルビューで開く」が名前の全文 help を覆わないようにする。操作自体は維持する。
- 名前領域をアクセシビリティ要素にし、value に `accessibilityValue` を渡す。
- サイドバー行の `emphasis.accessibilityValue` は維持し、全文 value は子の名前領域へ付ける。
- 既存の選択・状態の読み上げと省略前タイトルが共存する。装飾花名を重複読み上げさせない。
- 状態表示、アイコン、開始日時、workspace、選択・展開・ドラッグ・閉じる・rename・カードから単体への移動を維持する。
- `PaneTileView.header` の `.draggable` と後続 `.simultaneousGesture` の順序を維持する。
- `body`、表示開始、hover、AX 取得から導出・状態更新・保存を実行しない。
- 本文レンダリング、入力先、チーム役割、討論、端末所有権・載せ替えを変更しない。
- rename 後は既存4箇所の対応セッション名が更新される。タイムラインの過去スナップショットで古い名へ戻らない。

## 成功基準

### 1. 表示モデルの Swift Testing

PM は task-44 の公開 API から状態を作り、以下のリテラル期待値を凍結する。fallback は `abc123`、workspacePath は `/tmp/project`。

| 状態 | primary／secondary／fullTitle |
|---|---|
| generated `Rose` | `Rose`／nil／`Rose` |
| `ログイン画面を修正` を導出、元花名 `Rose` | `ログイン画面を修正`／`Rose`／`ログイン画面を修正` |
| manual `通知を修正`、元花名 `Rose` | `通知を修正`／`Rose`／`通知を修正` |
| manual `Rose`、元花名 `Rose` | `Rose`／nil／`Rose` |
| 空 manual、元花名 `Rose` | `abc123`／`Rose`／`abc123` |
| legacy `Rose` | `Rose`／nil／`Rose` |
| legacy 空名 | `abc123`／nil／`abc123` |
| manual `ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567` | 同じ33文字／元花名に従う／同じ33文字 |
| 上記33文字の derived、元花名 `Rose` | `ABCDEFGHIJKLMNOPQRSTUVWXYZ12345…`／`Rose`／`ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567` |
| derived 全文 nil の不整合入力を task-44 initializer で構築、name=`修正`、花名=`Rose` | `修正`／`Rose`／`修正` |
| flower 不一致入力 name=`Lily`、花名=`Rose` | `Lily`／`Rose`／`Lily` |
| 花名が空白だけの manual `修正` | `修正`／nil／`修正` |

追加の固定期待値：

- 花名ありの help：`ログイン画面を修正\n花名: Rose\n作業場所: /tmp/project`
- 花名なしの legacy `Rose`：`Rose\n作業場所: /tmp/project`
- 空 workspace：末尾行は `作業場所: `。パスを推測しない。
- 花名と primary が同じ場合も help の花名行を保持。
- accessibilityValue は fullTitle と一致。
- 日本語、長い英数字、複合絵文字、内部改行・空白を含む手動名を保持。
- モデルを繰り返し構築しても同じ結果で、入力状態を変更しない。

表示モデルの振る舞いを SwiftUI ソースの文字列一致だけで代替しない。

### 2. Ruby 検査の分離と凍結

PM が `.claude/scripts/task45-wiring.rb` を作成する。

#### 恒久回帰検査：通常実行で必須

- サイドバー、グリッド、トップバー、チームの到達可能な既存名前領域が実 titleState から表示モデルを使う。
- トップバーは PTY／チャットの選択ノードに対応し、選択変更・rename に追随する。
- チームの source chip、発言カード、Thinking 行それぞれで現在ノードの表示モデルに接続し、既存履歴名への退避はノード不在時だけ。
- primary／secondary、1行・末尾省略、全文 help、名前 AX value が接続される。
- 花名表示条件を View で再実装しない。
- サイドバーの選択用 AX value と各面の状態表示を維持する。
- 単体 `SessionView`／`ChatSessionView` やグリッド本文に新しいヘッダーを追加していない。
- トップバー内で既存操作を保ち、独立行・2段タイトル・固定余白増量を追加していない。
- workspace、開始日時、状態、閉じる、ドラッグと選択の順序、チームカードの移動操作を維持する。
- View／表示モデルから導出・rename・保存を呼ばない。
- task-45 の `allowed_paths` 内の `TranscriptTypography` 参照と既存 typography 委譲経路を維持する。凍結時の呼び出し元・対象・引数・適用位置を照合し、定数化、上書き、未使用化を拒否する。直接参照がないファイルにダミー参照は要求しない。

保護する式・操作順序を凍結 blob と比較する。後続の正当な変更を禁止する全ファイル比較を恒久条件にしない。名前領域や header 関数全体を無条件で除外しない。

#### 着手時の変更範囲検査：`TASK45_SCOPE_CHECK=1` のときのみ

- 製品差分が `allowed_paths` 内に収まる。
- 許可ファイル内でも名前領域と必要な読み取り・レイアウト差分以外は凍結 blob と一致する。
- task-41・task-44 の製品ソースが本タスクの凍結 blob から不変。
- `SessionView.swift`、`ChatSessionView.swift`、余白・共有ヘッダー高さのポリシー等を変更していない。
- 契約・台帳等の PM 管理対象は製品と区別し、広域除外しない。

task-45 自身の実装確認に適用し、後続タスクの回帰では付与しない。scope を外しても恒久検査・凍結検査は実行する。

#### 共通の凍結条件

- `TASK45_BASELINE` は `baseline_commit` と一致する完全コミット SHA 必須。
- HEAD・参照名・ブランチ名・未設定時フォールバックは禁止。
- 比較元は `git show <凍結SHA>:<path>` の blob。
- 受け入れテストと Ruby 自身が基準に存在し、現在内容と一致する。
- 基準には成立済み task-44 があり、`SessionTitlePresentation.swift` と task-45 の表示配線が存在しない。
- 実装入り HEAD の SHA による自己比較を拒否する。実装前の SHA と HEAD が一致することだけは拒否しない。
- 対象不在・解析不能・blob 欠落は非ゼロ終了。コメント、文字列、未使用ヘルパー、`if false` による偽装を拒否する。

#### `--selftest` と変異

実ファイルを変更せず、同じ検査器で正例・単一違反負例を評価する。期待エラー集合を厳密に比較する。

必須負例：

- サイドバー、グリッド、トップバー、チームをそれぞれ単独で未接続にする。
- チームの source chip／発言カード／Thinking 行を個別に未接続にする。
- チームで現在ノードを無視し、古い名前だけを表示する。
- fullTitle の代わりに primary を help／AX へ渡す。
- 1行・末尾省略・secondary 条件の欠落。
- サイドバー行の選択 AX value を名前で上書きする。
- 単体本文・グリッド本文への新規ヘッダー追加、トップバータイトルの2段化。
- ドラッグと選択の順序、状態、閉じる、端末接続、チーム移動操作を改変する。
- View から保存・導出を呼ぶ。
- protected typography 参照の削除・定数化・未使用化。
- コメント・文字列・未使用コードによる偽装。
- SHA 未設定・不正・契約不一致・blob 欠落・実装入り基準・テスト／Ruby 改変。
- scope 専用の範囲違反と、scope なしでも失敗すべき恒久違反の分離。

実装後は単独変異でも検出力を確認する。画面のコントラスト・切れ・重なりは Ruby 合格だけで確認済みとしない。

### 3. 先行契約と検証コマンド

task-40 の全ファイル不変・残余比較は task-40 完了時点の着手時検査であり、本タスクに適用しない。PM の task-40 契約注記と整合させる。本タスクが変更できるファイル内の typography 参照維持は task45-wiring.rb が恒久保護する。

task-39 の `PaneLayoutView.swift` 全体不変との衝突は、task-44 凍結前の PM 改訂で解消する。名前領域変更を許し、端末所有権・載せ替え・入出力を維持することを本タスクの凍結前にも確認する。未解決なら凍結しない。`SessionView.swift` は本改訂で変更対象から外れている。

task-41 と task-44 の回帰では、それぞれの scope 環境変数を外す。task-44 の**確定状態で履歴抽出へ到達しない恒久検査**は引き続き実行する。

```sh
~/.agents/scripts/compact-test task45-models bash macos/scripts/run-swift-tests.sh AgentDomain
~/.agents/scripts/compact-test task45-wiring-selftest ruby .claude/scripts/task45-wiring.rb --selftest
~/.agents/scripts/compact-test task45-wiring-scope env TASK45_BASELINE=<task-45凍結SHA> TASK45_SCOPE_CHECK=1 ruby .claude/scripts/task45-wiring.rb
~/.agents/scripts/compact-test task45-wiring-regression env -u TASK45_SCOPE_CHECK TASK45_BASELINE=<task-45凍結SHA> ruby .claude/scripts/task45-wiring.rb
~/.agents/scripts/compact-test task45-task41-regression env -u TASK41_SCOPE_CHECK TASK41_BASELINE=<task-41凍結SHA> ruby .claude/scripts/task41-wiring.rb
~/.agents/scripts/compact-test task45-task44-regression env -u TASK44_SCOPE_CHECK TASK44_BASELINE=<task-44凍結SHA> ruby .claude/scripts/task44-wiring.rb
~/.agents/scripts/compact-test task45-integration bash .claude/verify.sh
```

改訂した task-39 検査も PM の凍結手順で実行する。App ビルドは `macos` を作業ディレクトリとする。

```sh
~/.agents/scripts/compact-test task45-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用の絶対パス> -destination platform=macOS build
```

プレースホルダは PM が実値へ置換する。PM は凍結前に品質設定を確認し、適用可能な既存ゲートを実行する。lint・型チェック・静的解析・ビルド・テスト・GUI確認を区別し、未設定・対象外・未実行を記録する。

### 4. PM の課金なし目視ゲート

実 claude／codex／cursor セッションを要求しない。チャットは復元失敗プレースホルダ、PTY は既存 custom cat ハーネスを使う。

#### fixture と隔離

1. 今回の Debug バイナリ、専用データディレクトリ、defaults suite、エージェント定義を用意する。通常の Release／Debug 保存先を使用しない。
2. チャットは `docs/agent-output/visual-task-27-35-composer.md` を正本とする。custom `ui-chat-probe`、PATH 不在 binaryName、`backend: appServer`、pid キーなしで `customBinaryNotFound` プレースホルダへ入る。
3. PTY は `/tmp/phlox-t13-visual.SPfR9c/agents-t30.json` の `ui01-probe` を使う。`binaryName: cat`、`baseArgs: []`。descriptor は `backend: pty`、`kind: {type: custom, id: ui01-probe}`、`command: /bin/cat`、`args: []`、`env: {}`、pid キーなし、workingDirectory は今回専用の絶対パスに固定する。
4. 既存 descriptor の課金 command・引数・env を PTY fixture へ持ち込まない。不在 binary だけで PTY の起動抑止を保証したことにしない。
5. アプリ停止中に、同一プロジェクトへ `ログイン画面を修正`、`通知の重複を修正`、長い日本語、長い英数字、空名、同じ花名へ手動変更した名を用意する。旧データは新規メタ情報なし、他は task-44 の不変条件に一致する四フィールドを設定する。
6. チームの source chip とカード名へ到達する fixture を用意する。発言カード・Thinking 行の表示にデータが必要なら、隔離したローカル表示用 fixture を使い、AI セッションや討論を開始しない。注入した表示データを実応答の証拠としない。
7. `PHLOX_DATA_DIR`、`PHLOX_DEFAULTS_SUITE`、`PHLOX_AGENTS_JSON`、`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` で起動する。既存インスタンスを止める `debug-build-restart.sh` は使わない。

#### 必須の表示条件

| 軸 | 必須条件 |
|---|---|
| 表示位置 | サイドバー、グリッド、単体 PTY のトップバー、単体チャットのトップバー、チームの既存名前領域 |
| テーマ | 明色 `phlox-light`、暗色 `dracula` |
| 状態 | 通常、選択、注意。各状態が実際にある面で再現し、非該当は理由を記録 |
| 幅 | 通常幅、ウィンドウ1024pt、実測240ptのグリッドペイン |
| 階層 | サイドバーはルートと少なくとも3段の親子関係。字下げ・時刻・状態を表示した状態 |
| 名前 | 短名、長い日本語、長い英数字、空名、主名と異なる補助花名 |
| コントラスト | 主名・補助花名それぞれ、通常／選択／注意の実背景に対して4.5:1以上 |

240pt はウィンドウ幅ではなくペインの実幅を記録する。深い階層も名前領域の実幅を記録する。

#### 独立した合否条件

- 主名を優先して省略し、補助花名・時刻・状態・アイコンが主名や操作を押し出さない。
- 主名は末尾省略。全文が保存値から失われていない。
- 名前と本文、トップバー、サブペイン、使用量表示に重なりがない。
- 単体本文に新規ヘッダーがなく、グリッドにも二重ヘッダーがない。
- 主名・補助花名の文字色と実際に合成された背景色からコントラスト比を記録する。トークン名や目視印象だけで4.5:1達成としない。
- 閉じる、選択、展開、ドラッグ、rename、チームカードから単体への移動が欠けず到達できる。
- 各名前領域の hover で省略前タイトル、元花名、workspace を確認できる。
- AX value に全文があり、サイドバーの選択・既存状態の読み上げも維持される。
- UI で通常 rename、花名と同じ文字列への rename、空欄 rename を行い、各表示位置へ反映される。
- 保存完了後に同じ隔離環境を再起動し、主名・補助花名・短縮 ID を保持する。

表示位置、明暗、幅、状態の必要条件が未観測なら、その範囲は未検証であり、目視ゲートを通過扱いにしない。課金セッションで埋めない。

#### プロセスと証拠

- 起動 PID、実行ファイル、ウィンドウ所有 PID を照合する。
- チャット専用起動では子プロセス0件を確認する。
- PTY では起動後と描画・サイズ変更後の子孫プロセスを記録し、cat の実コマンドと起動経路を確認する。混在起動を子プロセス0件とは記録しない。
- claude／codex／cursor 等の課金プロセスが起動していないことを確認する。
- PM 専有の `docs/agent-output/visual-task-45.md` にコミット、fixture 条件、PID、テーマ、状態、実寸、画像、コントラスト比、help／AX、操作、再起動結果を記録する。
- 通常保存先が変更されていないことを確認する。
- 終了時に起動元と親子関係を確認し、今回起動した不要なアプリ・cat・ハーネスだけを停止する。`ps` で残存を確認し、共有プロセスを停止しない。

チャットプレースホルダは transcript 本文を表示しない。表示用 fixture、cat の出力、復元失敗画面を、正常 AI 応答・自動導出・実 CLI 送信の検証として報告しない。

Cursor は `docs/agent-output/task-45.md` に表示モデル、4箇所の接続、省略、help、AX、操作維持の実装状況と検証結果を記録する。PM 目視レポートは Cursor の変更許可パスに含めない。

## レビュー観点

- 作業名が主として識別でき、補助花名が主名や操作を押し出していないか。
- 既存4箇所へ接続し、単体の両 backend とチームの各名前領域を確認したか。
- 新規ヘッダーを作らず、ADR 0042／0073 の集約位置・高さ・余白を維持しているか。
- derived 候補行と手動名の全文が help／AX から確認できるか。
- 明暗・選択／注意・深い階層・240ptで、両文字の4.5:1と操作領域を確認したか。
- rename 後のチーム表示が古い履歴名へ戻らないか。
- 表示側が名前状態・導出・保存を変更していないか。
- scope と恒久回帰を分離し、先行の履歴抽出ガードと typography の保護を維持しているか。
- Swift Testing、Ruby、ビルド、課金なし目視を別々の証拠として報告しているか。

## 受け入れ検査の敵対レビュー反映（2026-09-13、指摘原文 `docs/agent-output/task45-acceptance-adversarial.md`）

- MUST1（scope 検査が契約準拠の `.tail` 変更を拒否）: 採択。名前 Text と修飾子・読み取り経路を構文単位で扱い、実物の未配線コードに契約準拠の変更を加えた scope 正例を追加する。
- HIGH2（名前・花名・help・AX の実接続）: 採択。表示モデル → 各 Text → 名前領域の修飾子を追跡し、接続を 1 つずつ切る負例を追加する。
- HIGH3（現在ノード → チーム子 View・トップバー）: 採択。chip・発言カード・Thinking 行ごとに 対象 ID → 現在ノード → 表示モデル → 子引数を検査。別 ID・legacy 無視・未使用 helper を単独負例に。
- HIGH4（既存操作・状態・余白の恒久保護）: 採択。契約が保護する操作・状態・余白の式を凍結 blob と照合する（同等の正しい表現は許容。閉じる操作はコメント除去後に判定）。
- HIGH5（typography の引数・適用位置・委譲経路）: 採択。呼び出し元・対象・引数・適用位置・委譲先を比較し単独改変を負例に。
- HIGH6（表示モデルの純粋性・View からの状態更新）: 採択。表示モデルの許可依存（Foundation・AgentDomain の型のみ）と副作用禁止、描画経路からの `name` 代入・`receivingUserMessage` 等の状態変更呼び出しを拒否する。
- HIGH7（比較元 blob 欠落の省略）: 採択。新設の表示モデル以外は blob 取得成功を必須にし、欠落は非ゼロ終了。
- HIGH8（33 文字ケースの helpText）: 採択。全文・花名・workspace を連結したリテラル期待値を追加。
- MEDIUM9（被覆・自己定数比較）: 採択。前後空白付き／空白のみの旧名、花名なし derived、異なる fallback・花名・非空 workspace を追加し、自己定数アサーションは別引数の出力検査へ置換。
- MEDIUM10（selftest の自己比較・部分確認）: 採択。実物由来の変更前後、負例の全エラー集合比較、本番 marker は行全体で本番呼び出しを検査。
- MEDIUM11（ADR 0073 の middle truncation）: PM 裁定。契約の末尾省略（`.tail`）は維持。ADR 0073 には本 run のフェーズ5で「セッション名の省略は末尾（UX-01c）」の後継決定を注記する（高さ・余白の決定は維持）。契約本文の変更なし。
- 「タブ」経路 unverified: 契約の対象箇所（サイドバー・グリッド見出し・チーム・トップバー）に「タブ」は無い。対象外として据え置き。
