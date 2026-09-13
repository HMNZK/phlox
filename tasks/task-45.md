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
