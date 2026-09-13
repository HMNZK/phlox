---
id: task-46
difficulty: standard
depends_on: [task-40]
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptItemPresentationTests.swift
  - .claude/scripts/task46-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptItemPresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+CommandGroup.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+TaskList.swift
  - docs/agent-output/task-46.md
---

## 目的

UX-05 / P1「回答本文と処理の詳細に見た目の差を付ける」のうち、回答・処理詳細・状態・エラーの表示分類、見出し、開閉、状態配線を扱う。回答は最初から読め、詳細は必要時に開け、処理中とエラーは閉じた詳細の外から識別できるようにする。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:100`。文字・間隔は先行 task-40 の体系を使う。Markdown の補正・要約からの装飾除去・コード保護は後続 task-47 の責務とする。

本稿は read-only 調査による未凍結契約である。ファイル変更、テスト作成・実行、ビルド、GUI確認は行っていない。以下の新規モデル・試験ファイル名は提案であり、既存シンボルと区別する。

## 入出力契約

### 担当・依存・凍結

- 実装担当は Cursor。受け入れテストと Ruby 検査は PM が作成・凍結し、Cursor は作成・変更しない。レビューは実装担当と別モデルが行う。
- 受け入れテストは `SessionFeatureTests` 内の Swift Testing と専用 Ruby 検査に限定する。App ターゲットにはテストを置かない。
- 契約、テスト、Ruby 検査、検証スクリプト、台帳、目視ハーネス、目視記録は PM 所有であり、Cursor の `allowed_paths` に含めない。
- task-40 完了後に対象コードと品質設定を再確認する。調査した `tasks/task-40.md` の `baseline_commit` はプレースホルダであり、`TranscriptTypography` の完成・検証済み状態は今回未確認。
- 本タスクの `baseline_commit` は、task-40 完了状態と task-46 の凍結テスト・Ruby 検査を含み、task-46 の製品実装を含まないコミットへ固定する。
- PM は未実装による RED、Ruby の `--selftest` 成功、単一違反の検出を確認して凍結する。環境エラーを未実装の RED と数えない。
- task-40 等が保護する条件のうち、思考文・タスクの既定展開や本契約の見出し変更との衝突は、PM が凍結前に契約として解消する。Cursor に先行テストを弱めさせない。

### 確認した実装

以下の `SF/` は `macos/Packages/SessionFeature/Sources/SessionFeature/`。行番号は今回の読み取り時点であり、task-40 完了後の位置ではない。

| 実ファイル・シンボル | 確認した挙動 |
|---|---|
| `SF/ChatMessageCells+Basic.swift:184`、`AgentMessageBody` | 文章を `RichMarkdownView`、コードを `CodeBlockView` で描く。回答は折り畳まない |
| 同ファイル`:203`、`ErrorMessageCell` | `"Error"`、警告アイコン、`DSColor.statusError` のラベル色・背景・枠を使用 |
| `SF/ChatMessageCells+Structured.swift:192`、`ReasoningSummaryView` | `ReasoningPresentation.usesDisclosure` により短文を直接表示。展開本文は `Text(text)` |
| 同ファイル`:67`、`ThinkingIndicatorCell` | 活動ラベル、orb、AXラベルを表示し、`RunningTurnStatusView` へ経過・無応答・中断を委譲 |
| 同ファイル`:252`、`CommandExecutionCell` | 既定閉。見出しはコマンドまたは `"Command"`、補足は `"実行中"`／`"Output available"` |
| 同ファイル`:287`、`FileChangeCell` | `FileChangeDisplayPolicy.isExpanded` を通じてユーザー操作を優先し、未操作なら閉じる |
| `SF/ChatMessageCells+CommandGroup.swift:15`、`CommandGroupHeader` | 最新IDとターン状態から実行中・表示可否を導出 |
| 同ファイル`:159`、`CommandGroupCell` | 既定閉。現在のカードは `header.title` を使い、補足は `nil` |
| `SF/ChatMessageCells+TaskList.swift:10`、`TaskListCell` | `.constant(true)` により展開固定 |
| `SF/ChatMessageCellsCommon.swift`、`DisclosureCard`／`DisclosureCardStyle` | 既存の開閉ボタン、シェブロン、AX値「展開中／折りたたみ中」を提供 |

### 表示分類モデル

新規 `TranscriptItemPresentation.swift` に、表示分類を導出する `TranscriptItemPresentation` を置く。SwiftPM 内から直接検査できる、同期的な値型とする。

入力は次の値に限定する。

- 種類：回答、思考詳細、コマンド詳細、ファイル変更、タスク、処理中、エラー。
- 当該種類に必要な原文、要約、件数、実行中フラグ、出力の有無、既存ファイル変更タイトル、活動ラベル。
- 件数・活動状態・変更ファイル要約は呼び出し側の実データから渡す。モデル内で ViewModel、時計、設定、ファイル、ネットワーク、プロセスへアクセスしない。

出力は、表示可否、分類、見出し、補足、折り畳み可否、既定展開状態、意味色の役割とする。意味色は SwiftUI の `Color` ではなく「通常／処理／エラー」を表す値とし、View が既存のテーマ色へ接続する。

| 種類 | 分類・意味色 | 折り畳み／既定 | 見出し・補足 |
|---|---|---|---|
| 回答 | 回答・通常 | 不可／本文表示 | 追加の「回答」見出し・カードを作らない |
| 思考詳細 | 詳細・処理 | 可／閉 | 見出し「思考の詳細」、補足は呼び出し側から渡された要約 |
| コマンド単体・グループ | 詳細・処理 | 可／閉 | 「処理の詳細（N件）」、実行中なら「実行中」、完了後に表示対象の出力があれば「出力あり」、それ以外は補足なし |
| ファイル変更 | 詳細・処理 | 可／閉 | 既存の変更ファイル要約。追加・削除件数は既存の色分けを保持 |
| タスク | 詳細・処理 | 可／閉 | 「タスク（N件）」 |
| 処理中 | 状態・処理 | 不可／表示 | 既存の活動ラベル |
| エラー | エラー・エラー | 不可／表示 | 「エラー」。診断本文は原文 |

追加規則：

- 空白だけの思考文は非表示。短文・長文はともに既定閉とする。
- 本タスクの思考要約は、既存の `ReasoningPresentation` から供給する。モデルは渡された要約を保持し、Markdown を解析しない。装飾除去済みであることは task-46 の合格条件に含めない。
- コマンド単体の件数は1。グループの件数は入力されたコマンド項目数であり、50件の描画窓や空出力の除外後の表示行数ではない。コマンド文字列が `nil` でも件数を失わない。
- グループの表示可否・実行中判定は `CommandGroupHeader.shouldRender`／`isRunning` を正本とする。空出力の既存除外条件を変えず、過去グループへ実行中表示を広げない。
- 「出力あり」は既存の表示条件で到達できる出力を対象とする。出力文字列の `"error"` 等から失敗を推測しない。
- 空タスクは「タスク（0件）」を表示し、開いた本文に「タスクなし」を表示する。

### 開閉と実Viewへの配線

- 折り畳める詳細の展開状態は、非永続なユーザー操作を優先する。導出規則は `userOverride ?? defaultExpanded` とし、未操作時は閉じる。
- 回答・処理中・エラーは折り畳み対象にしない。詳細用の override によって非表示にしない。
- 同じ項目・グループIDの内容更新、同長別内容への置換、実行終了でユーザーの開閉操作をリセットしない。
- 思考文は短文分岐も含めて `DisclosureCard` を使う。展開本文には原文全体を渡し、要約だけで代用しない。本タスクでは既存の `Text` による本文描画を維持できる。
- コマンド単体・グループは分類モデルの見出し・補足を実カードへ渡す。閉じた状態でも件数と実行中状態が読めること。
- `CommandGroupHeader.title` と `CommandGroupTitle.derive` は変更せず、既存のコマンド要約を展開内容側へ残す。コマンド単体も見出しから外したコマンド原文を展開内容で読めるようにする。
- タスクの `.constant(true)` を操作可能な非永続状態へ置き換える。タスクのID・順序・状態・状態アイコン・AXラベルは保持する。
- ファイル変更の開閉は `FileChangeDisplayPolicy.isExpanded` を引き続き使う。`defaultExpanded(lineCount:)` は描画予算用であり、カードの既定展開判定へ流用しない。分類モデルとの一致をテストする。
- 通常／処理の意味色は、既存の `DisclosureCard` の `isToolCall` とテーマ色へ接続する。差分の追加削除色は保持する。
- エラーは「エラー」のラベル、警告アイコン、既存の `DSColor.statusError` のラベル色・背景・枠を使う。診断本文の記号・パス・コードは原文のまま表示する。
- 処理中の活動ラベルとAXラベルには同じ実状態を渡す。orb の状態、可視性制御、経過、無応答警告、中断操作を保持する。
- 質問・承認操作を詳細カードへ収納しない。サブエージェント行は既存の移動ボタン・移動先・失敗色を保持する。
- 共通カードの実装は再利用し、クリック範囲・シェブロン・キーボード開閉・既存AXを維持する。

### 不変条件と変更境界

- task-40 完了後の文字・余白・倍率・テーマ追随を保持する。調査時の古いフォント指定へ戻さない。
- メッセージ・グループのID、順序、表示範囲、描画予算、スクロール追従を変更しない。
- コマンドの50件単位の追加表示、出力の20行からの全文表示、差分の500行からの追加表示を保持する。
- コピー原文、差分の行番号・構文ハイライト・追加削除色、質問・承認・中断・移動コールバックを保持する。
- `ChatTranscriptFormatting.swift`、`RichMarkdownView.swift`、共通カード、キャッシュ、共有ドメイン、クライアント、保存・復元処理、パッケージ依存を変更しない。
- `AgentMessageBody` の Markdown／コード分割・描画経路は保持する。
- 描画中の観測状態更新、`LazyVStack`、非同期ハイライト、無制限キャッシュ、新規設定・製品用デモモードを追加しない。

task-47 との `allowed_paths` の交差は、`ChatMessageCells+Structured.swift` の1ファイルだけとする。思考文の開閉と本文描画が同じ `ReasoningSummaryView` に存在するため、この交差を依存関係で逐次化する。

task-47 に許す後続変更は、同Viewの「要約の供給式」と「展開本文の描画経路」だけである。task-46 の検査は、これらの具体的な描画方式を固定せず、原文の受け渡し、空判定、見出し、開閉、状態保持を固定する。ファイル全体やView全体を比較から除外してはならない。

## 成功基準

### 1. Swift Testingで表示分類・状態を検査する

PM は本契約の表をリテラル期待値として凍結する。期待値を製品モデルの出力や列挙から生成しない。

| 入力・操作 | 必須結果 |
|---|---|
| 通常回答・複数段落回答 | 回答分類、折り畳み不可、本文表示 |
| 1行・複数行・60文字超の思考文 | 詳細分類、見出し「思考の詳細」、既定閉 |
| 空・空白だけの思考文 | 非表示 |
| 要約だけ異なる同長入力 | 新しい要約が反映される |
| コマンド1件・2件・51件 | 対応する件数見出し。描画窓で件数を減らさない |
| コマンド文字列が `nil` | 件数を保持 |
| 最新グループ実行中／完了、過去グループ | 最新の対象だけ「実行中」。完了後は出力条件に応じ「出力あり」または補足なし |
| 空出力だけの完了グループ | 既存の `shouldRender` と表示行除外に一致 |
| 差分0・1・500・501行 | 未操作なら閉。既存の表示上限500を保持 |
| タスク0・1・複数件 | 件数一致、既定閉、開閉可能。0件の展開本文は「タスクなし」 |
| 処理中・エラー | 折り畳み不可。状態／エラー分類と所定のラベル |
| overrideが `nil`・`true`・`false` | 既定閉・開・閉 |
| 開いた後／閉じた後の内容更新・実行終了 | 選択した展開状態を保持 |

`CommandGroupHeader`、`CommandGroupRowWindow`、`CommandGroupOutputDisplay`、`FileChangeDisplayPolicy` の実モデルも呼び、実行中対象、50件窓、20行出力、500行差分との整合を検査する。純粋モデルの検査を、View上の操作確認と読み替えない。

### 2. 専用Rubyで配線と凍結を検査する

PM が `.claude/scripts/task46-wiring.rb` を作成する。見本は `task38-wiring.rb` と `task39-wiring.rb`。

固定基準：

- `TASK46_BASELINE` は明示的なコミットSHAを必須とする。未設定、プレースホルダ、`HEAD`、`HEAD~1`、ブランチ名、無効コミットを拒否する。
- 契約の `baseline_commit` と完全SHAへ解決して一致させる。現在の履歴の祖先であることを確認する。
- 基準には task-40 完了状態があり、task-46 の新規 `TranscriptItemPresentation.swift` が存在しないことを確認する。先行完了状態の確認対象は PM が task-40 完了時に固定する。
- 受け入れSwiftファイルとRuby自身を `git show <固定SHA>:<path>` で取得し、作業ツリーとバイト一致を要求する。
- 必要なblobの取得失敗、ファイル不在、構造解析失敗は非ゼロ終了とする。新規製品ファイルの基準時点での不存在確認は、Gitの取得障害と区別する。
- 固定SHAが実装前HEADと等しいこと自体は拒否しない。実装後HEADへの差し替えは契約照合と実装前状態の確認で拒否する。HEAD自己比較へのフォールバックは禁止する。

配線・保護：

- 実セルの `body` から分類モデルの出力が見出し・補足・意味色・開閉へ届くことを確認する。
- 短文の思考だけ直接表示する分岐、タスクの定数Binding、更新時の開閉リセットを拒否する。
- グループの実行中判定が既存の `header.isRunning` に由来し、閉じたカードの補足に届くことを確認する。
- 回答の常時表示、空思考の非表示、エラー色、活動・AXラベル、既存操作の接続を確認する。
- 変更を許す表示式・Binding等を構造単位で特定し、その他の宣言・操作・描画窓・コピー・文字と余白を凍結blobと比較する。
- task-47 が後で変更する思考要約式・本文描画方式は固定しない。ただし、原文が展開本文へ渡ることと開閉契約は維持する。
- コメント・文字列中の名前、未使用関数、`if false`、戻り値を捨てた呼び出しは接続の証拠としない。
- 正規化はコメントと文字列外の空白に限定し、文字列内容を消して差異を隠さない。

`--selftest` は実ファイルを変えず、本番検査関数へ正常fixtureと単一違反fixtureを渡す。モデル未使用、短文だけ直接表示、件数誤り、常時展開、更新時リセット、実行中表示欠落、エラー色欠落、コピー改変、凍結テスト・Ruby改変、基準不正・不一致・非祖先・実装済み基準・blob取得失敗を個別に検出する。必要な負例をスキップしない。

### 3. 品質ゲート

確認した正本 `.claude/verify.sh` は、8パッケージ、更新隔離検査、差分の空白検査を実行する。PM は task-46 のRuby検査を接続し、先行契約との整合を凍結前に確認する。

以下は将来の実行コマンドであり、本起草では未実行。プレースホルダは PM が実値へ置換する。

```sh
~/.agents/scripts/compact-test task46-wiring-selftest ruby .claude/scripts/task46-wiring.rb --selftest
~/.agents/scripts/compact-test task46-wiring env TASK46_BASELINE=<固定SHA> ruby .claude/scripts/task46-wiring.rb
~/.agents/scripts/compact-test task46-integration bash .claude/verify.sh
```

Appビルドは `macos` ディレクトリで、作業専用のDerivedDataを使う。

```sh
~/.agents/scripts/compact-test task46-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <専用の絶対パス> -destination platform=macOS build
```

PM は `SessionFeature/Package.swift`、`macos/project.yml`、検証スクリプトと適用対象の品質設定を再確認する。専用lint・静的解析の設定済み状態は今回未確認であり、未設定・対象外・実行不能を実行成功と数えない。Swiftテスト、Ruby、ビルド、目視の結果を分け、失敗・警告・未検証範囲を記録する。

### 4. 課金なしのPM目視ゲート

実 claude／codex／cursor の起動・送信を、製品にも目視ゲートにも要求しない。

- **実Appのエラー表示：** 隔離Debug・隔離データの `sessions.json` から、復元失敗プレースホルダでチャット画面へ到達できることは PM 確認済み。確認した `SessionSpawnService.makeRestoreErrorChatSession` は非接続クライアントを使い、`ChatSessionViewModel.markRestoreFailed` がエラー項目を追加する。エラーラベル・意味色・本文の折り返しを確認する。
- **回答・詳細・状態：** PM所有のパッケージ内ハーネスで、既存の `ChatTranscriptView` の `viewModel:` と `transcript:` 入力へ非接続VMと固定項目を渡す。必要に応じて実セルもホストし、処理中・完了の状態を再現する。task-40 のハーネスは完成・利用可能性が今回未確認であり、利用可能なら再利用する。

回答、短文・長文思考、単体・複数コマンド、差分、空・非空タスク、処理中、構造化エラーを表示する。初期状態、マウス・キーボード開閉、同じIDの内容更新と完了、追加表示での末尾到達を確認する。

幅360／720pt、倍率0.8／1.0／2.0、明暗テーマで、重なり・切れ・操作不能がないこと。Reduce Motionでも処理中の意味が伝わること。

復元失敗画面だけを回答・詳細の検証に読み替えない。画像生成だけで合格にせず、PM が実Viewを操作・目視し、`docs/agent-output/visual-task-46.md` に経路、コミット、表示条件、操作、画像、合否、未検証項目を記録する。必要な表示を再現できなければ当該ゲートは未達とし、課金セッションで代替しない。

## レビュー観点（Rubric）

- 回答・詳細・処理中・エラーの区別が実表示へ接続されている。
- 短文思考とタスクも既定閉で、必要な本文・原コマンド・追加表示へ到達できる。
- 閉じたカードでも件数と対象グループの実行中状態が分かる。
- 内容更新・実行終了でユーザーの開閉状態が戻らない。
- エラー・活動状態の正本を保持し、出力文言から失敗を推測していない。
- task-40 の文字・余白、ID、順序、表示窓、コピー、質問・承認・中断を保持している。
- Markdown補正を持ち込まず、task-47 に渡す要約・本文の変更境界が限定されている。
- Rubyが凍結blobと実接続を検査し、単一違反selftestが機能する。
- Cursorがテスト・契約・検査を変更していない。
- 課金なしの目視証拠が対象表示を実際に覆い、未検証を明示している。
