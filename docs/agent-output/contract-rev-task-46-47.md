=== FILE: tasks/task-46.md ===
---
id: task-46
difficulty: standard
depends_on: [task-40]
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptItemPresentationTests.swift
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask46Tests.swift
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

=== FILE: tasks/task-47.md ===
---
id: task-47
difficulty: standard
depends_on: [task-46]
user_visible: true
acceptance_tests:
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/AcceptanceTranscriptMarkdownPresentationTests.swift
  - macos/Packages/SessionFeature/Tests/SessionFeatureTests/Acceptance/PMTranscriptVisualTask47Tests.swift
  - .claude/scripts/task47-wiring.rb
baseline_commit: "PM が凍結時に設定"
contract_tests: []
allowed_paths:
  - macos/Packages/SessionFeature/Sources/SessionFeature/TranscriptMarkdownPresentation.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatTranscriptFormatting.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/RichMarkdownView.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Basic.swift
  - macos/Packages/SessionFeature/Sources/SessionFeature/ChatMessageCells+Structured.swift
  - docs/agent-output/task-47.md
---

## 目的

UX-05 / P1 のうち、回答・思考文の Markdown を描画し、思考要約から装飾を除き、コード・コマンド・出力中の記号を保護する。未閉じ記法は本契約の有限規則だけで表示用に補正する。

仕様は `macos/docs/specs/ui-ux-improvement-backlog.md:100`。task-46 の表示分類・見出し・開閉・状態、task-40 の文字・余白を維持する。思考の展開本文は **Markdown 描画、body の文字体系、secondary 色**とする。

本書は敵対レビューと PM 裁定を反映した未凍結契約である。今回の改訂担当は read-only であり、ファイル保存、テスト作成・実行、ビルド、GUI 操作は行っていない。新規モデルと試験ファイルは実装予定の契約面である。

## 担当・依存・凍結

- 実装担当は Cursor。PM が Swift Testing、専用 Ruby、目視ハーネスを作成・凍結し、Cursor は変更しない。
- テストは `SessionFeatureTests` 内へ置き、App ターゲットへ追加しない。
- 契約、テスト、Ruby、検証スクリプト、台帳、目視ハーネス・記録、ADR は PM 所有であり、実装担当の `allowed_paths` 外とする。
- task-46 完了後の実コードを確認して凍結する。基準 B47 は task-46 の製品実装と task-47 の凍結テスト・Ruby・ハーネスを含み、`TranscriptMarkdownPresentation.swift` と task-47 の製品変更を含まない。
- B47 作成後に `baseline_commit` を実 SHA へ固定する。調査時 HEAD を自動採用しない。
- 未実装による RED、Ruby の `--selftest`、単一違反の検出、目視ハーネスの操作・撮影確認を凍結条件とする。新規 API 未定義によるコンパイル RED は区別して記録し、実装後の変異検査を必須とする。

### 分割しない理由と先行契約

思考要約と表示用補正は同じ `ReasoningSummaryView` の入口を共有し、コード保護と Markdown 本文への接続を同時に確認する必要がある。別契約へ分けると同じ入口の凍結が1回増えるため、PM 裁定により task-47 は分割しない。要約・補正・分割・配線のテストは独立した期待値を持たせ、片方の成功で他方の失敗を隠さない。

task-40 の Ruby 残余比較は task-40 完了時点の着手時範囲検査であり、後続変更へ適用しない。task-47 自身の Ruby で `TranscriptTypography` 参照の維持を検査する。

ADR 0147 の「見出しはコマンド」「補足は常に nil」「思考の見出しと本文が同一なら折り畳まない」は、task-46 が列挙した新決定へ置き換える。task-47 はその決定を維持する。後継 ADR の起草・関連文書反映は PM がフェーズ5で行う。

## 調査結果

以下の `SF/` は `macos/Packages/SessionFeature/Sources/SessionFeature/`。既存草案・敵対レビューの行番号を再利用しており、凍結時の位置ではない。

| 実ファイル・シンボル | 調査した挙動 |
|---|---|
| `SF/ChatMessageCells+Basic.swift:184`、`AgentMessageBody` | キャッシュの分割結果を通常初期化の `RichMarkdownView`／`CodeBlockView` へ渡す |
| `SF/RichMarkdownView.swift:14`・`:18` | 通常・`streaming:` の両初期化で入力をそのまま保持 |
| 同`:52` | Markdown テーマ本文色は primary 固定。外側の secondary 指定だけでは上書きを保証できない |
| `SF/ChatTranscriptFormatting.swift:10` | trim 後の3バッククォート接頭辞で開閉し、長さの対応を判定しない |
| 同`:18`・`:31` | Markdown 端の改行 trim と `.newlines` 分割があり、改行・空行保護の変更対象 |
| `SF/ChatMessageCells+Structured.swift:192` | 調査時の思考本文は `Text` 描画 |
| `SF/ChatMessageRenderCache.swift:66` | 入力文字列をキーとして分割結果を取得 |
| `AgentDomain/Sources/ChatRenderKit/ChatToolPresentation.swift` | `ChatReasoningPresentation` は `ThinkingRecap` に要約を委譲 |
| `AgentDomain/Sources/AgentDomain/ThinkingRecap.swift` | 見出し・末尾行抽出であり、本契約の Markdown／コード判定ではない |
| `DashboardFeature/Tests/DashboardFeatureTests/ChatTranscriptFormattingTests.swift` | 通常フェンスと、未閉じフェンスを Markdown へ戻す固定期待値 |

思考の直接 `Text` 経路と未閉じ入力の無補正経路は確認した。仕様画像の記号露出の原因、MarkdownUI の個別入力に対する実描画結果は本改訂では未検証であり、ライブラリの不具合と断定しない。

## 入出力契約

### 純粋な表示処理

`TranscriptMarkdownPresentation.swift` に次を置く。

```swift
enum TranscriptMarkdownPresentation {
    static func prepare(_ source: String) -> String
    static func summary(_ source: String) -> String?
}
```

同期的な純粋処理とし、毎回その入力から導出する。前回結果への追記、同じ文字数を根拠にした再利用、ViewModel・設定・I/O・時計への依存を追加しない。標準ライブラリ・Foundation・既存依存を使い、新規ライブラリやパッケージを追加しない。

### 改行と原文保護

- 表示処理と分割処理は CRLF／単独 CR を LF へ正規化してよい。本契約の CR を含む固定期待値は LF 正規化を採用する。
- それ以外のタブ、字下げ、行末空白、末尾空行は UTF-8 バイトを保持する。全文 trim やタブの空白展開をしない。
- 保存、エクスポート、メッセージ全文コピーは元の `ChatItem` 原文を維持する。表示用に正規化した文字列へ差し替えない。
- コードカードのコピーは、分割で抽出したコード本文と一致させる。CRLF／CR→LF の許容以外に字下げ・空行・記号を変えない。
- 以下の `\n`、`\r`、`\t` はそれぞれ実際の改行・CR・タブを表す。`\"` は文字列内の引用符である。

## `prepare` の有限規則

### 保護領域

閉じた／未閉じのバッククォート・チルダフェンス、インデントコード、インラインコードを先に識別し、その内部は補正しない。

- フェンスの開始は行頭の半角空白0〜3個の後に、同じ文字のバッククォートまたはチルダが3個以上。
- 終了は同じ文字種・開始以上の長さで、後ろが空白かタブだけの行。終了行も半角空白0〜3個を許す。
- 4空白またはタブ字下げのコード行を通常文章として補正しない。
- インラインコードは開始と同じ長さのバッククォート run で閉じる。短い内部 run を閉じとしない。未閉じのインライン開始以後も、その物理行末までは保守的に保護する。
- エスケープされた区切りを開始・終了として使わない。

### 補正対象

対象区切りは `**`、`*`、`__`、`_` の4種類。`~~`、リンク、括弧、見出し、任意の壊れた Markdown は修復しない。

1. 空行で区切った段落の**最終物理行**に開始があり、その行末まで閉じがない強調だけを対象にする。補正範囲は改行を跨がない。
2. 開始は行頭または空白・タブの直後。開始直後に空白でない本文文字が必要。識別子内部の `_`、演算子、単独の区切り run は対象外。
3. `**`／`__` を `*`／`_` より先に認識する。3個以上連続する同種 run は曖昧な入力として補正しない。
4. 同じ行の閉じた強調はそのまま保持する。閉じた強調の後に別の未閉じ強調があれば、後者だけを補正する。
5. 入れ子は最外の未閉じ強調だけを補正する。内側の未閉じ強調を再帰的に修復しない。既に閉じた最外強調の内部も再補正しない。
6. 閉じ記号を行末空白・タブの直前に補う。二重区切りの末尾に同種1文字の閉じ途中がある場合は、不足する1文字だけ補う。
7. 補正対象外は、許可した改行正規化を除いて入力不変。
8. `prepare(prepare(source)) == prepare(source)` を満たす。

旧草案の単独 `"**"` と `"## "` を空文字列へ変える規則は採用しない。本文のない区切りや見出しは有限な未閉じ強調補正の対象外とし、`prepare` では保持する。要約が空になるかは `summary` が別に判定する。

### 固定期待値

````text
prepare("**確認済み**")       == "**確認済み**"
prepare("## **確認結果**")    == "## **確認結果**"
prepare("**確認")             == "**確認**"
prepare("*確認")              == "*確認*"
prepare("__確認")             == "__確認__"
prepare("_確認")              == "_確認_"
prepare("説明 **確認")        == "説明 **確認**"
prepare("説明 *確認")         == "説明 *確認*"
prepare("説明 __確認")        == "説明 __確認__"
prepare("説明 _確認")         == "説明 _確認_"
prepare("**確認*")            == "**確認**"
prepare("__確認_")            == "__確認__"
prepare("**済み** と *確認")   == "**済み** と *確認*"
prepare("**外 *内")           == "**外 *内**"
prepare("**外 *内**")         == "**外 *内**"
prepare("**確認  \t")         == "**確認**  \t"

prepare("**確認\n次行")       == "**確認\n次行"
prepare("前行\n**確認")       == "前行\n**確認**"
prepare("**確認\n\n次段")     == "**確認**\n\n次段"
prepare("**確認\n\n")         == "**確認**\n\n"

prepare("**")                == "**"
prepare("*")                 == "*"
prepare("__")                == "__"
prepare("_")                 == "_"
prepare("## ")               == "## "
prepare("***確認")           == "***確認"
prepare("___確認")           == "___確認"
prepare("説明**確認")         == "説明**確認"
prepare("a * b")             == "a * b"
prepare("2 ** 3")            == "2 ** 3"
prepare("foo_bar")           == "foo_bar"
prepare("C#")                == "C#"
prepare("##tag")             == "##tag"
prepare("\\*\\*literal\\*\\*") == "\\*\\*literal\\*\\*"
prepare("~~未閉じ")          == "~~未閉じ"
prepare("[未閉じ](url")      == "[未閉じ](url"
prepare("`**未閉じ`")        == "`**未閉じ`"
prepare("`**未閉じ")         == "`**未閉じ"
prepare("    **未閉じ")      == "    **未閉じ"
prepare("\t**未閉じ")        == "\t**未閉じ"
prepare("```\n**未閉じ")     == "```\n**未閉じ"
prepare("~~~\n**未閉じ")     == "~~~\n**未閉じ"
prepare("説明\r\n**確認\r\n\r\n") == "説明\n**確認**\n\n"
````

正常な見出し・太字・斜体・箇条書き・引用・リンク・表は改行正規化を除いて入力不変とする。`"**確"` → `"**確認"` → `"**確認**"` の各原入力から結果を作り、同長の `"**確認"` → `"**更新"` では `"**更新**"` を返す。

## `summary` の候補と固定期待値

### 候補形式

1. コード領域を除き、ATX 見出しを優先する。半角空白0〜3個、`#` が1〜6個、その後に空白・タブまたは行末があるものを見出しとする。
2. 見出し末尾の閉じ `#` run は、直前に空白がある場合だけ装飾として除く。`##tag` は通常文章行、7個以上の `#` は見出しではない。
3. 最後の見出しから逆順に探し、装飾除去後に非空となる最初の見出しを使う。空の最終見出しから前の見出しへ遡る。
4. 有効な ATX 見出しがなければ、最後の通常段落の最後の非空文章行を使う。空になった候補は前の文章行へ遡る。
5. Setext 見出しは候補外。その本文行と下線行を一組として除外する。箇条書き・番号付きリスト・引用・表・水平線も候補外。各ブロックの継続行を通常文章へ混入させない。
6. 通常段落のインライン装飾は段落単位で解釈する。改行を跨ぐ完結した強調・リンクも解釈し、表示テキストの改行を保持した後で最後の非空文章行を選ぶ。リンク先内部の改行は表示テキストへ加えない。
7. 見出し記号、強調、取り消し線の装飾を除き、リンクは表示名を残す。エスケープは表示上の文字へ戻す。
8. インラインコードは区切りだけを除く。内部の `**`・`##`・短いバッククォート等は保持する。
9. 未閉じ強調は `prepare` の有限規則で補正できるものだけ補正してから解釈する。任意の記号を一括削除しない。
10. 候補の前後の空白を除き、装飾解釈後の Swift `Character` で先頭60文字へ制限する。61文字以上なら60文字の後に `…`。候補がなければ `nil`。
11. 入力原文を変更しない。思考要約にだけ使い、コマンド・診断・共通タイトルへ接続しない。

### 固定期待値

````text
summary("**確認済み**")                     == "確認済み"
summary("**確認")                           == "確認"
summary("# 一")                            == "一"
summary("## 二")                           == "二"
summary("### 三")                          == "三"
summary("#### 四")                         == "四"
summary("##### 五")                        == "五"
summary("###### 六")                       == "六"
summary("## **確認結果**")                 == "確認結果"
summary("## 前\n## 後\n本文")               == "後"
summary("## 有効\n## ")                    == "有効"
summary("## **有効**\n## ~~ ~~")            == "有効"
summary("本文\n## ")                       == "本文"
summary("## ")                            == nil
summary("## 確認 ###")                     == "確認"
summary("## C#")                           == "C#"
summary("##tag")                           == "##tag"
summary("####### 見出し外")                 == "####### 見出し外"

summary("一行目\n二行目")                   == "二行目"
summary("タイトル\n====")                   == nil
summary("残す\n\nタイトル\n----")           == "残す"
summary("- 項目")                          == nil
summary("1. 項目")                         == nil
summary("> 引用")                          == nil
summary("| A | B |\n| --- | --- |\n| x | y |") == nil
summary("本文\n\n- 項目")                  == "本文"
summary("本文\n\n> 引用")                  == "本文"
summary("## 見出し\n\n| A | B |\n| --- | --- |") == "見出し"

summary("**前\n後**")                       == "後"
summary("[前\n後](https://example.com)")    == "後"
summary("[詳細](\nhttps://example.com)")    == "詳細"
summary("[詳細](https://example.com/a#b)")  == "詳細"
summary("~~古い~~")                        == "古い"
summary("`**x** ## y`")                    == "**x** ## y"
summary("``a ` b **c**``")                 == "a ` b **c**"
summary("\\*literal\\*")                   == "*literal*"

summary("```\n## コード\n```")             == nil
summary("```\n**未閉じ")                   == nil
summary("~~~\n## コード\n~~~")             == nil
summary("    ## コード")                   == nil
summary("\t## コード")                     == nil
summary("文章\n\n```\n## コード\n```")       == "文章"
summary("")                               == nil
summary(" \t\n")                          == nil
````

60文字境界は ASCII だけで済ませない。PM は次の6個のリテラル文字列を連結した60 `Character` の入力・同一期待値を試験へ固定し、末尾に `"追"` を足した61文字の期待値を同じ60文字＋`"…"` として固定する。

```text
"あいうえおかきくけこ"
"さしすせそたちつてと"
"なにぬねのはひふへほ"
"まみむめもやゆよわを"
"0123456789"
"Ae\u{301}👨‍👩‍👧‍👦BCDEFGH"
```

結合文字 `e\u{301}` と家族絵文字をそれぞれ1 `Character` として数え、Unicode 正規化で原文表現を変更しない。期待値を製品の切り詰め関数から作らない。

## フェンス分割とコード保護

`ChatMarkdownFormatter.splitFencedCodeBlocks` と `ChatMarkdownBlock` の既存 API を維持する。

- バッククォートフェンスは文字種・長さを記録して分割する。短い終了候補、別文字種、後ろに文字がある候補では閉じない。
- バッククォート開始行の情報文字列にバッククォートが含まれる場合、その行を開始フェンスとして扱わない。
- チルダフェンスは独自の `.code` へ分割せず、まとまった `.markdown` として MarkdownUI へ渡す。内部のバッククォートを別の開始と解釈しない。
- 0〜3空白の開始・終了を許し、4空白／タブ字下げはインデントコードとして `.markdown` に残す。
- `.code.text` は開始行と終了行の間の本文行を LF で連結した値。開始・終了フェンス行は含めない。本文の字下げ・タブ・行末空白・空行を trim しない。
- 開始／終了行を分ける改行はフェンス構造の区切りである。本文中の空行に対応する改行は保持する。
- `.markdown` に残るコードは、その字下げ・末尾空行を保持する。
- 未閉じバッククォートフェンスを `.markdown` へ戻す既存契約を維持する。3本・字下げなしの既存言語表記の正規化だけを互換例外とする。
- 3空白字下げ、4本以上、チルダの未閉じ開始行を、3本・字下げなしへ書き換えない。
- 分割後の未閉じ `.markdown` も `prepare`／`summary` がコードとして保護する。

以下で `M(s)` は `.markdown(s)`、`C(lang,s)` は `.code(language: lang, text: s)` を表す。テストでは実 enum 値との等値比較と本文 UTF-8 比較を行う。

````text
split("Before\n```json\n{\"ok\": true}\n```\nAfter")
== [M("Before"), C("json","{\"ok\": true}"), M("After")]

split("Before\n```json\n{\"ok\": true}")
== [M("Before"), M("``` json\n{\"ok\": true}")]

split("```swift\n\t  **x  \n\n```")
== [C("swift","\t  **x  \n")]

split("   ```swift\n\t  **x  \n\n   ```")
== [C("swift","\t  **x  \n")]

split("    ```swift\n    **x  \n\n    ```\n\n")
== [M("    ```swift\n    **x  \n\n    ```\n\n")]

split("\t```swift\n\t**x\n\t```\n\n")
== [M("\t```swift\n\t**x\n\t```\n\n")]

split("```swift\r\n\t  x  \r\n\r\n```")
== [C("swift","\t  x  \n")]

split("```swift\r\t  x  \r\r```")
== [C("swift","\t  x  \n")]

split("```json\n**x\n\n")
== [M("``` json\n**x\n\n")]

split("   ```json\n  **x\n\n")
== [M("   ```json\n  **x\n\n")]

split("````json\n```\n**x\n\n")
== [M("````json\n```\n**x\n\n")]

split("````\na\n```\nb\n````")
== [C(nil,"a\n```\nb")]

split("```\na\n~~~\nb\n```")
== [C(nil,"a\n~~~\nb")]

split("```\na\n```text\nb\n```")
== [C(nil,"a\n```text\nb")]

split("```\na\n````")
== [C(nil,"a")]

split("```\na\n    ```\nb\n```")
== [C(nil,"a\n    ```\nb")]

split("~~~\n```\n**x\n~~~\n\n")
== [M("~~~\n```\n**x\n~~~\n\n")]

split("~~~\n**x\n\n")
== [M("~~~\n**x\n\n")]

split("本文\r\n\r\n")
== [M("本文\n\n")]
````

0空白と3空白フェンスの `.code.text` とコピー対象は、どちらもリテラル `"\t  **x  \n"`。4空白・タブの例は `prepare` へ渡しても改行正規化以外に不変、`summary` は `nil`。

既存未閉じフェンス期待値を変更して検査を通さない。末尾空行を含む追加期待値は既存の不足を補うものであり、コード本文の trim を互換仕様として固定しない。

## 実 View と本文色の配線

### 回答

- `AgentMessageBody` → `ChatMessageRenderCache.markdownBlocks` → `RichMarkdownView`／`CodeBlockView` の経路を維持する。
- 補正は `RichMarkdownView` の通常・`streaming:` 両入口へ接続し、戻り値が実際の `Markdown` 入力へ届くようにする。
- `AgentMessageBody` に本文色を表す限定引数を追加する。既定は primary で、既存の `AgentMessageBody(text:)` 呼び出しを維持する。
- Markdown ブロックへ本文色を渡す。コードブロック、コピー値、キャッシュキー、分割元入力は変更しない。

### 思考

- task-46 完了後の `ReasoningSummaryView` で `summary(text)` を補足へ渡す。
- 展開本文へ要約ではなく原文 `text` 全体を渡し、secondary 本文色を指定した `AgentMessageBody` で描画する。
- 短文も同じ経路。生の `Text` へ逃がす分岐を残さない。
- 要約 `nil` の非空コード思考も「思考の詳細」を表示し、展開本文へ到達できる。
- task-46 の既定閉・見出し・空判定・開閉保持を維持する。保持は同じセルが表示階層に残る更新だけ。非空・開 → 空白 → 非空では再表示時に閉じる。

### `RichMarkdownView` の限定変更

本文色は primary／secondary の2役割に限定し、既存引数を省略できる既定値を持たせる。任意テーマ設定や新規ユーザー設定へ広げない。

- 通常・`streaming:` の両初期化、テーマ生成、テーマキャッシュキーへ本文色の役割を渡す。
- 同じ theme ID・倍率でも primary と secondary のキャッシュを混同しない。
- `.text` の通常本文色と、primary を固定していた見出し色へ渡す。思考の見出しも secondary 系の本文色として描画する。
- body のサイズ、見出しのサイズ・ウェイト、`TranscriptTypography` の行間・余白を維持する。
- リンク、インラインコード、コードブロック、引用帯、コピー操作の専用色・処理は既存を維持する。思考の secondary 指定で構文ハイライトを一括上書きしない。
- 外側の `.foregroundStyle(.secondary)` だけで内部 primary 指定を残す実装は不合格。

`prepare`／`summary` をコマンド、出力、差分、エラー診断、ユーザー本文へ接続しない。`ThinkingRecap`／`ChatReasoningPresentation` の共有実装は変更しない。

## 変更境界と不変条件

- `ChatMessageCells+Basic.swift` は `AgentMessageBody` の本文色引数と Markdown ブロックへの転送だけを変更する。他のセル・コピー・コード分岐は保護する。
- `ChatMessageCells+Structured.swift` は `ReasoningSummaryView` の要約式、本文 Markdown 接続、本文色転送、不要な局所変数の除去だけを変更する。
- 同ファイルのコマンド、差分、サブエージェント、処理中、経過、無応答、中断の宣言は変更しない。
- `RichMarkdownView` は補正入口と本文色の限定配線を変更し、リンク処理、折り返し保護、キャッシュの既存性質、コードコピーを保持する。
- 表・表セルへ `fixedSize` を追加しない。非表本文・見出し・箇条書きの折り返し高さ保護を削除しない。
- ID、順序、表示窓、描画予算、スクロール追従、既存キャッシュキーを保持する。
- コマンド50件・出力20行・差分500行の追加表示と、質問・承認・中断・移動を保持する。
- 保存、エクスポート、クライアント、起動・復元、パッケージ依存を変更しない。
- 描画中の状態更新、`LazyVStack`、非同期ハイライト、無制限キャッシュ、製品用デモモードを追加しない。

task-46 との交差は Basic と Structured の2ファイルであり、依存順で逐次化する。ファイル全体を比較対象から外さず、上記構造だけを変更可能にする。

## 受け入れテスト

### Swift Testing

PM は本契約の `prepare`、`summary`、分割結果を独立したリテラル期待値として凍結する。製品処理の出力から期待値を生成しない。

加えて次を検査する。

- 補正対象4区切り、対象外、部分閉じ、改行境界、閉じた強調との混在、最外だけの補正。
- 固定入力に対する冪等性と元入力の不変。
- 見出しの遡及、候補外ブロック、複数行インライン装飾、60／61 `Character`。
- 分割後の `.markdown` を `prepare` へ渡しても、未閉じコードの内部を補正しない。
- コード本文・コードコピー対象の UTF-8、CRLF／CR 正規化、タブ・字下げ・末尾空行。
- `ChatMessageRenderCache.markdownBlocks` へ同長別内容を渡しても取り違えない。
- 同じ theme ID・倍率に対する primary／secondary のテーマキャッシュキーは異なる。同じ役割の再呼び出しは同じキー。
- 明暗・倍率変更でも本文色の役割を維持する。キーの不一致だけを色の実描画確認と読み替えない。
- task-46 の分類・コマンド表・開閉テストを恒久回帰として再実行する。

### Ruby：固定 SHA・着手時範囲・恒久回帰

PM が `.claude/scripts/task47-wiring.rb` を作成する。task-41 と同じ二段階方式にし、task-46 の Ruby へ task-47 固有検査を混在させない。

**常時実行する凍結検査：**

- `TASK47_BASELINE` は明示 SHA 必須。契約の `baseline_commit` と完全 SHA で一致し、現在の履歴の祖先であること。
- 未設定、プレースホルダ、`HEAD`、`HEAD~1`、`@`、ブランチ名、無効コミット、非祖先を拒否する。
- B47 に task-46 完了状態があり、`TranscriptMarkdownPresentation.swift` が存在しないこと。確認対象は PM が凍結時に固定する。
- `acceptance_tests` の Swift・ハーネス・Ruby 自身を B47 の blob とバイト比較する。
- blob 取得失敗、必要ファイル不在、解析不能は非ゼロ終了。新規製品ファイル不存在と Git 障害を区別する。
- 明示 SHA と実装前 HEAD の一致は許す。実装後 HEAD への差し替え、HEAD 自己比較、HEAD へのフォールバックは禁止する。

**`TASK47_SCOPE_CHECK=1` のときだけ実行する着手時の変更範囲検査：**

- B47 からの変更が許可ファイルと上記の限定構造内であること。
- Structured の他宣言、Basic の `AgentMessageBody` 以外、共通操作等を B47 の blob と比較する。
- RichMarkdownView の許可した入口・本文色・キャッシュキー以外を構造単位で保護する。
- task-47 の実装・完了時だけ実行し、後続タスクの通常回帰へ持ち込まない。

**環境変数なし／`TASK47_SCOPE_CHECK=0` の恒久回帰検査：**

- 回答の通常・`streaming:` 両入口で `prepare` の戻り値が `Markdown` へ届く。
- 思考の補足へ `summary(text)`、本文へ原文全体が届く。
- 思考本文色が `AgentMessageBody` → `RichMarkdownView` → テーマまで secondary として届く。
- 回答の既定 primary、色役割を含むキャッシュキー、コード・リンクの専用処理が維持される。
- 短文の直接 `Text`、要約だけの本文、`nil` 要約による非空思考の非表示を拒否する。
- コード、コマンド、出力、差分、診断、コピー原文への補正流入を拒否する。
- task-46 の空判定・見出し・開閉・状態配線を維持する。
- `TranscriptTypography` の実フォント・余白・行間参照を維持する。文字列や未使用参照だけでは合格にしない。
- リンク・非表折り返し保護・コピー等の恒久不変部分を B47 の構造単位の blob 比較で保護する。着手時の全面残余比較を混在させない。

コメント・文字列中の名前、未使用関数、`if false`、結果を捨てる呼び出しを接続と認めない。正規化はコメントと文字列外空白に限定し、文字列内容・補間内の実コードを消さない。

`--selftest` は実ファイルを変えず本番検査関数を使い、正常 fixture と次の単一違反 fixture の期待エラー集合を照合する。

- 通常入口／streaming 入口未接続、補正結果未使用、短文直接表示、要約だけの本文。
- secondary 転送欠落、テーマ本文 primary 固定、色役割のキャッシュキー欠落、回答既定色の変更。
- コードへの補正、コピー変更、開閉リセット、空判定変更、保護宣言変更、typography 退行。
- 凍結 Swift・ハーネス・Ruby 改変、基準不正・不一致・非祖先・実装済み基準・blob 取得失敗。
- scope だけの範囲違反は `1` で失敗し、恒久契約を守った変更なら scope なしで成功する。
- 恒久契約違反は scope の有無にかかわらず失敗する。

必要な負例をスキップしない。

## 品質ゲート

正本は `.claude/verify.sh` と `macos/scripts/run-swift-tests.sh`。調査した verify は8パッケージ、更新隔離検査、差分の空白検査を実行する。PM が task-47 検査と task-46 恒久回帰を接続する。

task-46 の回帰では `TASK46_SCOPE_CHECK=0`、task-40 の着手時残余比較は実行しない。

以下は実装時の手順であり、本改訂では未実行。

```sh
~/.agents/scripts/compact-test task47-selftest ruby .claude/scripts/task47-wiring.rb --selftest
~/.agents/scripts/compact-test task47-scope env TASK47_BASELINE=<B47> TASK47_SCOPE_CHECK=1 ruby .claude/scripts/task47-wiring.rb
~/.agents/scripts/compact-test task47-regression env TASK47_BASELINE=<B47> TASK47_SCOPE_CHECK=0 ruby .claude/scripts/task47-wiring.rb
~/.agents/scripts/compact-test task47-task46-regression env TASK46_BASELINE=<B46> TASK46_SCOPE_CHECK=0 ruby .claude/scripts/task46-wiring.rb
~/.agents/scripts/compact-test task47-integration bash .claude/verify.sh
```

App ビルドは `macos` ディレクトリで実行する。

```sh
~/.agents/scripts/compact-test task47-app-build xcodebuild -scheme Phlox -configuration Debug -derivedDataPath <専用の絶対パス> -destination platform=macOS build
```

PM は凍結前にパッケージ・App・検証・lint・型チェック・静的解析設定を再確認する。既存 `ChatTranscriptFormattingTests` を維持する。先行検査と許可変更が衝突した場合は PM が検査の責務を修正して再凍結し、Cursor に期待値の弱体化を行わせない。

Swift テスト、Ruby、ビルド、目視を区別し、警告・失敗・未設定・実行不能・未検証を記録する。

## 課金なしの PM 目視ゲート

実 claude／codex／cursor の起動・送信・課金セッションを要求しない。

### ハーネスと凍結前の実行確認

PM は `PMTranscriptVisualTask47Tests.swift` を作成する。task-46 のハーネスを参照・再利用できるが、task-46 の凍結済みテストは変更しない。

- `SessionFeatureTests` 内の Swift Testing、`NSWindow`、`NSHostingView` を使い、製品へテスト用モード・setter を追加しない。
- `StructuredAgentClient` の double と `AsyncStream<NormalizedChatEvent>` を VM へ注入し、公開開始経路で購読を開始する。
- `.turnStarted`／`.turnCompleted(nativeSessionId: nil)` を注入し、実 `status.isRunning` の true→false を確認する。
- 追記は実イベント、同長置換・空白置換は安定したハーネスモデルの transcript 更新で再現してよい。後者も実行状態は VM のイベント経路を使う。
- 同一 ID 更新中は VM・ホスト・ルート identity を保持する。ホスト再生成で開閉保持を検査したことにしない。
- 専用 `UserDefaults(suiteName:)` にテーマ・倍率キーを設定し、`.defaultAppStorage(suite)` をルートへ注入する。明暗 appearance も設定する。
- `ComposerLayout.transcriptContentMaxWidth(mainColumnWidth:)` と製品相当のコンポーザ高さによる `bottomScrollContentMargin` を使い、末尾まで操作する。
- 同じ画面に primary の回答と secondary の思考本文を並べ、同じテーマ・倍率でキャッシュが混同されないことを確認する。
- PM が凍結前に起動コマンド、操作可能なウィンドウ、イベント遷移、同一 ID 更新、AppStorage 反映、スクリーンショット保存、終了処理を実行確認する。旧表示の不足は不足として記録する。

通常実行では固定シナリオを自動検査して終了する。`PHLOX_PM_VISUAL_TASK=47` では操作用ウィンドウを保持し、PM のハーネス終了操作で閉じる。環境変数はテスト専用とし、受け入れアサーションをスキップしない。

```sh
~/.agents/scripts/compact-test task47-pm-visual env PHLOX_PM_VISUAL_TASK=47 bash macos/scripts/run-swift-tests.sh SessionFeature
```

### 実装後の確認

- 見出し・太字・斜体・箇条書き・リンク・引用・表を含む回答。
- `"**確"` → `"**確認"` → `"**確認**"` と同長別内容への置換。
- 4種類の未閉じ強調、改行を跨ぐ対象外、最外だけの補正。
- 空の最終見出しから前の見出しへ遡る思考要約。
- 短文・長文思考の既定閉、装飾除去済み要約、展開本文の Markdown と secondary 色。
- 要約 `nil` のコードだけの思考を開いて全文へ到達。
- 同一 ID・表示継続中の開閉保持と、空白を挟む再表示時の既定閉。
- 0／3／4空白、タブ、3／4バッククォート、チルダ、未閉じ、インライン、CRLF／CR、末尾空行のコード。
- コード・コマンド・出力・診断中の `**`・`##`・パス・演算子と、コピー原文。
- task-46 の単体／1件グループの差、件数、最新／過去の実行中補足。

幅360／720pt × 倍率0.8／1.0／2.0 × 明暗テーマで、重なり・切れ・操作不能を確認する。正常な Markdown の装飾記号が不意に露出する、コード記号・空白が欠落する、コピー原文が変わる、更新後に旧内容が残る、思考本文が primary になる場合は不合格。

復元失敗プレースホルダは実 App の到達性・エラー表示の補助証拠に限る。回答・思考 Markdown・状態遷移の検証へ読み替えない。

PM は `docs/agent-output/visual-task-47.md` にコミット、起動コマンド、入力・イベント、ID、幅、末尾余白、倍率、テーマ、操作、画像、合否、未検証項目を残す。必要な表示を再現できなければ目視ゲート未達とし、課金セッションで代替しない。

終了時はホスト、stream、VM 購読を閉じ、専用 defaults suite を清掃する。作業で起動したプロセスの親子関係を確認し、不要なものだけ終了して `ps` で残存確認する。リリース版・共有プロセスは停止しない。

## レビュー観点と完了条件

- 補正・要約・分割それぞれが有限規則と独立した固定期待値を満たす。
- 正常な Markdown と、コード・コピー原文を保護する。
- 改行正規化と、タブ・字下げ・末尾空行の保持を区別する。
- 通常／streaming の両入口、思考要約、原文本文へ接続されている。
- secondary が本文色引数・テーマ・キャッシュまで届き、回答は primary を維持する。
- task-46 の分類・見出し・開閉・状態と task-40 の文字体系を維持する。
- scope 検査と恒久回帰が分離され、凍結 blob と単一違反 selftest が機能する。
- 凍結テストを実装担当が変更せず、必須品質ゲート・独立レビュー・課金なし PM 目視が成立する。
- 未検証・失敗・警告を記録し、PM がフェーズ5で ADR 0147 の後継決定と関連仕様を反映する。

旧単一草案を第三の実装契約として併用しない。UX-05 の完了には task-46・task-47 の検査、独立レビュー、PM 目視、フェーズ5の文書反映を必要とする。