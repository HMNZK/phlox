---
status: accepted
last-verified: 2026-07-31
---

# ADR 0145: ツール実行グループの見出しを recap にし、開閉トグルを右端へ移す

> **このファイルの役割**: 固定文字列「ツール実行 ×N」を動的な recap へ置き換えた理由と、
> 毎秒更新を再描画コストに巻き込まないための配線。
> **書かないもの**: カードの装飾を落とした判断（→ [ADR 0144](0144-quiet-chat-chrome.md)）、
> recap 文字列そのものの導出規則（→ `ChatRecap` / `ThinkingRecap` の実装）、
> ブロック再評価の抑制（→ [ADR 0116](0116-transcript-block-equatable.md)）。

> **後継**（2026-07-31・[ADR 0147](0147-chat-code-card-and-header-dedup.md)）: 実機で使った結果、次の 3 決定を**覆した**。
> ①**完了形ラベル**（`… を実行` / `を読み込み` / `を編集`）をやめ、`CommandGroupTitle.derive(items:)` は
> **コマンド原文**（空白正規化＋`ThinkingRecap.clamp`）を返す。`RecapActivity` による分類は言い換えで情報が減るため。
> ②**`liveRecap` クロージャと `TimelineView` 追従を廃止**（`items` が変われば `Equatable` 経由で追従するため不要）。
> 未使用になった `ChatRecap.derive` / `ChatSessionViewModel.recap(now:)` は削除（`deriveActivityState` は残存）。
> ③**件数サブタイトル `実行中 ×N` / `×N` を廃止**（常に `nil`）。`×1` は情報量ゼロ、`実行中` は orb と重複。
> フォールバック `"ツール実行 ×N"`（コマンドが 1 件も無いグループ）と、シェブロンを自前で置く方針は不変。
> ただしシェブロンの位置は**右端 → タイトル直後**（`AGENTS.md >`）へ変更した。
> **60 文字クランプの共有・`.contentShape(Rectangle())`・`Equatable` を壊さないこと・
> 出力 20 行省略とコピー全文は不変**で、ADR 0147 がこれを引き継ぐ。

## 文脈

連続するツール実行は 1 つの `commandGroup` ブロックへ畳まれ、その見出しは
`"ツール実行 ×\(items.count)"` の固定文字列だった。件数は分かるが**何をしているかが一切読めない**。
一方、実行中ターンの recap（「`swift test` を実行中」等）は `ThinkingIndicatorCell` の下、
transcript 最下部にだけ出ていた。つまり「情報がある場所」と「目が行く場所」がずれていた。

さらに開閉シェブロンは `DisclosureGroup` 既定の左端にあり、行の先頭が装飾で埋まっていた。

## 決定

**見出しを recap にし、件数はサブタイトルへ、トグルは右端へ移す。**

- **タイトルの決定規則を純粋関数 `CommandGroupTitle.derive(items:isRunning:liveRecap:)` に集約する。**
  1. 実行中かつ live recap があれば、それをそのまま出す（時間追従）
  2. なければ最後の `.commandExecution` のコマンドを `RecapActivity.fromCommand` で分類し、**完了形**の
     ラベルにする（「… を実行」「… を読み込み」「… を編集」）
  3. コマンドが 1 件も無ければ従来の `"ツール実行 ×N"` へフォールバックする
- **recap の描画場所は 1 箇所にする。** `ThinkingIndicatorCell` の recap 行は削除した。同じ文字列が
  2 箇所に出ると視線が割れる。生成元（`ChatSessionViewModel.recap(now:)` → `ChatRecap.derive`）は
  そのまま残し、実行中の最新グループにだけクロージャを渡す。
- **60 文字クランプは `ThinkingRecap.clamp` として公開し共有する。** 最初の実装は
  「クランプ規則の再利用」を `ThinkingRecap.summary` 丸ごとの呼び出しで済ませており、`summary` 内の
  見出し抽出・最終行抽出が効いて**複数行コマンドのタイトルが末尾断片に化けていた**
  （`cd macos && swift build \⏎ --configuration release` → `--configuration release を読み込み`）。
  独立レビューが実測で検出した。正しくは、コマンドの改行と連続空白を単一スペースへ畳み、
  ラベル**全体**に clamp を適用する。
- **件数はサブタイトルへ移す**（実行中は `"実行中 ×N"`、完了時は `"×N"`）。見出しを recap に譲っても
  「何件走ったか」は読めるままにする。
- **トグルは自前のシェブロンをヘッダ右端（時刻の右）に置く。** `DisclosureGroup` 既定のシェブロンは隠す。
  ラベル `HStack` に `.contentShape(Rectangle())` を付けないと `Spacer` の空白帯がクリックに反応しないため、
  ヘッダ全体をクリック領域にするにはこれが要る。
- **展開時は 2 段構成にする。** 「`$ コマンド`」（等幅・primary）＋その下に出力（等幅・secondary）。
  出力が空の行には出力ブロックを描かない。出力は 20 行で省略し「さらに N 行を表示」で全文へ展開でき、
  **コピーは省略中でも元の出力全文**を返す。
- **毎秒更新を再描画に巻き込まない。** `CommandGroupCell.==`（ADR 0116）にクロージャを含めると
  常に不一致になり全グループが再評価される。live 追従はタイトル `Text` を `TimelineView` で包んで実現し、
  クロージャは比較対象から外す。`TimelineView` は親 body の再評価に依存せず自分のスケジュールで動くため、
  `Equatable` によるスキップと両立する。viewport 判定も**実行中グループにだけ**効かせ、
  非実行中グループがスクロールのたびに再評価されないようにした。

## 結果

- 実行中は「いま何をしているか」が、完了後は「最後に何をしたか」がヘッダから読める。
  サブエージェントのドロワーも同じヘッダ実装になる（live recap は渡らないので規則 2・3 で決まる）。
- 既存の凍結受け入れテストの `"ツール実行 ×N"` アサーションは、**フォールバック規則**
  （コマンドが 1 件も無いグループ）を検証する形へ PM が更新した。件数の保証は捨てていない。
- `CommandGroupOutputDisplay` の行分割は init で 1 回だけ行う。計算プロパティのままだと
  body 1 回につき出力を 4 回 split し、20000 行で 35ms → 8.9ms の差が出た（レビュアー実測）。
- 回帰保護: `AcceptanceCommandGroupRecapHeaderTests`（3 分岐・複数行コマンド・クランプ・決定論）、
  `TranscriptCellEquatableWhiteboxTests`（非実行中グループが viewport 変化で unequal にならない）。
