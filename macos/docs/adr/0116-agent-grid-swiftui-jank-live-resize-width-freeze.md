---
status: proposed
last-verified: 2026-07-24
---

# ADR-0116: エージェントグリッド（.appServer / SwiftUI）のカクつきは端末エンジンと別問題であり、live-resize 幅固定・窓縮小・行分離で対処する

## ステータス

提案中。本番 Release ビルド・実 9 セッションでの Instruments 実測により原因を確定し、Codex（gpt-5.6-terra, effort=high, read-only）の設計助言を反映した対処方針。実装は未着手。**ADR 0115（端末エンジンを off-main）とはスコープを分離する**——0115 は `.pty` 端末セッション向けであり、本 ADR が扱う `.appServer` エージェントグリッドのカクつきは 0115 では直らない。

## コンテキスト

### 問題

グリッドビューで複数の `.appServer`（構造化チャット）セッションを同時実行し、その複数が活発に出力しているときにアプリがカクつく。とりわけ **ウィンドウのリサイズ時に顕著**（幅を動かすだけで体感で明らかに固まる）。

### 描画経路の確定（`.pty` と `.appServer` で別系統）

- **`.pty`**（シェル・Claude Code / Cursor CLI）: PTY 出力 → SwiftTerm `feed()` / `draw()`（`TerminalView`）。**ADR 0115 の対象**。
- **`.appServer`**（Codex ネイティブ等の HTTP/WS 構造化イベント）: ネイティブ SwiftUI の `ChatTranscriptView` / `GridChatColumn`。**SwiftTerm を一切通らない**。駆動元は `@Observable` な `ChatSessionViewModel.transcript: [ChatItem]` の逐次更新。
  - 種別分岐は `ControllableSession`（`.pty(SessionViewModel)` / `.appServer(ChatSessionViewModel)`）、View 出し分けは `SessionGridView`。

根拠: **9 つの `.appServer` セッションを 3×3 グリッドで同時実行して os_signpost 計測したが、SwiftTerm の `feed`/`draw`（`com.phlox.perf`）は 1 件も発火せず**、`CoreAnimation Transaction.Commit` と `AppKit UpdateCycle` の停滞だけが観測された。

### 計測結果（本番アプリ・Release ビルド・実 9 セッション・Instruments）

**定常（9 セッション同時出力・50 秒・os_signpost）**
- `CoreAnimation Transaction.Commit` 停滞: p50 **15.6ms** / p95 22.6 / p99 26.1 / max 90.5ms（約 2489 回）
- `AppKit UpdateCycle` 停滞: p50 18.3 / p99 27.5 / max 90.5ms（1537 回）
- 停滞の中央値が既に 1 フレーム予算（16.7ms）を超過＝常時フレーム落ち。

**リサイズ（幅スイープ・18 秒・Time Profiler + potential-hangs）**
- メインスレッドのハング **17 件・合計 7.8 秒（約 43%）**、個々 470〜643ms（`Hang` / `Microhang`）。
- メインスレッド時間の内訳（スタック包含・重複可）:
  - **85.6% CoreText テキスト再 measure**（`CTLine` / `CTTypesetter` の行分割・行送り再計算）
  - 62.9% SwiftUI レイアウト（`UnaryLayoutEngine.sizeThatFits` / `placeChildren`）
  - 57.1% AttributeGraph の無効化・再計算
  - 21.3% AttributedString 生成
  - **0.1% Markdown パース（cmark）← リサイズでは無関係（キャッシュが効いている）**

### 因果（一本化）

リサイズ毎フレームで `contentMaxWidth` が変わり（`GridChatColumn.swift:14` の子 `GeometryReader` が `geo.size.width` から `:22` で算出して `ChatTranscriptView` の `.frame(maxWidth:)`（`ChatTranscriptView.swift:132`–`136`）へ渡す）、**非 Lazy な VStack**（`ChatTranscriptView.swift:147`–`163`）の最大 40 件（`TranscriptWindow.swift:25` `gridTileDefaultLimit=40`）× 9 タイル＝約 360 アイテムを CoreText で全再 typeset する。これが 470〜643ms ハングの主因。markdown 再パースは無関係。

定常側は `ChatSessionViewModel.applyStreamBatch`（`:1693`）が `transcript[index] = ...`（`:1700`/`:1703`/`:1706`）で単一要素を書き換えるが、`@Observable` の配列依存を通じて `ChatTranscriptView` 全体が無効化され、`ChatItemView` は Equatable でも `.equatable()` でもないため未変更行の body 再評価をスキップできない（毎回生成される `onRespondToUserQuestion` クロージャも差分不能の一因）。

### 既存 ADR の「非収束ループ」とは別レジーム

ADR 0030（非 Lazy 化・CPU 暴走根治）・0045（`fixedSize` 除去・リサイズ非収束ループ解消）・0010（描画中 `@Observable` 変更の再無効化ループ）は **「自走し続ける無限ループ」** への対処である。今回の実測は **「有界だが 1 回が数百 ms と高コスト」** な再 measure であり、別種の問題として扱う。したがって対処は既存ループ対策を壊さず（LazyVStack を再導入せず）に行う。

## 決定（対処方針・提案）

`.appServer` グリッドのカクつきは **SwiftUI / CoreAnimation 側で対処**する。ADR 0115（端末エンジン off-main）はこの問題を直さないため、0115 のスコープを `.pty` 端末セッションに限定する。対処は寄与順に:

1. **[リサイズ根治] live resize 中は整形幅を固定し、ドラッグ終了時に一度だけ反映する。** `maxWidth` を止めるだけ・幅バケットへの量子化だけでは、幅を縮めた時に親が子を再圧縮して再 typeset されるため不十分（Codex 指摘）。実際の提案幅（`.frame(width: heldWidth)`）を保持値で固定する。composer と transcript の整形幅は `ComposerLayout.transcriptContentMaxWidth` 契約に従い**同じ保持値**にし、リサイズ終了時に同時更新する。`fixedSize` は使わない（ADR 0045 の非収束を再発させない）。
2. **[即効・両方に効く] `TranscriptWindow.gridTileDefaultLimit` を 40 → 16 前後へ下げる。** ADR 0094 / 0051 の窓機構の延長。非 Lazy のまま、リサイズ時の測定対象と定常時に無効化される表示対象を約 60% 削減（9 タイルで最大 360 → 108〜144 件）。**LazyVStack は再導入しない**（ADR 0030 遵守）。一つだけ選ぶならこれ。ただし 1 無しにリサイズの 470〜643ms ハングは根治しない。
3. **[子 GeometryReader 除去] `GridChatColumn` の独自トップレベル `GeometryReader` を除去し、幅は親 `SessionGridView` から確定値で渡す。** 固定グリッドでは親が既に per-cell の `frame.width` を算出済み（`SessionGridView.swift:168` / `:178`）。AttributeGraph とレイアウト境界を減らす。1 と併用する整理。
4. **[定常根治] `ChatItemView`（と `CommandGroupCell`）を `item`/`isRunningCommand`/`agentDescriptor` に限定して Equatable 化＋`.equatable()`。** `ChatItem`・`AgentDescriptor` は既に Equatable。毎回生成の `onRespondToUserQuestion` クロージャは比較対象外にする。加えて **「確定行」と「ストリーミング中の 1 行」を分離**する: 確定 block 配列は追加・完了時のみ更新し、live 行は `@Observable` 参照型で本文だけ更新、親 `ChatTranscriptView` は live 行本文を読まない。`transcript` 自体は永続・ドメイン用に残し、表示専用 projection を別に持つ（移行リスク低減）。単に `[ChatItem]` をモデル配列に変えるだけでは、親が grouping や `TranscriptFollowSignal` 生成で全 `item` を読めば全行依存が残るため不十分。
5. **[後順位] MarkdownUI AST の局所キャッシュ。** 完了 block を固定し、未完了の末尾 block だけ再解析（境界は保守的に）。ただし MarkdownUI 2.4.1 に AST を注入できる公開 API があるか実装前に要確認。リサイズでは cmark 0.1% のため**定常向けの後順位**。補助的に `TranscriptStreamCoalescer`（`:38` `flushInterval=0.05`）を 3×3 表示時だけ 100〜150ms へ落とす余地があるが、上記の局所無効化後に計測して決める。

## 結果

**ポジティブ**
- リサイズ（470〜643ms ハング）と定常（Commit 停滞 p50 15.6ms）の**両方の実測ハングに構造的に効く**。
- 既存の窓機構（0051/0094）・coalescing（0093）・メモ化（0052）を壊さず延長できる。LazyVStack を使わないため 0030 の自走ループを再発させない。
- ADR 0115 と役割が分かれ、`.pty`（端末エンジン）と `.appServer`（SwiftUI）のどちらを優先すべきかを実測で判断できる。

**ネガティブ / 受容するコスト**
- `gridTileDefaultLimit` を下げると「以前のメッセージを表示」を押す頻度が増える。
- live resize 中は幅固定によりクリップされ得る（終了時に整う）。
- 確定/live 行分離は `ChatSessionViewModel` の transcript 更新経路の再設計を要する。
- 長期の TextKit 2 化（代替案 5）は MarkdownUI の見た目・コードブロックの操作部品・表・選択コピー・アクセシビリティを AppKit 側で再構成するコスト。

## 代替案

1. **端末エンジン off-main（ADR 0115）だけ** — 却下（本問題には無効）。`.appServer` は SwiftTerm を通らないため `feed`/`draw` の off-main 化は効かない。
2. **`contentMaxWidth` の量子化・デバウンスのみ** — 弱い。幅バケットごとに 360 件を再 measure する。Codex が否定。live resize 中の完全固定＋終了時一回反映を推奨。
3. **`(内容, 幅)` ごとの高さ/レイアウトキャッシュ** — 弱い。高さをキャッシュしても `Text` / MarkdownUI の行分割・描画測定は止まらない。SwiftUI の `Layout` キャッシュも子 `Text` の CoreText レイアウトを再利用しない。独自レンダラへ進む場合のみ意味。
4. **per-item を Canvas / CALayer に置換** — 高コスト。幅変更時の行分割は残る上、折返し・選択・リンク・コピー・コードブロック・表を自前再実装。
5. **長期本命: 1 タイル = 1 つの `NSTextView` / TextKit 2 ドキュメント**（表示済み段落のレイアウト/属性を保持し末尾だけ差分更新）— 最も筋が良い。LazyVStack を使わないので 0030 の anchor translation ループとは別系統。移行コストが大きいため、テキストのみの agent message から段階移行する。**別 ADR で扱う。**

## オープン課題

- live resize の開始/終了検知点（`NSWindow` の live-resize 通知か SwiftUI 側か）。
- `gridTileDefaultLimit` の最適値（16 は暫定。実測で確定する）。
- 確定/live 行分離で親が全 `item` を読む箇所（grouping・`TranscriptFollowSignal` 生成）の洗い出し。
- MarkdownUI 2.4.1 の AST 注入可否。
- 各対処後の再計測: 本 ADR の数値をベースラインに、hang 件数・`Commit` 停滞 p99・リサイズ内訳（CoreText 85.6%）の低減を確認する。

## 関連

- **スコープ分離元**: ADR 0115（端末エンジンを off-main = `.pty` 向け）
- 窓機構: 0051（末尾 N 件描画）, 0094（グリッド 40 件窓・hang timer の viewport 停止）
- 再無効化 / ループ教訓: 0030（非 Lazy 化）, 0045（`fixedSize` リサイズ非収束）, 0010（描画中 `@Observable` 変更）
- coalescing: 0093（ストリーミング delta のコアレシング）, メモ化: 0052（セル派生値の内容キー・メモ化）
- 実装アンカー: `ChatTranscriptView.swift:132`–`163`, `GridChatColumn.swift:14`/`:22`, `TranscriptWindow.swift:25`, `ChatSessionViewModel.swift:1693`–`1706`, `SessionGridView.swift:123`/`:168`/`:178`, `ComposerLayout.transcriptContentMaxWidth`
- 計測作業ログ: `macos/docs/delivery/0016-agent-grid-jank-measurement-worklog.md`
