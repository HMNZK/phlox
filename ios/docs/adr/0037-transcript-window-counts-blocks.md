---
status: active
last-verified: 2026-07-27
---

# ADR 0037: iOS の transcript 表示窓はブロック単位で数える

## ステータス

採択・実装済み（2026-07-27, `feature/tool-call-collapse-threshold`）。[ADR 0022](0022-ios-transcript-tail-window.md) の窓機構と既定値（`defaultLimit = 50` / `expandStep = 50`）は変更せず、**数える単位だけ**を message 数からブロック数へ変える。macOS の [ADR 0127](../../../macos/docs/adr/0127-transcript-window-counts-blocks.md) と同じ決定。

## コンテキスト

ユーザー報告:「ツールコールが多いだけでメッセージが折りたたまれてしまう。ツールコールの数と折りたたむ閾値は無関係にしてほしい。」

iOS は [ADR 0026](0026-ios-single-toolcall-grouped-row.md) で既に「連続する `.command` は1件以上で必ず `commandGroup`」に統一済みだったが、**窓は生の `ChatMessage` 件数を数えていた**（`SessionDetailTranscriptSlice` が `window.visibleRange(totalCount: messages.count)` を呼ぶ）。折りたたまれて画面上は1行にしかならないツール実行が1件につき1枠を消費するため、ツールを50件実行すると窓が全部埋まり、直前のメッセージが「以前のメッセージを表示」の裏へ押し出される。

窓の目的（[ADR 0022](0022-ios-transcript-tail-window.md) → 元は macOS の [ADR 0030](../../../macos/docs/adr/0030-transcript-eager-layout-and-one-way-composer-metrics.md)）は初回オープンの eager 描画コストの有界化なので、母数は「トップレベルに描画されるブロック数」であるべきだった。

## 決定

1. **窓はブロック数を数える。** `SessionDetailToolCallGrouping.visibleSlice(from:blockLimit:)` が全 message をブロックへ畳んだうえで末尾 `blockLimit` ブロックを返す。隠れ件数 `hiddenBlockCount` もブロック単位（旧 `hiddenItemCount` から改名）。`blockCount(of:)` を新設。
2. **`TranscriptWindow`（iOS 版）は一切変更しない。** 呼び出し側が渡す `totalCount` の意味だけを変える。`SubAgentDetailViewModel` が同じ型をグルーピング非適用で使っているため、型を触らないことがそのまま巻き添え防止になる。
3. **`SessionDetailTranscriptSlice` の `visibleMessages` は可視ブロック列から導く。** ブロック列と message 列が別々の計算でずれないようにする。

## 結果

- ツールコールが何件走っても、可視メッセージの構成が変わらない。
- **窓境界が必ずブロック境界になるため、旧「部分ブロック」処理（境界がグループ内部に落ちたとき先頭ブロックの id を差し替える）が不要になり削除した。** id の決定が1箇所になる。
- `visibleMessages` の導出を「可視ブロックの件数から `messages.suffix(n)`」にしたことで、**`ChatMessage.id` が transcript 内で一意という契約外の前提が消えた**（当初実装は id の逆引きで求めており、id が重複すると範囲がずれた）。body 評価パスの全配列走査も1本減った。
- 「以前のメッセージを表示（残り N 件）」の N の意味が message 数からブロック数へ変わる。実際の表示単位と一致する。
- サブエージェント詳細の窓（`SubAgentDetailViewModel`）は**対象外**。グルーピングを適用していないため症状が異なる。

## 凍結テスト

- `ios/Packages/PhloxKit/Tests/FeaturesTests/AcceptanceIOSBlockWindowTests.swift` — ツール1000件でも直前メッセージが可視・可視ブロック数 ≤ blockLimit（列挙した入力表）・部分ブロックが生じない・`visibleMessages` と `visibleBlocks` の一致・隠れ件数がブロック単位
