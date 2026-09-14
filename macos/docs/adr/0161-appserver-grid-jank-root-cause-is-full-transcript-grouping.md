---
status: active
last-verified: 2026-08-04
---

# ADR-0161: `.appServer` グリッドのカクつきの主因は transcript 全件の再グルーピングであり、ADR 0116 の対処1・2・4 では改善しない

## ステータス

採択（再計測による判定）。**ADR 0116 を supersede する**。0116 の「`.appServer` のカクつきは SwiftUI 側の問題であり ADR 0115（端末エンジン off-main）では直らない」というスコープ判断は維持するが、**因果の特定と対処の優先順位を差し替える**。本 ADR の対処は未実装。

## コンテキスト

### なぜ再計測したか

ADR 0116 の対処1（live-resize 中の整形幅凍結）・対処2（`gridTileDefaultLimit` 40→16）・対処4（`ChatItemView` の Equatable 化）は 2026-07-24 に実装された（commit `a6dcbbe` / `0b4f649` / `8f1dd77`）。しかし**実装後の値は一度も計測されておらず**、0116 に載っている「リサイズ時 470〜643ms ハング」「定常 Commit 停滞 p50 15.6ms」は**修正前のベースライン**のままだった。この値を現況として引用した誤りが起点。

### 計測方法（課金なしのローカル再現）

実エージェントを起動せずに「9 セッションが活発に出力している」条件を作った。`.appServer` + `kind: claudeCode` は `claude` CLI を `-p --input-format stream-json --output-format stream-json` で起動し、stdin/stdout の NDJSON で通信する（`ClaudeChatClient+Respawn.swift` の `buildArguments` / `LineDelimitedProcessTransport`）。そこで **`claude` と同名の合成ストリーム生成器**を用意し、`ZDOTDIR` 経由で login shell の PATH 先頭に差し込んだ（`BinaryPathResolver.resolvePathEnvironment()` が `/bin/zsh -l -c` の PATH を使うため）。API 呼び出しは 1 回も発生しない。

- 合成ストリーム: 1 セッションあたり約 40 delta/秒（25ms ± 30%）、1 メッセージ 80 delta で `message.id` を更新。本文は Markdown（見出し・箇条書き・コードブロック）混在。
- 実データ: 実セッション 9 本のトランスクリプト（計測開始時 9 本合計 7,653 / 7,883 items ＝ 1 セッション約 850 items）。全タイルが 16 件の表示窓を飽和。
- ウィンドウ 1040×1288、3〜4 列グリッドで 9 タイル同時表示。Release ビルド、`xctrace --template 'Time Profiler'`、指標は `potential-hangs`。
- **A/B**: A = 現行 HEAD（対処1・2・4 入り）、B = 対処1・2・4 だけを戻した同一 Release ビルド。同一のフィクスチャ複製・同一ウィンドウ寸法・同一手順。

### 計測結果

**定常（9 セッション同時出力・50 秒・無操作）**

| ビルド | 実行 | ハング件数 | 合計時間（50 秒中） | 中央値 | 最大 |
|---|---|---|---|---|---|
| A（対処1・2・4 あり） | 4 回 | 50〜63 | 36.4〜40.7s（**73〜81%**） | 381〜488ms | 2.41〜2.68s |
| B（対処1・2・4 なし） | 3 回 | 44〜49 | 35.1〜36.4s（**70〜73%**） | 411〜459ms | 2.39〜2.73s |

**リサイズ（実マウスドラッグ 8.5 秒を含む 40 秒）**

| ビルド | ハング件数 | 合計時間 | 中央値 | 最大 |
|---|---|---|---|---|
| A | 44 | 26.0s（65%） | 356ms | 2.15s |
| B | 34 | 26.7s（67%） | 455ms | 2.76s |

**アイドル（出力なし）でのリサイズ**: A・B とも `potential-hangs` 0 件・`hang-risks` 0 件。

メインスレッドは定常 50 秒中 50,517 サンプル稼働（≒101%）＝常時飽和。自己時間の最上位でも 1.1% で、単一のホットスポットは存在しない（AttributeGraph・SwiftUI 更新機構に薄く分散）。

### ここから言えること

1. **カクつきは現存する。** 文書の値（470〜643ms）より深刻で、リサイズ時だけでなく**定常で記録時間の 7〜8 割**を占める。
2. **対処1・2・4 に測定可能な改善はない。** B の反復ばらつき（70/73/70%）より A・B 差が小さく、A はむしろ悪い側に寄る。
3. **リサイズは主因ではない。** アイドル時のドラッグは 0 件で、ハングは「出力中であること」に随伴する。0116 の「リサイズ毎フレームの CoreText 再 typeset が 85.6%」という内訳は今回再現しなかった。

### 因果（差し替え）

`ChatTranscriptView` は表示窓（16 件）を**グルーピングの後段**でしか適用していない。

- `ChatTranscriptView.swift:336` — `transcriptItems` は `viewModel.transcript` を**全件**返す
- `ChatTranscriptView.swift:168` — `ChatTranscriptGrouping.blocks(from: items)` がその**全件**を走査する
- `ChatTranscriptView.swift:169` — `renderBlockLimit(for: blocks)` はその後で 16 件へ絞る

`TranscriptStreamCoalescer` の `flushInterval` は 0.05 秒（`TranscriptStreamCoalescer.swift:38`）なので、**1 セッションあたり約 850 items の全件走査が、9 タイル × 20 回/秒**で回る。`@Observable` の配列依存により 1 行の更新で `ChatTranscriptView` 全体が無効化されるため、対処4 の `.equatable()`（`ChatTranscriptView.swift:280`/`:287`）はセル本体の再評価は抑えても、この**親側の全件走査は抑えない**。対処2 で `gridTileDefaultLimit` を 40→16 にしても（`TranscriptWindow.swift:29`）、減るのは「描画する数」であって「走査する数」ではない。

これは 0116 自身が対処4 の注記で「単に `[ChatItem]` をモデル配列に変えるだけでは、親が grouping や `TranscriptFollowSignal` 生成で全 `item` を読めば全行依存が残るため不十分」と書いていた状態が、そのまま残っているということである。

## 決定

1. **[根治] 表示窓をグルーピングの前段へ移す。** `blocks(from:)` へ渡す配列を、窓で切った末尾スライスにする。走査母数を「全 items」から「窓件数＋グループ境界の確定に必要な最小の前方分」へ落とす。境界のために前方を見る必要がある場合は、必要量を上限付きで確定させる（無制限に遡らない）。
2. **[根治] 確定行と live 行を分離する。** 完了済みブロックは追加・完了時のみ更新し、ストリーミング中の 1 行だけを `@Observable` 参照型で本文更新する。親 `ChatTranscriptView` は live 行の本文を読まない。`TranscriptFollowSignal` の生成も全 item を読まない形にする。**これは 0116 の対処4 の未実装部分であり、`.equatable()` だけでは代替できない。**
3. **[取り消し] 対処1（live-resize 幅凍結）と対処2（40→16）は、効果が測定できないため根治策として数えない。** 実装済みのコードは残すが、これらを理由にカクつきが解消したと述べない。
4. **[据え置き] 0116 の対処3（子 `GeometryReader` 除去）・対処5（MarkdownUI AST キャッシュ）は未着手のまま。** ただし優先順位は 1・2 の後。
5. **[計測規約] `.appServer` グリッドの性能主張には、必ず「出力中か否か」を明記する。** アイドル時の計測は本問題の再現条件を満たさない（0 件になる）。再現には合成ストリームで足りる（課金不要）。

## 結果

**ポジティブ**
- 走査母数を落とす対処は、定常・リサイズの両方に同時に効く（どちらも同じ全件走査を通るため）。
- 合成ストリームによる再現手順が確立したので、以後は修正のたびに A/B を無償で回せる。
- 「実装済み」と「改善済み」を取り違えた記述を、実測で置き換えられた。

**ネガティブ / 受容するコスト**
- 窓を前段へ移すと、グループ境界の判定が窓の外側に依存するケース（同一ツール実行の連続グループが窓の先頭で切れる等）を扱う必要があり、見た目の切れ方が変わりうる。
- 確定行 / live 行の分離は `ChatSessionViewModel` の transcript 更新経路の再設計を伴う（0116 と同じコスト評価）。
- 本 ADR の計測は合成ストリーム（固定コーパス・約 40 delta/秒/セッション）であり、実エージェントの出力速度・内容分布とは異なる。`.pty` セッションは未計測。

## 代替案

1. **対処1・2・4 の延長で押し切る** — 却下。A/B で改善が測定できなかった。
2. **`flushInterval` を 0.05→0.1〜0.15 秒へ落とす** — 弱い。走査 1 回あたりのコストは変わらず、更新頻度を半分にするだけ。母数を落とす対処の後に効果を測って決める。
3. **LazyVStack の再導入** — 却下。ADR 0030 の自走レイアウトループを再発させる。
4. **Web 技術（Tauri 等）への置き換え** — 本問題には無効。コストは端末描画でも CoreText の幅再整形でもなく「更新のたびに全件を読む依存構造」にあり、同じ構造を DOM で組めば同じ再計算が起きる。

## 参照

- [ADR-0116](0116-agent-grid-swiftui-jank-live-resize-width-freeze.md)（superseded。修正前ベースラインの計測値と、当時の因果仮説）
- [ADR-0115](0115-terminal-engine-off-main-thread.md)（`.pty` 端末向け。本問題には無効というスコープ分離は 0116 から維持）
- [ADR-0030](0030-transcript-eager-layout-and-one-way-composer-metrics.md)（非 Lazy VStack と窓機構。LazyVStack 再導入禁止の根拠）
- 作業ログ: [delivery/0034](../delivery/0034-adr0116-remeasurement-worklog.md)
