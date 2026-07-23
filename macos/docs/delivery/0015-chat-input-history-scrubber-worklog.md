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

## フォローアップ（実機確認後のデザイン洗練＋スクロール連動）

初回デリバリ後、実機フィードバックで以下を追加改修した（同一 feature ブランチ上）。

- **囲いの除去・見出しの除去**: スクラバーを包んでいた `Capsule` 背景／枠線を撤去し細い横線のみに。パネル冒頭の「入力履歴」見出し＋区切り線も撤去。
- **Liquid Glass パネル**: パネル面を `#available(macOS 26.0, *)` で `.glassEffect(.regular)`、下位は `.ultraThinMaterial` にフォールバック。
- **ホバー領域の分離**（ちらつき／閉じ残りバグの根治）: スクラバーとパネルへ**独立した `.onHover`** を付け、両方から外れたときだけ 200ms 猶予で閉じる。単一 hit 領域だとパネルの背丈ぶんの空白まで hover 判定に入り「外しても閉じない」不具合が出たため。
- **スクラバー↔パネルの選択連動**: 共有の選択位置（ホバー中は `activeID`、非ホバー時はスクロール連動の現在位置、無ければ最新）で、選択中の線を白く長く・対応パネル行をハイライト。線・行のいずれのクリックでもジャンプ。
- **スクロール位置連動**: `ChatSessionView.currentInputPositionID` を `ChatTranscriptView` が NSScrollView のビューポート中央にあるユーザー入力から算出して更新。位置測定は content 座標系（スクロール不変）の preference、@Binding 更新は値変化時のみ＝既存の `isThinkingIndicatorInViewport` と同一経路で **ADR 0030** の再入を回避。クリックジャンプは `.center` アンカーなので着地後もその入力が中央に来て強調が保たれる。

検証: `swift build` 成功／SessionFeature 全 314 テスト pass（純関数テストは不変）。実機でホバー・クリックジャンプ・スクロール連動をユーザーが確認し完了。

## スコープ外（この run で入れていない）

- グリッド表示（`GridChatColumn`）への表示（ユーザー選択で単一表示のみ）。
- アシスタント応答・コマンド出力へのジャンプ、入力の検索/フィルタ、iOS 版。

## 関連

- 姉妹機能（過去ユーザー入力の一覧・ESC2連打の巻き戻し）: architecture/chat-revert-escape-and-interrupt.md
- コンポーネント目録の追記先: architecture/chat-mode-ux-components.md
- ジャンプ機構・windowing: architecture/chat-transcript-perf-worklog（delivery/0005）系、ADR 0010/0030。
