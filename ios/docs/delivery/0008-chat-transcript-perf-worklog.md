---
status: completed
last-verified: 2026-07-18
---

# 0008: チャット履歴描画の体感遅延改善（折りたたみ＋初回ロード表示）作業ログ

> この run で iOS(PhloxMobile) に行った作業のスナップショット。macOS 側の対応は [macos/docs/delivery/0005](../../../macos/docs/delivery/0005-chat-transcript-perf-worklog.md)。

## 背景

セッション（例: Magnolia）を開くと「空白→しばらくして一気に描画」というUX不具合が報告された。iOS 側にはチャット履歴の件数制限も、初回ロード中のフィードバックも無かった（macOS は件数制限を先行実装済み）。agentic-loop（backend=external）で iOS/macOS を並列タスク化して対応した。

## この run で iOS に入れた変更

- **task-1: チャット履歴の末尾ウィンドウ描画**（→ [ADR 0022](../adr/0022-ios-transcript-tail-window.md)）。`TranscriptWindow`（純粋値型・`defaultLimit = 50` / `expandStep = 50`）を新設し、`SessionDetailView` が `visibleMessages` を末尾スライス。超過時のみ「以前のメッセージを表示（残り k 件）」ボタンで段階展開、展開時アンカー保持。非 Lazy VStack 維持（ADR 0030 の LazyVStack 禁止を踏襲）。
- **task-2: 初回ロード中の接続表示**（→ [ADR 0023](../adr/0023-ios-initial-load-connecting-indicator.md)）。`isInitialLoading` と計算プロパティ `showsInitialLoadingIndicator` を追加し、初回ロードの空白区間に既存 `DSConnectingIndicator` を中央表示。閉じ判定は実データのロード完了に紐付け、ドラフト作成画面は `!isAwaitingInitialSpawn` で除外（永久スピナー回避）。

## 検証

- `swift test --package-path ios/Packages/PhloxKit --no-parallel` 全数 green（Swift Testing 388・XCTest 420）。受け入れ `TranscriptWindowAcceptanceTests`（6）＋白箱 `TranscriptWindowWhiteboxTests`・`SessionDetailWindowingWhiteboxTests`・`SessionDetailLoadingWhiteboxTests`（6）。
- iOS アプリ（PhloxMobile）のシミュレータ向けデバッグビルド BUILD SUCCEEDED（統合検証・コンパイル/リンク）。
- **未検証（実機）**: 実機/シミュレータでの初回オープン体感レイテンシと展開時のピクセル単位スクロール保持は次段（実機検証）で確認する。

## レビュー経緯

- task-1/task-3 は差し戻し#1 を経て pass（deep・stage-1+stage-2）。task-2 は stage-1 で MUST（ドラフト画面の永久スピナー）指摘→差し戻し#1 で `!isAwaitingInitialSpawn` ガードと回帰テスト追加→再レビュー pass。
- 生成した ADR: 0022（末尾ウィンドウ）・0023（初回ロード表示）。
