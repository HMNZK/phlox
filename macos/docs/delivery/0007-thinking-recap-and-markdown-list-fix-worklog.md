---
status: completed
last-verified: 2026-07-19
---

# 0007: Thinking recap（作業要約の薄グレー表示）＋ Markdown 箇条書き行重なり修正 worklog

agentic-loop（backend=external）による2件の run 記録。実装は外部エージェント（Cursor ヘッドレス）へ委譲、PM（Claude）が問題定義・契約凍結・レビュー・統合・蒸留を担当。対象は macOS + iOS 両方。

## この run でやったこと

| task | 難度 | 内容 | 主な変更 |
|---|---|---|---|
| task-2 | deep | recap 共有コア（純関数）を `AgentDomain` に実装 | 新規 `ThinkingRecap`／`RecapActivity`（`summary(reasoningText:recentActivity:elapsed:threshold:)`・`defaultThreshold=5`・活動ラベル最大60字） |
| task-3 | standard | macOS 配線（SessionFeature） | 新規 `ChatRecap.derive(...)`＋`ChatSessionViewModel.recap(now:)`、`ThinkingIndicatorCell` を recap クロージャ化（`TimelineView`）、`ChatTranscriptView` 配線 |
| task-4 | standard | iOS 配線（PhloxKit） | 新規 `ChatRecapIOS.derive(...)`＋`SessionDetailViewModel`（`thinkingStartedAt`・`recap(now:)`）、`DSThinkingIndicator`（textTertiary・lineLimit 3）、`SessionDetailView` を `TimelineView(.periodic)` 化 |
| task-1 | deep | Markdown 箇条書きの折り返し行が次項目と重なるバグ修正 | `RichMarkdownView.swift`・iOS `DSMarkdownText.swift` の `.listItem` テーマフックに list 限定 `.fixedSize(horizontal:false, vertical:true)` を追加（table 非波及） |

## 蒸留した永続知見

- [ADR 0100](../adr/0100-thinking-recap-heuristic-summary.md): recap をヒューリスティック抽出＋ツール活動から導出（LLM 要約は却下）、閾値ゲート、共有 `AgentDomain` 純関数設計。
- [ADR 0101](../adr/0101-scoped-listitem-fixedsize-to-avoid-table-cpu-regression.md): 箇条書き行重なりを `.listItem` 限定の縦サイズ確保で修正（ADR 0045 の表 CPU 暴走を再発させないスコープ限定）。
- iOS 側の配線ログは [ios/docs/delivery/0009](../../../ios/docs/delivery/0009-thinking-recap-wiring-worklog.md)。

## 検証（客観シグナル）

- 凍結受け入れテスト（PM 著・不変）: `ChatRecapAcceptanceTests`・`IOSChatRecapAcceptanceTests`（各7件）を先に契約凍結。閾値ゲート・活動ラベル・reasoning 見出し抽出・最新活動優先・最後の user 以降スコープを検証。
- 独立レビュー（persona-reviewer）: task-2/3/4 pass。
- 統合検証: dev を feature へ取り込んだ後の全走で AgentDomain 167／PhloxKit 413／SessionFeature 209／DashboardFeature 1383 すべて green（0 failures）。dev の Thinking シマー（ADR 0067）・サブエージェント集約と、recap 配線が同じ `ChatMessageCells+Structured.swift` を触るが ort 自動マージが意味的にも健全（コンパイル＋全テスト green で裏取り）。
- 目視: Debug ビルド（`com.phlox.Phlox.debug`・別 derivedDataPath）を Release 併存で起動し、recap の薄グレー表示と箇条書きの重なり解消をユーザーが確認（「確認できた」）。
- マージ: `feature/thinking-recap` を `dev` へ fast-forward。

## task-1 の検証方針（重要な判断）

箇条書きの重なりは PM が隔離描画ハーネス（`ImageRenderer`／`NSHostingView.fittingSize`、フォント倍率 0.8〜2.0）で**再現できなかった**（未修正でも高さは正しい＝実アプリのフル描画コンテキスト依存）。決定論ユニット回帰テストに落とすと緑固定の偽テストになるため凍結せず、ゲートを PM のライブ目視検証とした（ADR 0045 と同じ判断）。

## run 運用の教訓

- グローバル `verify.sh` 丸ごと実走は mid-run では誤検知する（兄弟タスク未実装の受け入れテストや `macos/build-debug/` の未追跡汚染を拾う）。per-task 認証は task 固有テスト直走＋`git status --short <pkg>` のスコープ確認で代替した。
- Debug 併存ビルドは別 `derivedDataPath`＋別 bundle id（`com.phlox.Phlox.debug`）で Release（`/Applications/Phlox.app`）に一切触れず起動できる（[guides/running-release-and-debug-together](../guides/running-release-and-debug-together.md)）。
