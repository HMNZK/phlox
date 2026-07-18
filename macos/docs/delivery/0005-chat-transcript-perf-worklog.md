---
status: completed
last-verified: 2026-07-18
---

# 0005: チャット描画パフォーマンス（閾値 200→50・復元中の接続表示）作業ログ

> この run で macOS(Phlox) に行った作業のスナップショット。iOS 側の対応は [ios/docs/delivery/0008](../../../ios/docs/delivery/0008-chat-transcript-perf-worklog.md)。

## 背景

セッションを開くと空白→一気に描画される体感遅延と、「200件は多い」というユーザー指摘。macOS は件数制限（ADR 0051/0094）を先行実装済みだったが、単一表示の初期件数が 200 と大きく初回描画コストの主因になっていた。加えて復元中は空白のまま描画待ちが伝わらなかった。agentic-loop（backend=external）で iOS と並列に対応した。

## この run で macOS に入れた変更

- **task-3: 単一表示窓の初期件数 200→50・折りたたみUI見直し**（→ [ADR 0097](../adr/0097-transcript-single-window-default-lowered-to-50.md)）。`TranscriptWindow.defaultLimit(.single)` と `expandStep` を 200→50 に引き下げ（`.gridTile = 40` は不変）。「以前のメッセージを表示」ボタンの見直し。ADR 0051/0094 の閾値記述をインライン改定注記＋0097 リンクで整合。
- **task-4: セッション復元中の接続表示**（→ [ADR 0098](../adr/0098-chat-restore-connecting-indicator.md)）。`ChatRestoreState` に `restoring` を追加、`restore()` 入口で `.restoring` に遷移。`ChatSessionView` が `.restoring` かつ transcript 空の間だけ新規 `ChatConnectingIndicator`（iOS `DSConnectingIndicator` の移植・`DSColor.chatAccent`・Reduce Motion 静的フォールバック・`accessibilityHidden(true)`）を中央表示。`SessionRestoreCoordinator` は変更不要。

## 検証

- `swift test --package-path macos/Packages/SessionFeature`（176）・`--package-path macos/Packages/DashboardFeature`（1374）全数 green。enum case 追加で網羅 switch が壊れない＝コンパイル通過が回帰ゲート（DashboardFeature が `ChatSessionViewModel`/`restoreState` を consume）。受け入れ `AcceptanceGridRenderCostTests`（`defaultLimit(.single)==50`）＋白箱 `TranscriptWindowContextWhiteboxTests`・`TranscriptRenderCostWhiteboxTests`・`ChatConnectingLoadingWhiteboxTests`（3）。
- macOS アプリ（Phlox）のデバッグビルド BUILD SUCCEEDED（統合検証・コンパイル/リンク・`ChatRestoreState` を switch する箇所はアプリターゲットに不在）。
- **未検証（実機）**: 実機での初回オープン・復元の体感レイテンシは次段（実機検証）で確認する。

## レビュー経緯

- task-3/task-4 は deep（stage-1 persona-reviewer + stage-2 Codex）。task-4 stage-2 は read-only サンドボックスで `swift test` 未実行のため needs_changes だったが、実害指摘ゼロ・静的に契約適合で、stage-1 実走（176+1374 green）＋PM のゼロ信頼 verify ＋実装役実走の3系統の独立 green を証拠に pass 裁定（decision-log 記録）。
- 生成/改定した ADR: 0097（閾値 200→50・新規）・0098（復元中接続表示・新規）・0051/0094（改定注記）。
