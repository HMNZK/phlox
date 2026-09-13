---
id: task-46
difficulty: standard
depends_on: [task-40]
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptItemPresentationTests.swift
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask46Tests.swift
  - .claude/scripts/task46-wiring.rb
baseline_commit: "0c6037f"
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

UX-05 / P1「回答本文と処理の詳細に見た目の差を付ける」のうち、表示分類・見出し・開閉・状態表示を変更する。回答は常時読め、詳細は必要時に開け、処理中とエラーは閉じた詳細の外から識別できるようにする。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:100`。文字・余白は task-40 の体系を維持する。Markdown 補正・思考要約の装飾除去・思考本文の Markdown 描画は task-47 が担当する。

本書は敵対レビューと PM 裁定を反映した未凍結契約である。今回の改訂担当は read-only であり、ファイル保存、テスト作成・実行、ビルド、GUI 操作は行っていない。新規モデルと試験ファイルは実装予定の契約面であり、存在・合格を主張しない。

## 担当・依存・凍結

- 実装担当は Cursor。PM が受け入れテスト・Ruby 検査・目視ハーネスを作成し、実装前に凍結する。Cursor は変更しない。
- 受け入れテストは `SessionFeatureTests` 内の Swift Testing と `.claude/scripts/task46-wiring.rb` に限定する。App ターゲットへテストを追加しない。
- 契約、テスト、Ruby、検証スクリプト、台帳、目視ハーネス、目視記録、後継 ADR は PM 所有であり、実装担当の `allowed_paths` 外とする。
- task-40 完了後に、対象コードと品質設定を再確認して凍結する。以前の草案で未確認だった task-40 の完了状態を、文書の記載だけで完了扱いしない。
- 基準コミット B46 は task-40 完了状態と本タスクの凍結テスト・Ruby・目視ハーネスを含み、`TranscriptItemPresentation.swift` と task-46 の製品変更を含まない。
- PM は B46 作成後に `baseline_commit` を実 SHA へ固定する。コミット自身の SHA をそのコミット内へ埋め込むことは要求しない。
- 凍結前に、未実装を理由とする RED、Ruby の `--selftest`、単一違反の検出、目視ハーネスの起動・状態遷移・操作・撮影を確認する。新規シンボル未定義によるコンパイル RED は理由を記録し、実装後の変異検査でアサーションの検出力を確認する。環境障害は RED の代用にならない。

### 先行契約との整合

task-40 の Ruby が行う製品ソースの残余比較は、task-40 完了時点で行う「task-40 着手時からの変更範囲検査」とする。task-46・task-47 の製品変更へ遡って適用しない。

task-46 の Ruby は、自身の恒久回帰検査で `TranscriptTypography` 参照の維持を検査する。task-40 の残余比較を再実行したことを、文字・余白の回帰確認の代用にしない。先行テストを Cursor に削除・スキップ・弱体化させない。

### ADR 0147 の置換対象

本契約は `macos/docs/adr/0147-chat-code-card-and-header-dedup.md` の次の決定を、対象表示に限って置き換える。

| 旧決定 | 本契約での決定 |
|---|---|
| コマンドグループの見出しはコマンド要約 | 単体・グループとも「処理の詳細（N件）」。コマンド原文・既存要約は展開内容から読める |
| サブタイトルは常に `nil`。実行中はヘッダーに出さない | コマンド詳細には「実行中」または「出力あり」。思考詳細には要約を渡す |
| 思考の見出しと本文が同一なら折り畳まない | 非空の思考は短文・長文とも折り畳み可能で既定閉 |

コードカード、差分の帯、行番号、構文ハイライト、ファイル変更の既定閉など、上表以外の決定は維持する。後継 ADR の起草と関連文書の更新は PM がフェーズ5で行う。本タスクの実装担当へ ADR 更新を要求しない。

## 調査結果

以下の `SF/` は `macos/Packages/SessionFeature/Sources/SessionFeature/`。行番号は既存草案・敵対レビューの調査位置を再利用しており、凍結時の位置を保証しない。

| 実ファイル・シンボル | 調査した挙動 |
|---|---|
| `SF/ChatMessageCells+Basic.swift:184`、`AgentMessageBody` | Markdown を `RichMarkdownView`、コードを `CodeBlockView` へ渡す。回答は折り畳まない |
| 同`:203`、`ErrorMessageCell` | `"Error"`、警告アイコン、`DSColor.statusError` のラベル・背景・枠 |
| `SF/ChatMessageCells+Structured.swift:192`、`ReasoningSummaryView` | `usesDisclosure` で短文を直接表示し、展開本文は `Text(text)` |
| 同`:67`、`ThinkingIndicatorCell` | 活動ラベル・orb・AX ラベル。経過・無応答・中断を既存 View へ委譲 |
| 同`:252`、`CommandExecutionCell` | 既定閉。見出しはコマンド、補足は実行中または英語の出力表示 |
| 同`:287`、`FileChangeCell` | `FileChangeDisplayPolicy.isExpanded` でユーザー操作を優先 |
| `SF/ChatMessageCells+CommandGroup.swift:15`、`CommandGroupHeader` | 最新 ID・ターン状態から実行中と表示可否を導出 |
| 同`:36` | 1件グループは空出力でも表示対象 |
| 同`:159`、`CommandGroupCell` | 既定閉。カードの補足は `nil` |
| `SF/ChatMessageCells+TaskList.swift:10` | `.constant(true)` で展開固定 |
| `SF/ChatMessageCells.swift:51`・`:58` | 空白思考は子 View を生成しない。単体コマンドは空白出力かつ非実行中なら非表示 |
| `SF/ChatMessageCellsCommon.swift` | 共通カードのボタン・シェブロン・AX 値「展開中／折りたたみ中」 |

## 入出力契約

### 表示分類モデル

`TranscriptItemPresentation.swift` に同期的な値型 `TranscriptItemPresentation` を置く。

入力は種類、原文、要約、件数、実行中、出力の有無、既存ファイル変更タイトル、活動ラベルとする。コマンドについては単体経路／グループ経路を区別できる入力を持つ。1件という件数だけから経路を推測しない。

出力は表示可否、分類、見出し、補足、折り畳み可否、既定展開状態、意味色の役割とする。意味色は SwiftUI の `Color` ではなく、通常／処理／エラーを表す値とする。

件数・状態・変更ファイル要約は実データから渡す。モデルから ViewModel、時計、設定、ファイル、ネットワーク、プロセスへアクセスしない。

| 種類 | 分類・意味色 | 折り畳み／既定 | 見出し・補足 |
|---|---|---|---|
| 回答 | 回答・通常 | 不可／本文表示 | 追加見出し・カードなし |
| 思考 | 詳細・処理 | 可／閉 | 「思考の詳細」、渡された要約 |
| コマンド単体・グループ | 詳細・処理 | 可／閉 | 「処理の詳細（N件）」、下表の補足 |
| ファイル変更 | 詳細・処理 | 可／閉 | 既存の変更ファイル要約と増減件数 |
| タスク | 詳細・処理 | 可／閉 | 「タスク（N件）」 |
| 処理中 | 状態・処理 | 不可／表示 | 既存の活動ラベル |
| エラー | エラー・エラー | 不可／表示 | 「エラー」、診断本文は原文 |

- 空白だけの思考は非表示。非空思考は要約が `nil` でも表示する。
- task-46 の思考要約は既存 `ReasoningPresentation` から供給する。分類モデルは Markdown を解析しない。
- コマンド単体は1件。グループは入力項目数を数え、空出力除外後の行数や50件の描画窓から数えない。コマンドが `nil` でも数える。
- グループの実行中・表示可否は `CommandGroupHeader.isRunning`／`shouldRender` を引き続き使う。
- 「出力あり」は表示対象に空白以外の出力が存在するときだけ。実行中の補足が優先する。出力中の `"error"` 等から失敗を推測しない。
- 空タスクは「タスク（0件）」を表示し、展開本文は「タスクなし」。

### コマンド表示の固定期待値

入力 ID は単体・1件グループが `a`、2件グループが順に `a,b`。時刻は固定値、各 command は `"echo ok"` とする。

状態列の「最新」は最終項目 ID と `lastTranscriptID` が一致、「過去」は `lastTranscriptID = "z"`。実行中／完了はターン状態であり、過去項目自体を実行中にしない。

各セルは `表示可否／補足／展開時の表示行ID`。`nil` は補足なし、`[]` は非表示のため到達する行なし。閉じている間は本文行を描画しない。

| 経路・件数 | output（入力順） | 見出し | 最新・実行中 | 最新・完了 | 過去・ターン実行中 | 過去・完了 |
|---|---|---|---|---|---|---|
| 単体・1 | `[""]` | 処理の詳細（1件） | `true／実行中／[a]` | `false／nil／[]` | `false／nil／[]` | `false／nil／[]` |
| 単体・1 | `[" \n"]` | 処理の詳細（1件） | `true／実行中／[a]` | `false／nil／[]` | `false／nil／[]` | `false／nil／[]` |
| 単体・1 | `["ok"]` | 処理の詳細（1件） | `true／実行中／[a]` | `true／出力あり／[a]` | `true／出力あり／[a]` | `true／出力あり／[a]` |
| グループ・1 | `[""]` | 処理の詳細（1件） | `true／実行中／[a]` | `true／nil／[a]` | `true／nil／[a]` | `true／nil／[a]` |
| グループ・1 | `[" \n"]` | 処理の詳細（1件） | `true／実行中／[a]` | `true／nil／[a]` | `true／nil／[a]` | `true／nil／[a]` |
| グループ・1 | `["ok"]` | 処理の詳細（1件） | `true／実行中／[a]` | `true／出力あり／[a]` | `true／出力あり／[a]` | `true／出力あり／[a]` |
| グループ・2 | `["",""]` | 処理の詳細（2件） | `true／実行中／[b]` | `false／nil／[]` | `false／nil／[]` | `false／nil／[]` |
| グループ・2 | `[" \n"," \n"]` | 処理の詳細（2件） | `true／実行中／[b]` | `false／nil／[]` | `false／nil／[]` | `false／nil／[]` |
| グループ・2 | `["ok","ok"]` | 処理の詳細（2件） | `true／実行中／[a,b]` | `true／出力あり／[a,b]` | `true／出力あり／[a,b]` | `true／出力あり／[a,b]` |
| グループ・2 | `["ok",""]` | 処理の詳細（2件） | `true／実行中／[a,b]` | `true／出力あり／[a]` | `true／出力あり／[a]` | `true／出力あり／[a]` |
| グループ・2 | `["","ok"]` | 処理の詳細（2件） | `true／実行中／[b]` | `true／出力あり／[b]` | `true／出力あり／[b]` | `true／出力あり／[b]` |
| グループ・2 | `["ok"," \n"]` | 処理の詳細（2件） | `true／実行中／[a,b]` | `true／出力あり／[a]` | `true／出力あり／[a]` | `true／出力あり／[a]` |
| グループ・2 | `[" \n","ok"]` | 処理の詳細（2件） | `true／実行中／[b]` | `true／出力あり／[b]` | `true／出力あり／[b]` | `true／出力あり／[b]` |

非表示行でも分類モデルが導出する見出しは上表の文字列である。実画面には表示しない。

追加の固定期待値：

- 上表の command を `nil` に置換しても、表示可否・補足・件数・行 ID は同じ。
- `a,b` がともに表示される最新実行中グループの行状態は `[false,true]`。過去グループと完了グループは `[false,false]`。
- 51件の入力 ID は `c01`〜`c51`、全出力 `"ok"`。見出しは「処理の詳細（51件）」。
- 初期表示窓50の行 ID は次の固定配列。隠れた件数は `1`。

```text
[c02,c03,c04,c05,c06,c07,c08,c09,c10,c11,c12,c13,c14,c15,c16,c17,c18,c19,c20,c21,c22,c23,c24,c25,c26,c27,c28,c29,c30,c31,c32,c33,c34,c35,c36,c37,c38,c39,c40,c41,c42,c43,c44,c45,c46,c47,c48,c49,c50,c51]
```

- 追加表示後は先頭に `c01` が入り51行、隠れた件数 `0`。最新実行中なら補足「実行中」、最新完了・過去実行中・過去完了なら「出力あり」。
- 空配列は製品のコマンドグループとして生成しない。0件グループを追加表示する変更をしない。

期待値を `CommandGroupHeader` や分類モデルの出力から生成しない。両者を別々に上表へ照合する。

### 開閉と実 View への配線

- 詳細のユーザー操作は非永続。未操作時は閉じ、導出は `userOverride ?? defaultExpanded` と等価にする。
- 開閉保持は、同じセルが表示階層に残る更新に限定する。同一 ID の非空本文更新、同長別内容への置換、表示が継続する実行終了で操作をリセットしない。
- 思考を「非空・展開済み → 空白 → 非空」と同一 ID で更新した場合、空白時は非表示、再表示時は既定閉とする。親による子 View の除去を跨いで保持しない。
- セッション切替、項目除去・再挿入、セルを除去する表示窓変更について保持を保証しない。永続状態や親側の状態辞書を追加しない。
- 回答・処理中・エラーを詳細用 override で隠さない。
- 思考は短文も `DisclosureCard` を使い、展開本文へ原文全体を渡す。task-46 では `Text` 描画を維持してよい。文字は body、色は secondary。
- コマンドの分類モデル出力を実カードの見出し・補足へ渡す。
- `CommandGroupHeader.title`／`CommandGroupTitle.derive` は変更せず、既存要約を展開内容側から読めるようにする。単体も見出しから外したコマンド原文を展開内容へ残す。
- タスクの `.constant(true)` を操作可能な状態へ置き換える。ID・順序・状態・アイコン・AX ラベルを維持する。
- ファイル変更は `FileChangeDisplayPolicy.isExpanded` を使う。描画予算用の `defaultExpanded(lineCount:)` をカードの既定展開判定へ流用しない。
- 通常／処理の意味色は既存の `isToolCall` とテーマへ接続する。差分の追加・削除色は保持する。
- エラーは「エラー」、警告アイコン、既存の `DSColor.statusError` のラベル・背景・枠。診断本文の記号・パス・コードを変更しない。
- 活動ラベルと AX ラベルは同じ実状態に由来する。orb、経過、無応答警告、中断操作を維持する。
- 質問・承認は詳細カードへ収納しない。サブエージェントの移動操作・移動先・失敗色を保持する。
- 共通カードを再利用し、クリック範囲・シェブロン・キーボード開閉・AX 値を維持する。

## 変更境界と不変条件

- task-40 の文字・余白・倍率・テーマ追随と `TranscriptTypography` への参照経路を維持する。古い固定フォント・独自余白へ戻さない。
- ID・順序・表示範囲・描画予算・スクロール追従を変更しない。
- コマンド50件、出力20行、差分500行からの追加表示を保持する。
- コピー原文、差分の行番号・構文ハイライト・増減色、質問・承認・中断・移動コールバックを保持する。
- `ChatTranscriptFormatting.swift`、`RichMarkdownView.swift`、共通カード、キャッシュ、共有ドメイン、クライアント、保存・復元、パッケージ依存を変更しない。
- task-46 では `AgentMessageBody` の宣言・Markdown／コード分割経路を変更しない。
- 描画中の観測状態更新、`LazyVStack`、非同期ハイライト、無制限キャッシュ、新規設定、製品用デモモードを追加しない。

task-47 との製品 `allowed_paths` の交差は `ChatMessageCells+Structured.swift` と `ChatMessageCells+Basic.swift` の2ファイル。task-40 → task-46 → task-47 の順で逐次化する。

task-47 に許す変更は次に限定する。

- `ReasoningSummaryView` の要約供給式、展開本文の Markdown 描画と secondary 本文色の受け渡し、不要な局所変数の除去。
- `AgentMessageBody` の既定 primary の本文色引数追加と、Markdown ブロックへの引数転送。
- `RichMarkdownView` の本文色引数・テーマ・キャッシュキーへの限定配線は task-47 側で扱う。

task-46 の恒久回帰検査は、上記の具体的な要約式・本文描画方式を固定しない。原文の受け渡し、空判定、見出し、開閉、状態、文字体系は固定する。ファイル全体や `ReasoningSummaryView` 全体を保護対象から外さない。

## 受け入れテスト

### Swift Testing

表示分類、コマンド表、開閉導出をリテラル期待値で検査する。

| 入力・操作 | 期待値 |
|---|---|
| 通常・複数段落の回答 | 回答分類、折り畳み不可、本文表示 |
| 1行・複数行・60文字超の非空思考 | 「思考の詳細」、詳細分類、既定閉 |
| `""`、`" \t\n"` の思考 | 非表示 |
| 非空思考、要約 `nil` | 表示、補足なし、展開本文へ到達可能 |
| 同長別内容・別要約 | 新しい原文・要約が反映される |
| タスク0・1・2件 | 「タスク（0件）」「タスク（1件）」「タスク（2件）」、既定閉 |
| 空タスクの展開 | 「タスクなし」 |
| override `nil`・`true`・`false` | 閉・開・閉 |
| 開／閉操作後、セルが残る内容更新・実行終了 | 開／閉を保持 |
| 非空・開 → 空白 → 非空、同一 ID | 非表示を挟み、再表示時は閉 |
| 処理中 | 状態分類、折り畳み不可、活動ラベル |
| エラー本文 `"a/**/b: error"` | 「エラー」、エラー分類、本文は同じ文字列 |
| 差分0・1・500・501行 | 未操作時は閉。501行は初期500行、残り1行 |

実モデル `CommandGroupHeader`、`CommandGroupRowWindow`、`CommandGroupOutputDisplay`、`FileChangeDisplayPolicy` も直接検査する。21行出力は初期20行・隠れた1行・展開時21行・コピーは全文。これらのモデルテストを View 操作の証拠と読み替えない。

### Ruby：固定 SHA・着手時範囲・恒久回帰

PM が `.claude/scripts/task46-wiring.rb` を作成する。二段階の見本は task-41、構造検査の参考は task-38／39 とする。

**常時実行する凍結検査：**

- `TASK46_BASELINE` は明示的なコミット SHA 必須。契約の `baseline_commit` と完全 SHA へ解決して一致させ、現在の履歴の祖先であることを確認する。
- 未設定、プレースホルダ、`HEAD`、`HEAD~1`、`@`、ブランチ名、無効コミット、非祖先を拒否する。
- 基準に task-40 完了状態があり、新規 `TranscriptItemPresentation.swift` が存在しないことを確認する。先行完了の確認対象は PM が凍結前に確定する。
- `acceptance_tests` の Swift ファイル、ハーネス、Ruby 自身を `git show <B46>:<path>` で取得し、作業ツリーとバイト一致させる。
- blob 取得失敗、必要ファイル不在、解析不能は非ゼロ終了。新規製品ファイルの基準時点での不存在は、Git 障害と区別する。
- 明示 SHA が実装前 HEAD と等しいこと自体は許す。実装後 HEAD への差し替えや HEAD 自己比較へのフォールバックは禁止する。

**`TASK46_SCOPE_CHECK=1` のときだけ実行する着手時の変更範囲検査：**

- B46 からの製品変更が本契約の許可ファイル・許可構造に収まること。
- 許可した表示式・Binding・本文追加部分以外の宣言を、B46 の blob と比較する。
- `AgentMessageBody`、共通操作、描画窓、コピー等の task-46 で変更しない部分を保護する。
- この検査は task-46 の実装・完了ゲートで実行する。後続 task-47 の回帰では実行しない。

**環境変数なし／`TASK46_SCOPE_CHECK=0` で実行する恒久回帰検査：**

- 実セルの `body` から分類モデルの結果が見出し・補足・意味色・開閉へ届くこと。
- 短文だけ直接表示、タスクの定数 Binding、表示継続中の更新による開閉リセットを拒否する。
- グループ実行中の正本が `header.isRunning` で、閉じたカードの補足へ届くこと。
- 回答の常時表示、空思考の非表示、非空・要約 `nil` の表示、エラー色、活動・AX ラベル、操作の配線を検査する。
- task-47 が変更できる要約式・本文描画方式・本文色引数を許容しながら、原文と secondary 色の役割、開閉契約を保護する。
- `TranscriptTypography` のフォント・余白・行間参照が、実描画経路に残ることを検査する。既存の `ChatScaledFont`／`ChatTypography` を介す参照も経路を確認し、未使用の参照1個で代用しない。
- 永続的な不変部分だけを B46 の構造単位の blob 比較で保護する。task-40 の残余比較や task-46 のファイル全体比較を恒久回帰へ混ぜない。

コメント・文字列中の名前、未使用関数、`if false`、戻り値を捨てた呼び出しは接続と認めない。正規化はコメントと文字列外の空白に限定し、文字列内容・補間内の実コードを消さない。

`--selftest` は実ファイルを変更せず、本番検査関数へ正常 fixture と単一違反 fixture を渡す。次を個別に検出し、期待エラー集合まで照合する。

- モデル未接続、短文だけ直接表示、件数誤り、常時展開、更新時リセット、実行中補足欠落。
- エラー色・活動 AX・コピー・描画窓・`TranscriptTypography` の接続欠落。
- 凍結 Swift・ハーネス・Ruby 改変、基準不正・不一致・非祖先・実装済み基準・blob 取得失敗。
- 範囲外変更は `SCOPE_CHECK=1` で失敗する。
- task-47 で許可する本文・要約・色引数の変更 fixture は恒久回帰で成功する。
- 同じ fixture に開閉リセットや typography 退行を1件加えると恒久回帰で失敗する。
- 環境変数なし／`0` と `1` の検査分離が機能する。必要な負例をスキップしない。

## 品質ゲート

調査した `.claude/verify.sh` は8パッケージ、更新隔離検査、差分の空白検査を実行する。Swift テストの正本は `macos/scripts/run-swift-tests.sh`。PM は task-46 完了分岐に scope 検査、通常回帰に scope なし検査を接続する。

以下は実装時の実行手順であり、本改訂では未実行。SHA と DerivedData は PM が実値へ置換する。

```sh
~/.agents/scripts/compact-test task46-selftest ruby .claude/scripts/task46-wiring.rb --selftest
~/.agents/scripts/compact-test task46-scope env TASK46_BASELINE=<B46> TASK46_SCOPE_CHECK=1 ruby .claude/scripts/task46-wiring.rb
~/.agents/scripts/compact-test task46-regression env TASK46_BASELINE=<B46> TASK46_SCOPE_CHECK=0 ruby .claude/scripts/task46-wiring.rb
~/.agents/scripts/compact-test task46-integration bash .claude/verify.sh
```

App ビルドは `macos` ディレクトリで実行する。

```sh
~/.agents/scripts/compact-test task46-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <専用の絶対パス> -destination platform=macOS build
```

PM は凍結前に `SessionFeature/Package.swift`、`macos/project.yml`、検証スクリプト、対象に適用される lint・型チェック・静的解析設定を確認する。未設定・対象外・実行不能を成功扱いしない。Swift テスト、Ruby、ビルド、目視の結果と警告・失敗・未検証範囲を分けて記録する。

## 課金なしの PM 目視ゲート

実 claude／codex／cursor の起動・送信・課金セッションを要求しない。

### ハーネスの準備と凍結前確認

PM は `PMTranscriptVisualTask46Tests.swift` に Swift Testing のハーネスを置く。製品へデモモードやテスト専用 setter を追加しない。

1. `StructuredAgentClient` のテスト用 double を注入する。既存の `MidTurnPersistenceWhiteboxTests.swift` の `AsyncStream<NormalizedChatEvent>` と continuation の方式を再利用できる。`start`・送信・終了はローカルに完結させる。
2. VM の公開開始経路でイベント購読を開始し、double から `.turnStarted` と `.turnCompleted(nativeSessionId: nil)` を注入する。`status.isRunning == true`、次に `false` を Swift Testing で実際に待って確認する。private setter の操作や固定 transcript の置換だけで実行状態を再現したことにしない。
3. 通常の追記は実イベントで流す。同長置換・空白を挟む置換は、安定した Observable なハーネスモデルに保持した `[ChatItem]` を `ChatTranscriptView(transcript:)` へ渡して更新してよい。この場合も実行状態は VM のイベントで変える。
4. 同一 ID 更新中は同じ VM、ホスト、ルート View の identity を保つ。更新ごとに `NSHostingView` を作り直したり `.id(UUID())` を付けたりしない。
5. 専用 `UserDefaults(suiteName:)` に `ThemeStore.themeKey` と `ChatFontSettings.scaleKey` を設定し、ルートへ `.defaultAppStorage(suite)` を適用する。システム明暗は color scheme／appearance も明示する。環境変数のデータ隔離だけで AppStorage 注入済みと扱わない。
6. `@MainActor` で `NSWindow` と `NSHostingView` を作り、実 `ChatTranscriptView` と必要な単体経路を操作可能な状態で表示する。
7. 製品の `ChatSessionView.swift:122`・`:123` と同じ `ComposerLayout.transcriptContentMaxWidth(mainColumnWidth:)`、コンポーザの計測高さに相当する `bottomScrollContentMargin` を使う。幅だけ指定して末尾余白を0にした簡略ホストで末尾到達を合格にしない。
8. マウス・キーボード操作、同一 ID 更新、実行開始・完了、AppStorage の倍率・テーマ反映、画像保存を PM が凍結前に実行する。凍結前の旧表示は成功条件未達として記録し、ハーネスが再現できることだけを確認する。

通常のテスト実行では固定シナリオを自動確認して終了する。`PHLOX_PM_VISUAL_TASK=46` のときは PM 操作用ウィンドウを表示し、ハーネス内の終了操作まで保持する。この環境変数はテスト内だけで解釈し、受け入れアサーションをスキップする用途に使わない。

起動コマンドも PM が凍結前に実行確認する。

```sh
~/.agents/scripts/compact-test task46-pm-visual env PHLOX_PM_VISUAL_TASK=46 bash macos/scripts/run-swift-tests.sh SessionFeature
```

### 実装後の確認

回答、短文・長文思考、単体・グループコマンド、差分、空・非空タスク、処理中、構造化エラーを表示する。

- 初期閉、マウス・キーボード開閉、AX 値、原文への到達。
- 同一 ID・表示継続中の内容更新と実行終了で開閉保持。
- 思考の非空 → 空白 → 非空で再表示時は閉。
- コマンド表の単体／1件グループの差、最新／過去の補足。
- 50件・20行・500行からの追加表示と末尾到達。
- 幅360／720pt × 倍率0.8／1.0／2.0 × 明暗テーマ。重なり、切れ、操作不能がない。
- Reduce Motion 下でも処理中の意味が読める。

復元失敗プレースホルダによる実 App エラー表示は補助経路とする。既存草案では PM 確認済みと記録されているが、本改訂では再実行していない。この画面を回答・詳細・状態更新の検証へ読み替えない。

PM は `docs/agent-output/visual-task-46.md` にコミット、起動コマンド、入力、イベント、ID、幅、末尾余白、倍率、テーマ、操作、画像、合否、未検証項目を記録する。画像生成だけでは合格にしない。

終了時はウィンドウ・イベント stream・VM の購読を閉じ、専用 defaults suite を清掃する。起動したテストプロセスの PID と親子関係を確認し、その作業の残存プロセスだけを終了して `ps` で再確認する。稼働中のリリース版・共有プロセスは停止しない。

## レビュー観点と完了条件

- 表示分類・コマンドの固定期待値が実 View まで接続されている。
- 開閉保持の保証範囲と、空白を挟む再表示時の既定閉が区別されている。
- 原文・操作・描画予算・文字体系を保持している。
- ADR 0147 の置換対象が限定され、後継 ADR は PM のフェーズ5責務になっている。
- Ruby の scope 検査と恒久回帰が分離され、task-47 の許可変更を妨げない。
- 凍結テストを実装担当が変更していない。
- 必須テスト・品質ゲート・独立レビュー・PM 目視が成立し、未検証を隠していない。

task-46 の成立だけを UX-05 全体の完了としない。UX-05 の完了には task-47 と PM のフェーズ5での文書反映も必要とする。

## 受け入れ検査の敵対レビュー反映（2026-09-13、`docs/agent-output/task46-acceptance-adversarial.md` を PM 裁定）

- MUST1（同一入力に true/false の相反期待）: 採択。共通関数は `userOverride ?? defaultExpanded` に統一し、回答の常時表示は「実回答 View が詳細用 Binding に依存しない」配線条件として rb で検査。
- HIGH2（task-47 の `AgentMessageBody(text:, bodyColor:)` 経路を拒否）: 採択。正常 fixture を契約 task-47 の経路にし、別ファイルへの原文・本文色転送まで追跡。
- HIGH3〜6（存在確認のみ・コメント内偽宣言・変更範囲未取得・typography 参照 1 個で代用）: 採択。実カードの引数・Binding getter/setter・表示ガードをモデル結果と対応づけ、宣言抽出はコード領域から、B46 からの実変更一覧で範囲外検出、フォント役割・倍率・余白・行間を別々に確認（`ChatScaledFont` 経由の転送を追う）。負例は 1 変更 1 期待エラー集合。
- HIGH7（環境変数なしでアサーション回避）: 採択。固定シナリオと状態アサーションは常時実行、ウィンドウ表示・操作待ちだけ環境変数で切替。
- HIGH8（目視ハーネスが更新・経路・条件を再現できない）: 採択。Observable なシナリオモデルと操作ボタンで同一 ID 更新・空白挟み再表示・開閉後終了を発生させ、単体経路・1 件グループ・51 件・501 行、幅 360/720・倍率 0.8/1.0/2.0・明暗を選べるようにし、composer と transcript に同じ設定を注入。
- MED9〜12: 採択（実 `FileChangeCell.visibleSections` の切り出し照合、selftest の単一違反分割、`viewModel.terminate()` の保証、基準不存在と git 障害の区別）。
