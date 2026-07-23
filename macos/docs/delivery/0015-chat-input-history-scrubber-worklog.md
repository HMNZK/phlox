---
status: completed
last-verified: 2026-07-23
---

# 0015 チャット入力履歴スクラバー（macOS 単一チャット表示）

## この run で何をしたか

会話履歴が長くなると過去の自分の入力を遡りにくい問題に対し、ChatGPT の左端ナビゲーション相当の「入力履歴スクラバー」を macOS の単一チャット表示（`ChatSessionView`）へ追加した。

- チャット画面の**左中央**に横線を積み重ねたミニマルなインジケータ（スクラバー）を常設（最下部＝最新入力を強調）。
- スクラバーに**ホバー**すると過去のユーザー入力を一覧するオーバーレイパネルが開く（1行=1入力・末尾省略）。
- 一覧の行を**クリック**すると、その入力メッセージまでスクロール（ジャンプ）する。

## 実装（既存資産の再利用が骨子）

- **データ層（task-1）**: `InputHistoryPolicy.swift` を新設。`entries(from: [ChatItem]) -> [InputHistoryEntry]`（`.userMessage` を transcript 配列順で抽出）、`scrubberTicks(from:cap:)`（スクラバー表示用に最新側を上限件数で返す）。`ChatSessionViewModel.inputHistoryEntries` で公開。revert 用 `revertCandidates`（新しい順）とは別プロパティで意味論を分離。
- **UI 層（task-2）**: `ChatInputHistoryScrubber.swift` を新設。スクラバー＋ホバーで開くオーバーレイパネル＋行。`ChatSessionView.mainColumn` の transcript に `.overlay(alignment: .leading)` で重ね、行クリックで `requestedTranscriptTarget = <id>` を代入。
- **ジャンプは新機構を作らず既存へ相乗り**: `requestedTranscriptTarget` → `ChatTranscriptView.jumpToTarget`（windowing の reveal-on-jump 込み）。表示件数制限で隠れた古い入力にも到達する。
- **ホバーのちらつき対策**: スクラバーとパネルを単一 `.onHover` の連続 hit 領域にし、離脱時は 200ms の cancellable Task で閉じ、再進入でキャンセル。状態変更は onHover / クリック / Task 完了のみ（**ADR 0010**＝body 中の観測 state 変更禁止 を遵守）。transcript レイアウトには割り込まず overlay に留める（**ADR 0030**）。

## 検証

- 純関数の受け入れ＋白箱テスト（Swift Testing, `InputHistoryPolicyAcceptanceTests`/`InputHistoryPolicyWhiteboxTests`）11 件 green。配列順不変条件（timestamp ソートへ化けない）の回帰ガードを含む。
- アプリ Debug ビルド（xcodebuild -scheme Phlox）BUILD SUCCEEDED。SessionFeature 全 314 テスト pass（退行なし）。
- ランタイム視覚検証: `NSHostingView` + `cacheDisplay` で production View を PNG 描画し、スクラバー本体と履歴パネル（過去入力の1行省略一覧）が参考デザインどおり描画されることを確認。
- 残る未検証: ライブでのマウスホバー実操作の感触のみ（配線・ホバー論理は検証済み）。

## スコープ外（この run で入れていない）

- グリッド表示（`GridChatColumn`）への表示（ユーザー選択で単一表示のみ）。
- アシスタント応答・コマンド出力へのジャンプ、入力の検索/フィルタ、iOS 版。

## 関連

- 姉妹機能（過去ユーザー入力の一覧・ESC2連打の巻き戻し）: architecture/chat-revert-escape-and-interrupt.md
- コンポーネント目録の追記先: architecture/chat-mode-ux-components.md
- ジャンプ機構・windowing: architecture/chat-transcript-perf-worklog（delivery/0005）系、ADR 0010/0030。
