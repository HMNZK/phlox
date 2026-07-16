---
status: active
last-verified: 2026-07-11
---

# ADR 0073: 前面オーバーレイ UI は「実測高からの余白予約」で本文と重ねない

> **このファイルの役割**: トップバー・フローティング composer と本文の重なり2件（2026-07-11 ユーザー報告）に対し、なぜ固定値でなく実測高ベースの純関数ポリシーで直したかの決定。あわせてシングルビューヘッダ行の 32pt 統一の決定。
> **書かないもの**: 各ビューの現行構造（→ `architecture/team-timeline-view.md`・`architecture/chat-subagent-display.md`）。

## 文脈

Phlox は操作系をレイアウトフローに置かず前面オーバーレイで描く方針（AppKit NSView に覆われる問題の回避。DashboardView のコメント参照）。オーバーレイは**高さを予約しない**ため、本文側の固定余白と実高がズレると重なる。実際に2件が顕在化した:

1. トップバー（使用量メーター含む topTrailing オーバーレイ）が2段表示になると実高が固定余白 32pt を超え、アゴラの右寄せユーザー発言と重なった。
2. 「履歴から再開」カードがトランスクリプト中央の overlay で、フローティング composer（ADR 0065）の実測高を考慮せず、低いウィンドウで衝突した。

## 決定

- **実測高 → 本文余白の一方向依存**を原則にする。オーバーレイの実高を `onGeometryChange` で計測し、本文側の余白は純関数ポリシーで決める。余白の変化がオーバーレイのサイズ決定へ戻る循環（発振）を構造的に作らない。state 更新は同値ガードで抑止する。
  - トップバー: `TopBarInsetPolicy.contentTopInset = max(32, ceil(実測高) + 8)`（32=従来固定値を下限に維持）。single/grid/team 共通入口（`DashboardDetailView`）で適用。
  - 履歴カード: `ChatHistoryStartLayout.maxCardHeight = clamp(利用可能高 − composer実測高 − 56, 120...360)`・`bottomInset = composer実測高`（センタリング領域を composer の上に制限）。
- **シングルビューのヘッダ行はグリッドのタイルヘッダと同じ縦幅に統一**: `SubAgentSplitLayout.headerHeight` 64→32。メイン/サブ両ペイン共有定数のため罫線整列（Bug4 対策）は維持。あわせてアイコン右にセッション名（heroTitle・middle truncation）を表示（グリッドと同型）。

## 棄却案

- **固定余白の増量**（32→48 等）: メーターの段数・フォント設定で実高が変わるためいずれ再発する。実測駆動が根本対応。
- **オーバーレイをレイアウトフローへ戻す**: AppKit ビューに覆われて消える既知問題（DashboardView コメント）に逆行。

## 結果

- 凍結受け入れ: `AcceptanceTopBarInsetTests`（5）・`AcceptanceChatHistoryLayoutTests`（6）・`AcceptanceSingleHeaderLayoutTests`（1）。
- 実 Debug（小ウィンドウ 760×480 相当）でシングル/アゴラとも本文・入力欄・ヘッダの重なりなしを目視確認。履歴カードそのものの実機確認は「新規セッション作成時に表示される状態」が必要なため未実施（純関数テスト＋レビューで担保。既知の残余: カード全体高はヘッダ行を含むため、極端な低さでは下限 120pt 側で理論上の食い込み余地がある——レビュー LOW・現実的なウィンドウ高では解消済み）。
- メーター2段時の実機再現は未実施（使用量データが Debug 環境に無く強制表示手段がない。実測予約の構造で解消される設計であり、単体テストとレビューで担保）。
