---
status: active
last-verified: 2026-07-03
---

# ADR 0023: チャット自動追従スクロールの非アニメ化（自己持続再無効化ループの遮断）

## 文脈

チャット UI で CPU が 100% に固着しアプリ全体（ControlServer 含む）が応答不能になる暴走が、①通常のセッション往来・サイドバー開閉、②高速セッション切替、③グリッドビュー表示、の3経路で実測された（`sample` 3本がすべて同一ホットパス）。ホットパスは `flushObservers → GraphHost.flushTransactions` 配下の `LazySubviewPlacements.placeSubviews` / `ForEachList.applyNodes`（transcript の ForEach 再差分）＋ `ChatBottomOffsetPreferenceKey.reduce` ＋ `AnimatableAttribute`。ADR 0010（Loopflow 盤ハング）と同クラスの「view 更新がレイアウトを駆動し、レイアウトが view 更新を再駆動する」自己持続ループである。

発振源は自動追従スクロールの `withAnimation(.easeOut 0.16) { proxy.scrollTo(...) }`。アニメーション中の各フレームで LazyVStack のセル実体化・推定サイズ更新が起こり、スクロール目標が動き続けてアニメーションが収束しない。再現は確率的（レース）で、一度定着すると外部入力ゼロでも継続する。A/B 検証（アニメ無効化ビルド）と修正後実測（ベースラインを固着させた同一プロトコルで 0% 収束・8ラウンド超）が因果を支持する。

## 決定

- `ChatTranscriptView.scrollToBottomIfNeeded` は **常に非アニメ** の `proxy.scrollTo` で最下部へ移動する。`withAnimation` と `animated` 引数を除去。
- 自動追従の判定（`ChatAutoFollowController` の preference 監視・dedup）は変更しない。
- 一般則（ADR 0010 の系）: **transcript のような可変高コンテンツを持つ LazyVStack への `scrollTo` を `withAnimation` で駆動しない**。アニメーションがレイアウト（preference・セル実体化）へフィードバックする構成は自己持続ループの温床になる。

## 棄却案

- スクロール要求のフレーム合流（防御層の追加）: 非アニメ化単独で実測が収束したため見送り（ユーザー決定）。
- NSScrollView 直接制御でアニメーションを温存: 実装が重く SwiftUI レイアウト機構との相互作用が再び未知数になるため不採用。

## 結果

- 新着メッセージ到達時の 0.16 秒スクロールアニメーションは失われ、瞬間ジャンプになる（自動追従・手動スクロールの慣性は維持）。
- 検証: DashboardFeature 526 tests green・E2E 17 green・runtime 実測で CPU 一桁%収束（診断と実測の詳細は delivery/0006 worklog）。
- この欠陥クラスは `swift test` をすり抜ける。UI/描画/状態観測の修正は runtime 実測（top/sample）を完了条件にする（CLAUDE.md 既載の教訓を再確認）。
