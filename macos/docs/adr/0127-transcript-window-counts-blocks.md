---
status: active
last-verified: 2026-07-27
---

# 0127: transcript の表示窓はブロック単位で数え、ツール実行は1件でも集約する

## ステータス

採択・実装済み（2026-07-27, `feature/tool-call-collapse-threshold`）。**[ADR 0096](0096-chat-tool-call-grouping.md) の「連続2件以上を集約」を supersede する。** 窓の機構そのもの（[ADR 0030](0030-transcript-eager-layout-and-one-way-composer-metrics.md) / [ADR 0051](0051-transcript-tail-window.md)）と既定値 50 / 16（[ADR 0097](0097-transcript-single-window-default-lowered-to-50.md) / [ADR 0116](0116-agent-grid-swiftui-jank-live-resize-width-freeze.md)）は変更しない。

## コンテキスト

ユーザー報告:「ツールコールが多いだけでメッセージが折りたたまれてしまう。ツールコールの数と折りたたむ閾値は無関係にしてほしい。」

原因は2つの機構がどちらもツールコール件数に依存していたこと。

1. **表示窓が生の `ChatItem` 件数を数えていた。** `TranscriptWindow.visibleRange(totalCount:)` に `items.count` を渡していたため、折りたたまれて画面上は1行にしかならない連続ツール実行が、1件につき1枠を消費していた。ツールを50件実行すると窓（既定50）が全部埋まり、直前のユーザーメッセージ・エージェントの発話が「以前のメッセージを表示」の裏へ押し出される。**窓の目的（先行レイアウトコストの有界化）に照らすと、これは母数の取り方が間違っている**——閉じたグループが占めるレイアウトは1行なので、コストの母数は「トップレベルに描画されるブロック数」であって item 数ではない。
2. **集約の条件が件数依存だった。** `ChatTranscriptGrouping` は連続2件以上のときだけ `commandGroup` に畳み、1件のときは `.single` のまま出していた（ADR 0096）。同じ「ツール実行」が件数によって別の見た目になる。iOS は先に [iOS ADR 0026](../../../ios/docs/adr/0026-ios-single-toolcall-grouped-row.md) で1件以上に統一しており、macOS だけが取り残されていた。

## 決定

1. **窓はトップレベルに描画されるブロック数を数える。** `ChatTranscriptGrouping.visibleSlice(from:blockLimit:)` が全 item をブロックへ畳んだうえで末尾 `blockLimit` ブロックを返す。隠れ件数 `hiddenBlockCount` もブロック単位（旧 `hiddenItemCount` から改名）。
2. **連続する `.commandExecution` は1件以上で常に `commandGroup` にする。** iOS と同じ契約に揃える。
3. **`TranscriptWindow` は一切変更しない。** API・`defaultLimit`（single=50 / gridTile=16）・`expandStep`・`reveal` の実装はそのまま。呼び出し側が渡す `totalCount` の意味だけを item 数 → ブロック数へ変える。
4. **隠れ域へのジャンプは item index → block index へ翻訳してから `reveal` に渡す。** `ChatTranscriptGrouping.blockIndex(ofItemWithID:in:)` / `blockCount(of:)` を新設。

## 結果

- ツールコールが何件走っても、可視メッセージの構成が変わらない。
- **窓境界が必ずブロック境界になるため、旧「部分ブロック」処理（境界がグループ内部に落ちたとき先頭ブロックの id を全 transcript 上のグループ先頭 item.id へ差し替える）が不要になり削除した。** id の決定が1箇所になる。
- レイアウトコストの上限の表現が「可視 item 数 ≤ 50」から「**可視ブロック数 ≤ 窓 limit**」へ変わる。ADR 0030 の目的（非 Lazy VStack の先行レイアウトコストを有界化する）は維持される——閉じた `commandGroup` はヘッダ1行しかレイアウトしないため。
- 「以前のメッセージを表示 / 残り N 件」の N の意味が item 数からブロック数へ変わる。実際の表示単位と一致するので、表示としてはむしろ正確になる。
- ADR 0116 が実測した `gridTileDefaultLimit = 16` の「母数」の意味も item 数からブロック数へ変わる。16 という数値は据え置いた（グリッドタイルでツール実行が長く連なる場合、実質的な情報量は増えるがレイアウト対象の行数は増えない）。
- 1件のツール実行が `commandGroup` になった副作用として、**出力が空・非実行中の単独コマンドがカードごと描画されなくなる**（`shouldRender = isRunning || !rows.isEmpty` に引っかかる）。これは [ADR 0128](0128-command-group-cost-bounding.md) で iOS の規則（唯一の行には空出力フィルタを適用しない）を移植して塞いだ。
- 実装が全 item を1回走査してブロック列を作るが、呼び出し元 `ChatTranscriptView` は既に `InputHistoryPolicy.entries(from:)` で全 item を毎 body 走査しており、漸近コストは増えていない。

## 棄却した案

- **窓の上限そのものを撤廃する**: ADR 0030 の非 Lazy VStack 前提を壊す。ユーザーの要求は「件数と閾値を無関係にする」であって「上限をなくす」ではない。
- **窓は item 数のまま、コマンドの重みを小さくする（例: 0.1枠）**: 依然としてツールコール件数が閾値に効く。要求を満たさない。
- **メッセージ種別ごとに別々の窓を持つ**: 表示順が時系列で1本なので、2本の窓を突き合わせる複雑さに見合わない。

## 凍結テスト

- `macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceToolCallGroupingTests.swift` — 1件でも集約・identity 安定・平坦化等価
- `macos/Packages/SessionFeature/Tests/SessionFeatureTests/AcceptanceBlockWindowTests.swift` — ツール1000件でも直前メッセージが可視・可視ブロック数 ≤ blockLimit（列挙した入力表）・部分ブロックが生じない・block index 翻訳
