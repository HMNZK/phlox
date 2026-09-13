---
id: task-47
difficulty: standard
depends_on: [task-46]
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptMarkdownPresentationTests.swift
  - .claude/scripts/task47-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptMarkdownPresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptFormatting.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift
  - docs/agent-output/task-47.md
---

## 目的

UX-05 / P1 のうち、回答・思考文の Markdown 装飾を表示し、コード・コマンド・出力中の記号を保護する。正常な Markdown の描画を維持し、契約で定める未閉じ記法だけを表示用に補正する。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:100`。先行 task-46 の見出し・開閉・状態表示と、task-40 の文字・余白を保持する。

本稿は read-only 調査による未凍結契約である。ファイル変更、テスト作成・実行、ビルド、GUI確認は行っていない。`TranscriptMarkdownPresentation` と新規試験ファイル名は本契約の提案である。

## 入出力契約

### 担当・依存・凍結

- 実装担当は Cursor。PM が Swift Testing の受け入れテストと専用Ruby検査を作成・凍結し、Cursor は作成・変更しない。レビューは実装担当と別モデルが行う。
- テストは `SessionFeatureTests` 内に置き、App ターゲットへ追加しない。Markdown判定はパッケージ内の純粋処理に置く。
- 契約、テスト、Ruby、検証スクリプト、台帳、目視ハーネス・記録は PM 所有であり、`allowed_paths` 外とする。
- task-46 完了後に凍結する。基準コミットには task-46 の製品実装と task-47 の凍結テスト・Ruby検査を含め、task-47 の製品実装を含めない。
- task-46 完了状態は今回未確認。PM は完了後の実コードを確認し、実装後状態を基準に検査対象を確定する。元草案の調査時HEADを自動採用しない。
- 未実装による RED、検査自身の `--selftest` 成功、単一違反の検出を凍結条件とする。

### 確認した実装

以下の `SF/` は `macos/Packages/SessionFeature/Sources/SessionFeature/`。行番号は今回の読み取り時点であり、task-46 完了後の位置ではない。

| 実ファイル・シンボル | 確認した挙動 |
|---|---|
| `SF/ChatMessageCells+Basic.swift:184`、`AgentMessageBody` | `ChatMessageRenderCache.markdownBlocks` の文章を通常初期化の `RichMarkdownView`、コードを `CodeBlockView` へ渡す |
| `SF/RichMarkdownView.swift:14`／`:18` | 通常・`streaming:` の両初期化で入力をそのまま保持 |
| `SF/ChatTranscriptFormatting.swift:10`、`ChatMarkdownFormatter.splitFencedCodeBlocks` | 空白除去後の `hasPrefix("```")` で開閉。フェンス長の対応を判定しない |
| `SF/ChatMessageCells+Structured.swift:192`、`ReasoningSummaryView` | 調査時は思考本文・短文を `Text` で直接表示 |
| `SF/ChatMessageRenderCache.swift:66`、`markdownBlocks` | 入力文字列をキーとして分割結果を取得 |
| `macos/Packages/AgentDomain/Sources/ChatRenderKit/ChatToolPresentation.swift`、`ChatReasoningPresentation` | `ThinkingRecap.headline(from:)` に要約を委譲 |
| `macos/Packages/AgentDomain/Sources/AgentDomain/ThinkingRecap.swift`、`headline(from:)` | 見出し・末尾非空行を抽出するが、Markdownとコードを区別する解析ではない |
| `macos/Packages/DashboardFeature/Tests/DashboardFeatureTests/ChatTranscriptFormattingTests.swift` | 通常フェンスの分割と、未閉じフェンスをMarkdownへ戻す期待値を持つ |

思考文が Markdown 描画を経由しない経路と、未閉じ記法がそのまま渡る経路を確認した。仕様画像の記号露出がどの経路で発生したか、各未閉じ入力の実描画結果は未確認。MarkdownUI 自体の不具合とは断定しない。

### Markdown表示モデル

新規 `TranscriptMarkdownPresentation.swift` に、次の同期的な純粋処理を置く。

```swift
enum TranscriptMarkdownPresentation {
    static func prepare(_ source: String) -> String
    static func summary(_ source: String) -> String?
}
```

これは新規に定める検査可能な面であり、既存シンボルではない。Foundation・標準ライブラリ・既存依存を利用できる。新規ライブラリ、パッケージ、ViewModel依存、設定、I/O、時計、前回入力を保持する状態を追加しない。

#### `prepare` の規則

1. 完結した正常な Markdown は入力を変更せず、既存の Markdown 描画へ渡す。見出し、強調、リンク、箇条書き、引用、表を一律のプレーンテキストへ変換しない。
2. コード領域外の末尾にある未閉じ強調を、後掲の期待値どおり表示用文字列だけ補正する。任意の壊れた Markdown の完全修復は要求しない。
3. 通常初期化・`streaming:` 初期化の両方から同じ処理へ到達する。実回答が使う通常初期化を対象から外さない。
4. 毎回、元入力から結果を導出する。前回の補正結果への追記を使わず、同長別内容への置換も反映する。
5. フェンス、インラインコード、インデントコードの内部は補正対象外とする。未閉じフェンスも末尾までコードとして保護する。
6. 明示的なエスケープ、演算子、識別子、通常の記号を保持する。文字列全体から `*`・`#`・`_`・バッククォートを削除する処理は禁止する。
7. `prepare(prepare(source)) == prepare(source)` を満たす。
8. `ChatItem`、保存、エクスポート、既存のコピー対象原文を変更しない。

修復範囲外の曖昧な記号を推測で削除しない。未閉じ強調への対処が、コード保護や正常入力の不変条件に優先してはならない。

#### `summary` の規則

- フェンスコード・インデントコードを候補から除く。最後の Markdown 見出しを優先し、なければ最後の非空文章行を使う。
- H1〜H6の見出しを対象にする。`##tag` は見出しと扱わない。
- 見出し・強調・取り消し線の装飾を除き、リンクは表示名を残す。
- インラインコードは区切りだけを除き、内部の `**`・`##`・バッククォート等を保持する。インラインコードを含む文章は要約候補になる。
- 装飾解釈後に Swift の `Character` 単位で先頭60文字へ制限する。60文字ちょうどなら省略記号なし、超過時だけ60文字の後ろへ `…` を付ける。
- 候補がない、または装飾除去後に空なら `nil` とする。空入力、フェンス／インデントコードだけの入力は `nil`。
- 入力文字列を変更しない。思考要約にだけ使用し、共通カードのタイトル、コマンド、パス、診断、出力へ一括適用しない。

### フェンス分割とコード保護

`ChatMarkdownFormatter.splitFencedCodeBlocks` と `ChatMarkdownBlock` の既存APIを維持する。

- 開始フェンスの文字種・長さを記憶する。同じ文字種で開始以上の長さを持ち、後ろに空白以外の内容がない行だけを終了フェンスとして扱う。
- 4バッククォート内の3バッククォートを終了と誤認しない。終了候補にコード文字列が続く行も閉じとして扱わない。
- 通常の3バッククォート分割結果と既存の言語指定を保持する。
- チルダフェンスを独自に分割しない場合も、開始・終了を認識して内部を保護したままMarkdownUIへ渡す。
- 4空白インデントのコードを文章補正しない。コードのインデント・本文内空白・空行を保持する。
- インラインコードは区切りのバッククォート長を対応させ、内部の短いバッククォートを終了扱いしない。
- コード本文から強調・見出しに見える文字列を削除しない。描画と既存コピー経路へ同じコード本文を渡す。
- 未閉じフェンスを `.markdown` へ戻す既存契約を保持する。その戻り値も `prepare`／`summary` が未閉じコードとして認識すること。

既存テストの次の期待値は維持する。`\n` は改行を表す。

```text
入力:
Before\n```json\n{"ok": true}

分割結果:
.markdown("Before")
.markdown("``` json\n{\"ok\": true}")
```

この既存の3バッククォート開始行の正規化と、コード本文の改変を区別する。4本以上の未閉じフェンスを3本へ縮め、内部の3本で誤って閉じる状態にしてはならない。

### 実Viewへの配線

- 回答の既存経路 `AgentMessageBody` → `ChatMessageRenderCache.markdownBlocks` → `RichMarkdownView`／`CodeBlockView` を保持する。
- 回答への補正は `RichMarkdownView` の入口で接続する。`ChatMessageCells+Basic.swift` とキャッシュの変更を必要としない構成にする。
- `RichMarkdownView` の通常・`streaming:` の両入口から、`prepare` の結果が実際の `Markdown` 描画入力へ届くこと。呼び出した結果を捨てない。
- 思考文は task-46 完了後の `ReasoningSummaryView` を使う。要約の供給式を `summary(text)` へ変更し、展開本文を既存の `AgentMessageBody(text: text)` へ接続する。
- 思考要約が `nil` でも、非空のコード本文を持つ思考カードを消さない。「思考の詳細」の見出しを残し、展開して本文へ到達できること。空原文の非表示条件は維持する。
- task-46 の短文・長文とも既定閉、可変Binding、手動開閉保持、見出し、分類、意味色を維持する。
- コマンド・出力・差分・エラー診断本文・ユーザー本文には `prepare`／`summary` を接続しない。
- `ThinkingRecap` と `ChatReasoningPresentation` の共有実装を変更しない。他画面・他クライアントの要約仕様へ波及させない。

### 不変条件と変更境界

- task-40 の文字・余白・倍率・テーマ追随を保持する。
- Markdownのリンク処理、テーマキャッシュ、正常な表・見出し・箇条書き・コードの描画を保持する。
- 表・表セルへ `fixedSize` を追加しない。非表本文・見出し・箇条書きの折り返し高さ保護を削除しない。
- メッセージID・順序、表示窓、描画予算、スクロール追従、既存キャッシュキーを変更しない。
- コマンド50件、出力20行、差分500行の追加表示、コピー原文、差分表示、質問・承認・中断・移動を保持する。
- 非同期ハイライト、描画中の観測状態更新、`LazyVStack`、無制限キャッシュ、新規設定・製品用デモモードを追加しない。
- 保存形式、エクスポート、クライアント、起動・復元処理、パッケージ依存を変更しない。

task-46 との `allowed_paths` の交差は `ChatMessageCells+Structured.swift` だけであり、`depends_on: [task-46]` により逐次化する。同ファイルで許す変更は `ReasoningSummaryView` の要約供給式と展開本文の描画経路、および不要になる同View内の局所変数の除去に限る。

同ファイルのコマンド、差分、サブエージェント、処理中、経過・無応答・中断の各宣言は task-47 の基準blobと一致させる。思考文の変更のために別宣言まで比較から除外しない。

## 成功基準

### 1. Swift Testingで装飾表示と記号保護を検査する

PM は以下をリテラル期待値で凍結する。`\n` は改行を表す。`prepare`、`summary`、分割結果を別々に検査する。

| 入力 | 必須結果 |
|---|---|
| `**確認済み**` | `prepare` は入力不変、要約は `確認済み` |
| `## **確認結果**` | `prepare` は入力不変、要約は `確認結果` |
| H1〜H6の見出し | 見出しとして要約を抽出し、見出し記号を除去 |
| `**確認` | `prepare` は `**確認**` |
| `**確認*` | `prepare` は `**確認**` |
| `**` だけ | `prepare` は空文字列、要約は `nil` |
| `## ` だけ | `prepare` は空文字列、要約は `nil` |
| `**確` → `**確認` → `**確認**` | 各原入力から再導出し、最後は原入力と一致 |
| 同長別内容の未閉じ強調 | 新しい内容を反映し、以前の結果を残さない |
| インラインコード `` `**x** ## y` `` | `prepare` は不変、要約は `**x** ## y` |
| 複数バッククォートのインラインコード | 内部の短いバッククォート・強調記号を保持 |
| フェンス内の `let s = "**x** ## y"` | 分割後のコード本文・コピー対象に原文が残る |
| 未閉じフェンス内の `**未閉じ` | 強調の閉じ記号を追加しない |
| 4バッククォート内の3バッククォート | 内側でコードを終了しない |
| 開始と異なるフェンス文字、短い終了候補、後続に文字がある終了候補 | コードの終了と誤認しない |
| チルダフェンス、4空白インデントコード | 内部の記号・空白・空行を保持 |
| `\*\*literal\*\*` | `prepare` は明示的エスケープを保持 |
| `a * b`、`2 ** 3`、`C#`、`foo_bar`、`##tag` | `prepare` は入力不変 |
| `[詳細](https://example.com/a#b)` | `prepare` は入力不変、要約は `詳細` |
| `~~古い~~` | `prepare` は入力不変、要約は `古い` |
| 複数見出しと後続文章 | 最後の見出しを優先 |
| 見出しなしの複数文章行 | 最後の非空文章行 |
| フェンス内見出しとコード外文章 | コード内見出しを候補にしない |
| 日本語・結合文字・絵文字を含む60／61文字 | 装飾解釈後の60 `Character` 境界と省略記号規則に一致 |
| フェンス／インデントコードだけ、空入力 | 要約は `nil` |
| 正常な太字・斜体・箇条書き・引用・リンク・表 | `prepare` は入力不変 |
| 各入力の再補正 | 冪等、元入力は不変 |

追加の実経路検査：

- `ChatMarkdownFormatter.splitFencedCodeBlocks` の通常分割・既存未閉じ期待値を検査する。
- 分割後の `.markdown` を `prepare` へ渡す組み合わせを検査し、未閉じコード内部が補正されないことを確認する。
- `ChatMessageRenderCache.markdownBlocks` に同長別内容を渡し、内容の取り違えがないことを確認する。
- コード本文の空白・空行を含む期待値はバイト内容も比較し、装飾除去やtrimによる欠落を検出する。

### 2. 専用Rubyで配線と凍結を検査する

PM が `.claude/scripts/task47-wiring.rb` を作成する。見本は `task38-wiring.rb` と `task39-wiring.rb`。task-46 のRubyへ本タスクの検査を混在させない。

固定基準：

- `TASK47_BASELINE` は明示的な固定コミットSHAを必須とし、契約の `baseline_commit` と完全SHAで照合する。
- 未設定、プレースホルダ、`HEAD`、`HEAD~1`、ブランチ名、無効コミット、非祖先を拒否する。
- 基準に task-46 完了状態があり、新規 `TranscriptMarkdownPresentation.swift` が存在しないことを確認する。先行完了状態の確認対象は PM が task-46 完了時に固定する。
- 本タスクの受け入れSwiftファイルとRuby自身を固定SHAのblobから読み、作業ツリーとバイト一致を要求する。
- 必要なblobの取得失敗、対象不在、解析不能は非ゼロ終了。基準時点での新規製品ファイル不存在は、Gitの取得障害と区別する。
- 実装前HEADと固定SHAの一致自体は許す。実装後HEADを基準に差し替える自己比較、HEADへのフォールバックは禁止する。

配線・保護：

- 実回答の通常初期化と `streaming:` 初期化の両方で、`prepare` の戻り値が `Markdown` へ到達する。
- `ReasoningSummaryView` の要約に `summary(text)` が渡り、展開本文が原文を受け取る `AgentMessageBody` へ到達する。
- 短文だけ生の `Text` へ逃がす分岐、要約だけを本文へ渡す配線、`nil` 要約による非空思考の非表示を拒否する。
- 回答の分割経路、コード本文、コピー原文を保護し、コマンド・出力・差分・診断等への補正適用を拒否する。
- `ChatMessageCells+Structured.swift` の変更は前述の2箇所に限定し、開閉状態、空判定、見出し、意味色と他の宣言を基準blobで保護する。
- Markdownのテーマ・リンク・折り返し保護と、変更対象外の製品宣言を固定blobと比較する。
- コメント・文字列中の呼び出し名、未使用関数、`if false`、結果を捨てる呼び出しを接続として数えない。
- 正規化はコメントと文字列外の空白に限定し、コード・ラベル内の文字を消さない。

`--selftest` は本番検査関数へ正常fixtureと単一違反fixtureを渡す。通常入口未接続、streaming入口未接続、補正結果未使用、短文だけ直接表示、要約だけを本文へ渡す、コードにも補正、コピー改変、開閉リセット、保護宣言改変、凍結Swift・Ruby改変、基準不正・不一致・非祖先・実装済み基準・blob取得失敗を個別に検出する。実ファイル変更や必要な負例のスキップは行わない。

### 3. 品質ゲートと先行契約の回帰

正本は `.claude/verify.sh` と `macos/scripts/run-swift-tests.sh`。確認時のverifyは8パッケージ、更新隔離検査、差分の空白検査を実行する。PM は本タスクのRubyと task-46 の回帰検査を接続し、先行契約との衝突を凍結前に解消する。

以下は将来の実行コマンドであり、本起草では未実行。プレースホルダは PM が実値へ置換する。

```sh
~/.agents/scripts/compact-test task47-wiring-selftest ruby .claude/scripts/task47-wiring.rb --selftest
~/.agents/scripts/compact-test task47-wiring env TASK47_BASELINE=<task47固定SHA> ruby .claude/scripts/task47-wiring.rb
~/.agents/scripts/compact-test task47-task46-regression env TASK46_BASELINE=<task46固定SHA> ruby .claude/scripts/task46-wiring.rb
~/.agents/scripts/compact-test task47-integration bash .claude/verify.sh
```

Appビルドは `macos` ディレクトリで実行する。

```sh
~/.agents/scripts/compact-test task47-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <専用の絶対パス> -destination platform=macOS build
```

- 既存の `ChatTranscriptFormattingTests` を維持し、未閉じフェンス期待値の追従変更で通さない。
- task-46 の分類・見出し・開閉・状態と、task-40 の文字・余白の回帰を確認する。
- パッケージ定義、App設定、適用対象のlint・型チェック・静的解析・ビルド・テスト設定は PM が凍結前に再確認する。専用lint・静的解析の設定済み状態は今回未確認。
- 先行検査が今回許可する表示変更まで固定していた場合は、PM が契約の変更境界を明示して解消する。Cursor にテスト変更・スキップを行わせない。
- Swiftテスト、Ruby、ビルド、目視を区別し、失敗・警告・未設定・実行不能を記録する。

### 4. 課金なしのPM目視ゲート

実 claude／codex／cursor の起動・送信を、製品にも目視ゲートにも要求しない。

`sessions.json` の復元失敗プレースホルダでチャット画面へ到達できることは PM 確認済み。この画面は到達性・エラー表示の証拠とし、回答・思考文のMarkdown表示を検証した証拠とはしない。

PM はパッケージ内の目視ハーネスで、既存の `ChatTranscriptView` の `viewModel:`／`transcript:` 入力へ非接続VMと固定データを渡す。task-46 のハーネスは利用可能なら再利用する。ハーネスと記録はPM所有とし、製品にデモモードを追加しない。

同じ画面で次を確認する。

- 見出し、太字、箇条書き、リンク、表を含む回答。
- `**確` → `**確認` → `**確認**` の累積更新と同長別内容への置換。
- 短文・長文思考の装飾除去済み要約と、開いた本文のMarkdown表示。
- 完結・未閉じ・4本バッククォート・チルダ・インデント・インラインの各コード。
- コード・コマンド・出力・エラー診断中の `**`・`##`・パス・演算子の保持。
- task-46 の既定閉、手動開閉保持、件数・実行中表示。

幅360／720pt、倍率0.8／1.0／2.0、明暗テーマで重なり・切れ・操作不能がないこと。正常な装飾記号が本文に露出する、コード記号が欠ける、コピー原文が変わる、更新時に古い内容が残る場合は不合格とする。

PM が実Viewを操作・目視し、`docs/agent-output/visual-task-47.md` に経路、コミット、入力、幅、倍率、テーマ、開閉・更新操作、画像、合否、未検証項目を記録する。画像生成だけで合格にせず、必要な表示を再現できなければゲート未達とする。課金セッションで代替しない。

## レビュー観点（Rubric）

- 補正モデルの戻り値が、実回答の通常入口とstreaming入口、思考要約・展開本文へ接続されている。
- 正常なMarkdownを保持し、契約外の曖昧な記号を推測で削除していない。
- フェンスの文字種・長さ、インライン区切り、エスケープ、インデントコードを区別している。
- 未閉じフェンスの分割後もコード保護が続き、既存の未閉じ期待値を維持している。
- コード・コマンド・出力・診断・コピー原文を壊していない。
- 同長置換と補正の冪等性を満たし、前回入力に依存していない。
- 要約の60文字制限が装飾解釈後の `Character` 単位である。
- task-46 の見出し・開閉・状態、task-40 の文字・余白、Markdownの折り返し保護を保持している。
- 共通ファイルの変更が思考要約・本文描画に限定され、他の宣言を保護している。
- Rubyが固定SHAのblob比較と実配線を検査し、単一違反selftestが機能する。
- Cursorがテスト・契約・検査を変更せず、課金なしの目視と未検証範囲が記録されている。

### 分割案

旧単一草案を、本書の task-46「表示分類・見出し・開閉・状態」と task-47「Markdown装飾・コード保護」に置き換える。旧草案を第三の実装契約として併用しない。

`allowed_paths` の交差は `ChatMessageCells+Structured.swift` の1ファイルに限定し、task-40 → task-46 → task-47 の順に実装・凍結する。task-47 は task-46 完了後の同ファイルを基準に、思考要約と展開本文だけを変更する。

UX-05 の完了には、両契約の検査・独立レビュー・課金なし目視ゲートの成立を必要とする。
