---
id: task-46
difficulty: standard
depends_on:
  - task-40
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptItemPresentationTests.swift
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptMarkdownPresentationTests.swift
  - .claude/scripts/task46-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptItemPresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptMarkdownPresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptFormatting.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+CommandGroup.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+TaskList.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCellsCommon.swift
  - docs/agent-output/task-46.md
---

## 目的

UX-05 / P1「回答本文と処理の詳細に見た目の差を付ける」。回答は最初から読み進められ、処理の詳細は要約から必要時に開けるようにする。処理中・エラーは詳細を開かなくても識別できる。Markdown の装飾記号を表示本文へ露出させず、コード・コマンド・出力中の記号は保持する。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:100`。文字の役割・サイズ・間隔は task-40 の `TranscriptTypography` を正本とし、本タスクで別の体系を作らない。

本稿は `docs/agent-output/contract-draft-task-46.md` 向けの未凍結案である。read-only 指定に従いファイルは作成・変更していない。テスト作成・実行、ビルド、GUI確認も未実施。調査終了時の HEAD は `db137db2b5b4cc35ef3809cfddedef7609921190`。凍結基準には自動採用しない。

## 入出力契約

### 担当・依存・凍結

- 実装担当は Cursor。受け入れテストと Ruby 検査は PM が用意して凍結し、実装担当は作成・変更しない。レビューは実装担当と別モデルが行う。
- `acceptance_tests` の Swift ファイルは既存の `SessionFeatureTests` 内の Swift Testing とする。App ターゲットにテストを置かない。
- テスト、検査、契約、検証スクリプト、台帳、目視ハーネス・目視記録は PM 所有であり、実装担当の `allowed_paths` に含めない。
- **task-40 と重複するファイルは、task-40 完了後の状態を基準にする。** 調査時の旧フォント・余白へ戻さない。PM は task-40 完了後に重複箇所を再確認し、その状態に対して本タスクのテストを凍結する。
- `TranscriptTypography` の実装済み状態は今回未確認。上記2つの新規表示モデルと以下の公開面も、本契約で提案する名前であり、既存シンボルではない。
- `baseline_commit` は task-40 の完了状態と本タスクの凍結テスト・Ruby 検査を含み、task-46 の製品実装を含まないコミットへ固定する。
- task-40 が保護する「展開条件」のうち、本契約で明記する思考文・タスクカードの変更は後続タスクによる意図した変更である。先行検査との衝突があれば、PM が契約の差分を明示して凍結条件を調整する。Cursor に既存テストを弱めさせない。

### 確認した実装と問題の位置

以下の `SessionFeature/` は `macos/Packages/SessionFeature/Sources/SessionFeature/` を指す。行番号は今回読んだ状態の位置であり、task-40 完了後の位置ではない。

| 実ファイル・シンボル | 確認した挙動 |
|---|---|
| `SessionFeature/ChatMessageCells+Basic.swift:184`、`AgentMessageBody` | `ChatMessageRenderCache.markdownBlocks` で分割し、文章を `RichMarkdownView`、コードを `CodeBlockView` へ渡す。回答の折り畳みはない |
| `SessionFeature/RichMarkdownView.swift:14`、`:18`、`:26` | 通常・`streaming:` 初期化とも入力をそのまま保持し、`Markdown(markdown)` へ渡す。ストリーミング専用補正はない |
| `SessionFeature/ChatTranscriptFormatting.swift:10`、`splitFencedCodeBlocks` | 空白を除いた行の `hasPrefix("```")` でフェンスを切り替える。開始・終了の長さを区別せず、未閉じフェンスは Markdown 側へ戻す |
| `SessionFeature/ChatMessageCells+Structured.swift:192`、`ReasoningSummaryView` | 長文は既定折り畳み。展開本文は `Text(text)`、短文は `Text(presentation.trimmedText)` で直接表示 |
| `macos/Packages/AgentDomain/Sources/ChatRenderKit/ChatToolPresentation.swift:23`、`ChatReasoningPresentation` | `trimmedText != headline` で折り畳みの有無を分ける |
| `macos/Packages/AgentDomain/Sources/AgentDomain/ThinkingRecap.swift:59`、`headline(from:)` | 見出しまたは末尾非空行を抽出する。強調・コードを区別する Markdown 解析ではない |
| `SessionFeature/ChatMessageCellsCommon.swift:63`、`:96` | 共通カードの文字列タイトル・補足を `Text` へ直接渡す |
| `SessionFeature/ChatMessageCells+CommandGroup.swift:159`、`CommandGroupCell` | 既定折り畳み。`CommandGroupHeader.isRunning` は導出されるが、カードの `subtitle` は `nil` |
| `SessionFeature/ChatMessageCells+Structured.swift:252`、`CommandExecutionCell` | 既定折り畳み。見出しはコマンドまたは `"Command"`、補足は `"実行中"`／`"Output available"` |
| `SessionFeature/ChatMessageRenderCache.swift:181`、`FileChangeDisplayPolicy.isExpanded` | 行数によらず、未操作なら既定折り畳み。別の `defaultExpanded(lineCount:)` は描画予算用であり、カードの既定状態ではない |
| `SessionFeature/ChatMessageCells+TaskList.swift:16`、`TaskListCell.body` | `.constant(true)` のため展開状態が固定 |
| `SessionFeature/ChatMessageCells+Basic.swift`、`ErrorMessageCell` | `"Error"` のラベル・アイコン・背景・枠に `DSColor.statusError` を使う。本文は直接 `Text(message)` |
| `SessionFeature/ChatMessageCells+Structured.swift:67`、`ThinkingIndicatorCell` | 活動ラベル、orb、AXラベルを表示。`RunningTurnStatusView` が経過・無応答・中断操作を担う |

装飾記号の露出経路として、思考文の本文・見出しが Markdown 解釈を経由しない箇所を確認した。未閉じ記法がそのまま渡る経路も存在する。ただし、仕様の画像 `16-chat-existing.png` の露出がどの経路で発生したか、および各未閉じ入力の実描画結果は**未確認**。MarkdownUI 自体の不具合と断定しない。

### 表示分類の純粋モデル

新規 `TranscriptItemPresentation` は、表示対象の種類から以下を返す小さな値型とする。

- 種類：回答、思考の詳細、コマンドの詳細、ファイル変更、タスク、処理中、エラー。
- 出力：分類、見出し、補足、折り畳み可否、既定展開状態、意味色の役割。
- 入力に必要な件数・実行中状態・活動ラベルは呼び出し側から値で渡す。ViewModel、時計、設定、I/Oから取得しない。
- 色は `Color` の保存値ではなく、通常／処理／エラーの意味を表す値とする。実Viewが現在のテーマの色へ接続する。
- 展開状態は `userOverride ?? defaultExpanded` で導出する。再描画・内容更新・実行終了だけでユーザーの選択を戻さない。
- 既存の `FileChangeDisplayPolicy`、コマンド件数・行数窓、活動状態の導出を再実装しない。既存窓口との一致を受け入れテストで確認する。

| 種類 | 分類・意味色 | 折り畳み | 既定表示・見出し |
|---|---|---|---|
| 回答 | 回答・通常 | 不可 | 本文を表示。追加の「回答」カードで包まない |
| 思考文 | 詳細・処理 | 可 | 短文・長文とも閉じる。「思考の詳細」と装飾除去済み要約 |
| コマンド単体／グループ | 詳細・処理 | 可 | 閉じる。「処理の詳細（N件）」、実行中なら補足「実行中」 |
| ファイル変更 | 詳細・処理 | 可 | 閉じる。既存の変更ファイル要約・追加削除件数を保持 |
| タスク | 詳細・処理 | 可 | 閉じる。「タスク（N件）」 |
| 処理中 | 状態・処理 | 不可 | 既存の活動ラベルと状態表示を常時見せる |
| エラー | エラー・エラー | 不可 | 「エラー」、アイコン、本文を表示 |

補足規則：

- コマンドの完了後、表示対象の出力があれば補足を「出力あり」とする。出力も実行中状態もない場合の既存の非表示条件は維持する。
- `CommandGroupHeader.title`、`CommandGroupTitle.derive` の既存値は変更せず、コマンド要約として展開内容側で使用する。折り畳み見出しの主文にはしない。
- グループの実行中判定は既存の `CommandGroupHeader.isRunning` を使う。後続の別グループまで実行中表示にしない。
- 空の思考文は既存どおり非表示。空タスクの見出しは「タスク（0件）」、展開内容は「タスクなし」とする。
- タスク一覧は状態・順序・IDを保持する。質問・承認操作は処理の詳細へ収納しない。
- サブエージェント行は既存の詳細への移動ボタンとして維持する。失敗アイコンの意味色と移動先を変更しない。
- コマンド出力中の `"error"` 等から失敗を推測しない。既存の構造化エラー・失敗状態を正本とする。

### Markdown 表示の純粋モデル

新規 `TranscriptMarkdownPresentation` に、文章用の `prepare(_ source: String) -> String` と、思考要約用の `summary(_ source: String) -> String?` を置く。Foundation・標準ライブラリおよび既存依存を利用し、新規ライブラリを追加しない。

`prepare` の契約：

1. 完結した正常な Markdown はそのまま既存 Markdown 描画へ渡す。太字・見出し・リンク・箇条書き・表を一律のプレーンテキストへ変換しない。
2. コード領域外の末尾にある未閉じ強調記法は、表示用文字列だけを補正する。元の `ChatItem`、保存、エクスポート、コピー原文は変更しない。
3. 累積入力ごとに元の文字列から導出する。前回の補正結果に追記せず、同長別内容への置換も反映する。
4. 実際の `AgentMessageBody` は通常初期化を使うため、`streaming:` 初期化だけに補正を置かない。通常・`streaming:` の両入口を同じ規則へ接続する。
5. フェンス内・インラインコード内・インデントコード内の `**`、`##`、バッククォート等は装飾除去の対象外。未閉じフェンスの内部もコードとして保護する。
6. 明示的なエスケープ、通常の数式・記号・識別子を保持する。文字列全体から `*`・`#`・`_` を削除する処理は禁止する。
7. `prepare(prepare(source)) == prepare(source)` を満たす。表示用補正の繰り返しで閉じ記号を増殖させない。

`summary` の契約：

- コードブロックを候補から除き、最後のMarkdown見出し、なければ最後の非空文章行を使う。候補がなければ `nil`。
- 見出し・強調・取り消し線などの装飾は除き、リンクは表示名を残す。インラインコードの区切りだけを除き、コード内容の記号は残す。
- 装飾解釈の後に最大60文字へ制限し、超過時だけ `…` を付ける。日本語・結合文字・絵文字を途中のバイトで切らない。
- この処理は自然言語の思考要約に限定する。共通カードの全タイトル、コマンド、パス、出力に無条件適用しない。

コード分割の契約：

- `ChatMarkdownFormatter.splitFencedCodeBlocks` の既存APIと通常の3バッククォート分割結果を維持する。
- 開始フェンスの文字種・長さと終了条件を対応付ける。4バッククォート内の3バッククォート、コード中の見出し・強調を誤って文章へ戻さない。
- チルダフェンス・インデントコードを独自分割しない場合も、コードとして保護したまま MarkdownUI へ渡す。
- 未閉じフェンスを Markdown 側へ返す既存契約は維持できる。その場合も、後段で内部を文章として補正しない。
- コード本文の内容・空白・空行を保持する。既存のコードブロック境界の扱いと、本文データの改変を区別して検査する。

### 実Viewへの配線

- 回答：既存の `AgentMessageBody` → Markdown／コード分割を維持し、Markdown部分を補正済み入力で描く。
- 思考文：短文も `DisclosureCard` に統一する。要約は `summary`、展開本文は Markdown／コードを解釈する実描画経路へ接続する。
- コマンド：固定の処理見出し・件数・実行中状態を折り畳み中にも表示する。展開するとコマンド原文と出力へ到達できる。
- タスク：`.constant(true)` を、非永続のユーザー操作可能な展開状態へ置き換える。
- エラー：ラベル・アイコン・背景・枠の `DSColor.statusError` を維持する。診断本文は原文を保持し、コード・パス中の記号を装飾として削除しない。
- 処理中：活動ラベル、AXラベル、orb、経過、無応答警告、中断操作を保持する。詳細カードが閉じていても状態を識別できる。
- 共通カード：既存のクリック範囲、シェブロン、AXの「展開中／折りたたみ中」を維持する。キーボードで開閉できることを確認する。

### 不変条件

- task-40 の `TranscriptTypography`、文字倍率、テーマ追随、本文・処理要約・補助文字の役割と間隔を維持する。
- メッセージ・グループの順序、ID、空出力の除外、表示範囲、描画予算、スクロール追従は変更しない。
- コマンドの50件単位の追加表示、出力の20行からの全文表示、差分の500行からの追加表示、コピー原文を保持する。
- 差分の行番号・追加削除色・構文ハイライトを保持する。
- 質問・承認・中断・サブエージェント選択のコールバック、保存形式、クライアント、起動・復元処理は変更しない。
- 表・表セルへ `fixedSize` を追加しない。本文・見出し・箇条書きの折り返し高さ保護を削除しない。
- 非同期ハイライト、描画中の観測状態更新、`LazyVStack`、無制限キャッシュを追加しない。
- 新しい設定、製品用デモセッション、課金バックエンドを起動する検証機能を追加しない。

## 成功基準

### 1. Swift Testingで分類・状態を凍結する

PM は以下のリテラル期待値をテストへ固定する。期待値を製品の列挙・モデル出力から生成しない。

| 入力・操作 | 必須結果 |
|---|---|
| 通常回答、複数段落の回答 | 回答分類、折り畳み不可、本文表示 |
| 思考文1行／複数行／60文字超 | 詳細分類、既定閉、要約あり |
| 空白だけの思考文 | 表示なし |
| コマンド1件／2件／コマンド値なし | 件数に対応する処理見出し。コマンド値なしでも件数を失わない |
| 最新グループが実行中 | 既定閉のまま「実行中」 |
| 同じ内容の完了状態 | 「実行中」が消える |
| 過去グループと最新グループ | 最新の対象だけ実行中 |
| 差分0／1／500／501行 | 未操作時は閉。既存の追加表示規則を保持 |
| タスク0／1／複数件 | 件数一致、既定閉、展開可能 |
| エラー、処理中 | 折り畳み不可。通常回答と異なる分類・状態ラベル |
| overrideが `nil`／`true`／`false` | 既定／開／閉に一致 |
| ユーザーが開いた後に本文更新・実行終了 | 開いた状態を維持 |
| ユーザーが閉じた後に本文更新 | 閉じた状態を維持 |
| 同じ長さで内容だけ異なる入力 | 新しい内容が結果へ反映される |

`FileChangeDisplayPolicy.isExpanded`、`CommandGroupHeader.isRunning`、既存の行数・件数窓も実モデルを呼んで確認する。未使用の分類表だけで合格にしない。

### 2. Swift Testingで記号保護を凍結する

次の表の `\n` は改行を表す。`prepare` の結果と `summary` の結果を別々に検査する。

| 入力 | 必須結果 |
|---|---|
| `**確認済み**` | `prepare` は入力不変。要約は `確認済み` |
| `## **確認結果**` | `prepare` は入力不変。要約は `確認結果` |
| `#### 詳細`、H1〜H6 | 見出しとして要約を抽出し、見出し記号を残さない |
| `**確認` | 表示用結果は `**確認**` |
| `**確認*` | 表示用結果は `**確認**` |
| `**` だけ | 表示用結果は空文字列 |
| `## ` だけ | 表示用結果は空文字列 |
| `**確` → `**確認` → `**確認**` | 各入力から再導出し、最後は元入力と一致 |
| インラインコード `` `**x** ## y` `` | `prepare` は入力不変。要約のコード内容は `**x** ## y` |
| 複数バッククォートで囲むコード | 内部の単独バッククォート・強調記号を保持 |
| フェンス内の `let s = "**x** ## y"` | コード本文・コピー原文に同じ文字列が残る |
| 未閉じフェンス内の `**未閉じ` | 内部に強調の閉じ記号を追加しない |
| 4バッククォート内に3バッククォート | 内側を終了フェンスと誤認しない |
| チルダフェンス、4空白インデントコード | 内部の装飾に見える記号を保持 |
| `\*\*literal\*\*` | 明示的なエスケープを保持し、補正で強調へ変えない |
| `a * b`、`2 ** 3`、`C#`、`foo_bar`、`##tag` | 通常文字・演算子として保持 |
| `[詳細](https://example.com/a#b)` | リンク入力不変。要約は `詳細` |
| 日本語・絵文字を含む60／61文字 | 装飾解釈後に60文字境界を適用 |
| コードだけ、空入力 | 思考要約は `nil` |
| 上記各入力の再補正 | 冪等。元入力は不変 |

追加の境界検査：

- フェンス文字の種類・長さ、インラインコードの区切り長、エスケープされた区切り、改行、空行を組み合わせる。
- 正常な箇条書き、引用、リンク、表、太字・斜体・取り消し線を壊さない。
- 通常初期化と `streaming:` 初期化の入力が同じ純粋処理へ到達することを Ruby で検査する。
- この表は任意の壊れたMarkdownを完全修復する要求ではない。表にない曖昧な記号を推測で削除しない。

### 3. Rubyで配線と凍結基準を検査する

`.claude/scripts/task38-wiring.rb`、`task39-wiring.rb` を見本に、PM が `task46-wiring.rb` を作成する。

基準の検査：

- `TASK46_BASELINE` は明示した固定コミットSHAだけを受け付ける。未設定、プレースホルダ、`HEAD`、`HEAD~1`、ブランチ名を拒否する。
- 契約の `baseline_commit` と環境変数を完全SHAへ解決して照合する。
- 基準が現在の履歴の祖先であり、task-40 完了状態を含み、task-46 製品実装を含まないことを確認する。
- 基準の2つの受け入れテストと Ruby 自身を `git show <固定SHA>:<path>` で取得し、作業ツリーとバイト比較する。
- blob取得失敗、対象不在、解析不能は非ゼロ終了。現在のHEADを読み直して基準の代用にしない。
- 固定SHAが実装前のHEADと同じであること自体は拒否理由にしない。実装後HEADへの基準差し替えを、契約照合・実装前状態の確認で拒否する。

配線の検査：

1. 実際の回答・思考文から補正モデル、Markdown描画、コード描画へ到達する。
2. 思考文の短文分岐にも閉じられるカードがあり、展開本文を生の `Text(text)` で代用していない。
3. コマンド単体・グループの見出し、件数、実行中表示がモデルから実描画へ届く。
4. コマンド・出力・差分・コピー経路へ装飾除去を適用していない。
5. タスクカードが可変のBindingを使い、ユーザー操作を反映する。
6. エラーの意味色、状態ラベル、既存AXと操作を保持する。
7. task-40 の文字・余白の配線と、変更対象外の製品宣言を固定blobと比較する。意図した表示変更だけを比較対象から構造単位で除く。
8. コメント、文字列中の呼び出し名、未使用関数、`if false`、結果を捨てる呼び出しで合格しない。

`--selftest` は本番検査関数に正常例と単一違反の負例を渡す。少なくとも「補正結果を未使用」「短い思考文だけ直接表示」「コードにも記号除去」「常時展開」「実行中表示なし」「エラー色消失」「凍結テスト改変」「基準欠落・HEAD指定・blob取得失敗」をそれぞれ検出する。必要な負例をスキップして成功扱いにしない。

PM は未実装によるRED、検査自身のselftest成功、各負例の検出を確認してから凍結する。環境エラーだけをREDの証拠にしない。

### 4. 既存品質ゲートを実行する

確認した正本は `.claude/verify.sh` と `macos/scripts/run-swift-tests.sh`。前者は8パッケージ、更新隔離検査、差分の空白検査を実行する。task-46 のRuby検査は未作成・未接続であり、PM が凍結時に接続する。

```sh
~/.agents/scripts/compact-test task46-wiring-selftest ruby .claude/scripts/task46-wiring.rb --selftest
~/.agents/scripts/compact-test task46-wiring env TASK46_BASELINE=<固定SHA> ruby .claude/scripts/task46-wiring.rb
~/.agents/scripts/compact-test task46-integration bash .claude/verify.sh
```

Appビルドは `macos` ディレクトリで、今回専用のDerivedDataを指定する。

```sh
~/.agents/scripts/compact-test task46-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <今回専用の絶対パス> -destination platform=macOS build
```

- `<固定SHA>` とパスはPMが実値へ置換する。
- `SessionFeature/Package.swift`、`macos/project.yml`、検証スクリプトはtask-40完了後にも再確認する。
- 専用SwiftLint／SwiftFormat設定は今回の検索では見つからなかった。未設定を成功扱いにせず、新規導入を要求しない。
- 既存の `ChatTranscriptFormattingTests` の未閉じフェンス期待値、コマンド見出し・コピー・空出力・差分・タスク更新の回帰検査を維持する。
- 先行契約の配線検査との不整合はPMが契約として解消する。期待値の追従変更・スキップによる成功扱いは禁止する。
- テスト、Ruby検査、ビルド、目視を区別して結果を記録する。失敗・警告・実行不能を省略しない。

### 5. PMが課金なしで実表示を確認する

実claude／codex／cursorの起動・送信を、製品変更にも目視ゲートにも要求しない。

**A. 隔離Debugの復元失敗プレースホルダ**

sessions.jsonからチャット画面を表示できることはPM確認済み。`SessionSpawnService.makeRestoreErrorChatSession` は接続しないクライアントを使い、`ChatSessionViewModel.markRestoreFailed` はエラー項目を追加する。通常の回答・処理履歴は復元表示されないため、この経路の証拠はエラー表示と画面到達に限定する。

PMは隔離Debug・隔離データでエラーラベル、意味色、本文の折り返しを撮影する。送信・再試行・新規課金セッション作成は行わない。

**B. パッケージ内の目視ハーネス**

PMは `SessionFeatureTests` 内のハーネスで、既存の `ChatTranscriptView(transcript:)` に固定データを渡す。通信しないテスト用クライアントを使用し、製品にデモモードを追加しない。task-40 の目視ハーネスが利用可能なら再利用する。今回その完成状態は未確認。

同じ画面に次を置く。

- 見出し・強調・箇条書きを含む回答。
- 短文／長文の思考詳細。
- 完了済み／実行中のコマンドグループ。
- コード・コマンド・出力中の `**`・`##`。
- 差分、タスク、構造化エラー、処理中表示。

反証条件：

- 初期表示で回答本文が隠れる、または思考・タスクの詳細が開いているなら不合格。
- 閉じた処理カードから実行中状態を識別できなければ不合格。
- マウス・キーボードで詳細を開閉できず、追加表示から末尾へ到達できなければ不合格。
- 本文の太字・見出し用記号が露出する、コード中の同じ記号が欠けるなら不合格。
- 内容更新で手動の開閉状態が戻るなら不合格。
- エラーを通常回答と色・ラベル・アイコンで区別できなければ不合格。
- 幅360pt／720pt、倍率0.8／1.0／2.0、明暗テーマで本文が重なる・切れる・操作不能になるなら不合格。
- Reduce Motion時に処理中の意味が失われるなら不合格。

画像生成成功だけを表示成功と数えない。PMは実Viewを操作して画像を確認し、`docs/agent-output/visual-task-46.md` にApp／ハーネスの別、コミット、幅、倍率、テーマ、開閉・実行状態、画像、合否、未検証項目を記録する。ハーネスが成立しなければ該当ゲートは未達とし、課金セッションで代替しない。

## レビュー観点（Rubric）

- 回答・詳細・処理中・エラーの分類が実Viewに反映され、未使用の純粋モデルだけで合格していない。
- 短い思考文とタスクカードも既定閉になり、必要な詳細・追加表示・操作を失っていない。
- ストリーミングの通常初期化経路も補正対象であり、同長置換や完了時に古い内容が残らない。
- Markdownの装飾とコードの記号を区別し、エスケープ・演算子・パスを破壊していない。
- 共通カードへの一括文字列置換でコマンドを壊していない。
- エラーや失敗を出力文字列から推測せず、既存の構造化状態と意味色を使っている。
- task-40 完了後の文字・間隔・テーマ・倍率を保持している。
- ID、順序、表示窓、描画予算、コピー、質問・承認・中断を変えていない。
- Ruby検査は固定SHAのblob比較と到達経路検査を行い、selftestが単一違反を検出する。
- 復元失敗画面の証拠を、回答・処理詳細の検証へ読み替えていない。
- Cursorがテスト・契約・検査を変更せず、未検証・警告・失敗が明示されている。

### 末尾の分割案

表示分類・開閉状態と、Markdown補正・コード保護は独立に失敗しうるため、**凍結前の分割を推奨する**。

- **task-46：回答・処理詳細・状態・エラーの表示契約。** `TranscriptItemPresentation`、各セルの見出し・開閉・状態配線を担当し、task-40に依存する。
- **別タスク（番号未割当）：Markdown装飾の表示とコード保護。** `TranscriptMarkdownPresentation`、フェンス判定、回答・思考文への配線を担当し、task-46に依存する。上記のMarkdown受け入れテストを移し、専用のRuby検査を凍結する。

分割時は本稿を二重の実装契約として使わず、PMがfrontmatter・許可パス・成功基準を切り分けて再凍結する。UX-05は両タスクと課金なし目視ゲートの成立後に完了とする。