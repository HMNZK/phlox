---
status: active
last-verified: 2026-07-18
---

# ADR 0022: iOS チャット履歴の末尾ウィンドウ描画（TranscriptWindow・初期50件・段階展開・アンカー保持）

> **このファイルの役割**: モバイルでセッションを開くと空白→一気に描画される体感遅延を、チャット履歴を末尾 N 件のみ描画し超過分を折りたたむ件数制限で抑えた決定と、その閾値・展開契機・スクロールアンカー保持の設計理由を記録する。
> **書かないもの**: 現行の実装仕様（→ 実装は `Features/SessionDetail/TranscriptWindow.swift`・`SessionDetailView.swift`）・接続ローディング表示（別 ADR）。

## 文脈

`SessionDetailView.chatSection` は `ForEach(viewModel.visibleMessages)` で**チャット履歴の全件を一度に**非 Lazy VStack へ描画していた。長いセッションを開くと、全件の先行レイアウト（各行の Markdown 分割・ハイライトを含む）が同期で走り、「セッションを開く→しばらく空白→一気に描画」の体感遅延が発生していた（ユーザー報告のUX不具合）。

macOS（Phlox）側は同種の問題を `TranscriptWindow`（末尾 N 件描画・ADR 0051、非 Lazy VStack・ADR 0030、グリッドタイル窓・ADR 0094）で既に解決済みだが、iOS 側には件数制限が一切無かった。iOS/macOS は Swift Package を共有しないため、設計を移植する。

## 決定

1. **`TranscriptWindow`（純粋値型）による末尾件数制限**。macOS 実装を iOS へ移植し、grid 文脈の無い iOS では**単一文脈のみに簡約**した。`visibleRange(totalCount:)` は totalCount のみから末尾スライスの開始位置と隠れ件数を返す純関数（`defaultLimit = 50`・`expandStep = 50`）。スクロール量・可視領域・GeometryReader 計測には一切連動しない（ADR 0030 の再入禁止を構造で担保）。
2. **window は View 所有**（`SessionDetailView` の `@State`）。`viewModel.visibleMessages`（空メッセージ除外済みの全件・意味は不変）を View 側で末尾スライスし、超過時のみ先頭に「以前のメッセージを表示（残り k 件）」ボタンを出す。**拡張契機はボタン押下のみ**（`expand()` で +50）。セッション切替（`session.id` 変化）で `reset()`。50 件以下では折りたたみ UI もスライスも現れず全件表示。
3. **非 Lazy VStack を維持**（LazyVStack 再導入禁止）。macOS 実機で「実行中タイル更新＋スクロール」を契機に CPU 55-100% 固着の自走レイアウトループが確定済み（macos ADR 0030）。描画コスト削減は遅延機構ではなく件数制限で行う。
4. **展開時のスクロールアンカー保持**。展開で先頭に古い行を追加した瞬間にビューポートが履歴先頭へ飛ばないよう、`SessionDetailTranscriptExpansionPolicy`（純関数）が展開前の先頭可視 item の id をアンカーとして捕捉し、世代トークンを前進させ、末尾追従ではなくアンカースクロール（`scrollTo(anchor, .top)`）を選ぶ。View 側は世代ガード付きでこの scrollTo をイベント駆動で1回だけ発行する（macos ADR 0051 の展開アンカー保持と同型）。

## 棄却案

- **LazyVStack 化**: macos ADR 0030 で実機確定済みの自走レイアウトループ（CPU 暴走）。採らない。
- **スクロール位置連動の動的 window**: レイアウト観測フィードバック＝ADR 0030 の再入口。採らない。展開はボタン操作に限る（ユーザーの「自発的に遡る」はこのボタンで実現）。
- **`visibleMessages` 自体を窓化する**: 空メッセージ除外の既存契約（`ChatVisibilityAcceptanceTests`）を壊すため採らず、窓は View 側スライスに閉じた。

## 閾値の根拠

初期表示 `defaultLimit = 50`・拡張 `expandStep = 50`。macOS の従来 200 は「多すぎる」というユーザー指摘を受け、初回 eager 描画数を大きく減らす方向で 50 に設定した（macOS 側も同時に single 200→50 へ引き下げ）。起点値であり実機体感で調整しうる。

## 結果

- 受け入れテスト `TranscriptWindowAcceptanceTests`（6件）＋白箱 `TranscriptWindowWhiteboxTests`・`SessionDetailWindowingWhiteboxTests` が green。展開決定ロジック（アンカー捕捉・世代前進・末尾追従を選ばない）を白箱でリテラル検証。`swift test --package-path ios/Packages/PhloxKit --no-parallel` 全数 green（802件）。
- 初回オープン時の eager 描画数が末尾 50 件に有界化（従来は全件で非有界）。
- **未検証（フェーズ4/実機）**: 展開時のピクセル単位のスクロール位置保持は macOS 実機検証済みパターンの忠実移植であり、iOS 実機/シミュレータでの XCUITest 目視確認は次段で行う。
