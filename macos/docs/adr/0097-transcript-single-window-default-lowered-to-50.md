---
status: active
last-verified: 2026-07-18
---

# 0097: 単一表示トランスクリプト窓の初期件数を 200→50 に引き下げ（expandStep も 50）

> **このファイルの役割**: 単一表示（`.single`）の `TranscriptWindow` 既定件数と展開ステップを 200 から 50 へ引き下げた決定と rationale。ADR 0051・0094 の閾値記述を改定する。
> **書かないもの**: 窓機構そのものの設計（→ 0051 純関数化・reveal-on-jump・アンカー保持 / 0094 文脈別既定・hang timer pause）。接続ローディング表示（別 ADR）。

## 文脈

セッションを開くと空白→一気に描画される体感遅延（ユーザー報告のUX不具合）と、「200件は多い」というユーザー指摘があった。ADR 0051 は単一表示の `TranscriptWindow` を既定 `limit=200`・`expandStep=200` で導入し、ADR 0094 は `TranscriptPresentationContext`（`.single = 200` / `.gridTile = 40`）で文脈別の既定を導入した。単一表示の初回 eager 描画数（末尾 200 件）が、非 Lazy VStack（ADR 0030）での初期レイアウトコストの主因になっていた。

同種の問題を抱える iOS 側にも件数制限を新設する（ADR 0022）にあたり、初回描画数を大きく減らす方向で両プラットフォームの初期件数を揃えることにした。

## 決定

1. **単一表示（`.single`）の既定を `defaultLimit = 50`・`expandStep = 50` に引き下げる**（従来 200/200）。`.gridTile = 40` は不変。
2. 窓の他の性質は一切変えない: 純関数性（totalCount のみに依存・スクロール量/可視領域に非連動＝ADR 0030 の再入禁止）、拡張契機はボタン押下のみ、非 Lazy VStack 維持、`reset()`/`reveal()`/展開アンカー保持の意味論（ADR 0051・0094）。
3. iOS（ADR 0022）と同値（`defaultLimit = 50`・`expandStep = 50`）で揃える。iOS/macOS は Swift Package を共有しないため実装は別だが、初期件数の設計判断を一致させる。

## 棄却案

- **200 のまま維持**: 初回 eager 描画数が大きく体感遅延が継続。ユーザー指摘に反する。
- **中間値（例 100）**: 半端で iOS と不一致。初回コスト削減効果も限定的。
- **Lazy 化で描画コストを下げる**: ADR 0030 で実機確定済みの自走レイアウトループ（CPU 55-100% 固着）。採らない。件数制限で対処する方針は不変。

## 結果

- 受け入れテスト `AcceptanceGridRenderCostTests`（`TranscriptWindow.defaultLimit(for: .single) == 50`・単一文脈の `visibleRange` の startIndex/hiddenCount を 50 基準へ更新）、白箱 `TranscriptWindowContextWhiteboxTests`（`expandStep == 50`・展開後 startIndex）・`TranscriptRenderCostWhiteboxTests`（1000 件で visibleCount ≤ 50）が green。`swift test --package-path macos/Packages/SessionFeature` 全数 green。
- 単一表示の初回 eager 描画数が末尾 50 件に有界化（従来 200）。
- **未検証（フェーズ4/実機）**: 実機での初回オープン体感（空白→描画のレイテンシ低減）は次段で確認する。

## 改定関係

- ADR 0051 の「既定 limit=200・expandStep=200」、ADR 0094 の「`.single = 200`」を本 ADR で **200→50 に改定**（両 ADR にインライン改定注記と本 ADR へのリンクを追記）。0051・0094 のその他の決定（純関数化・reveal-on-jump・アンカー保持・文脈別既定の枠組み・hang timer pause）は不変。
