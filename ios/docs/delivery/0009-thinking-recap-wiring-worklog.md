---
status: completed
last-verified: 2026-07-19
---

# 0009: Thinking recap（作業要約の薄グレー表示）iOS 配線 作業ログ

> この run で iOS(PhloxMobile) に行った作業のスナップショット。要約コアの設計と macOS 対応は [macos/docs/adr/0100](../../../macos/docs/adr/0100-thinking-recap-heuristic-summary.md) と [macos/docs/delivery/0007](../../../macos/docs/delivery/0007-thinking-recap-and-markdown-list-fix-worklog.md)。

## 背景

Thinking が長いとき、iOS は末尾 reasoning 全文（`thinkingPreview`）を薄グレー表示するだけで「いま何をしているか」が伝わらなかった。macOS と共通の要約コア（`AgentDomain.ThinkingRecap`）を iOS からも消費し、長考時に活動要約を出す。要約方式（ヒューリスティック＋ツール活動・LLM 不使用）と閾値ゲートの決定は macOS ADR 0100 が正本。

## この run で iOS に入れた変更（task-4）

- **要約導出**: 新規 `ChatRecapIOS.derive(messages:status:elapsed:threshold:)`。iOS 独自 `ChatMessage`（`.reasoning`/`.command`/`.fileChange`）を共有コア `ThinkingRecap` へ橋渡しし、最後の user 発話以降を対象に最新ツール活動を優先、無ければ reasoning ヒューリスティック。
- **経過時間の起点**: `SessionDetailViewModel` に `thinkingStartedAt: Date?` を追加。running 進入時に設定、退出時に nil、同ステータスの polling では動かさない。`recap(now:)` が閾値（5秒）ゲートを適用。
- **表示**: `DSThinkingIndicator` を recap 表示に変更（`textTertiary`＋`lineLimit(3)`）。`SessionDetailView` の同インジケータを `TimelineView(.periodic(from:.now, by:1))` で包み `viewModel.recap(now: context.date)` を渡す。既存の `thinkingPreview` は保持。

## 検証

- `swift test --package-path ios/Packages/PhloxKit --no-parallel` 全数 green（Swift Testing 413／XCTest 420）。凍結受け入れ `IOSChatRecapAcceptanceTests`（7）＋白箱 `ChatRecapIOSWhiteboxTests`。
- 独立レビュー（persona-reviewer）: pass（thinkingStartedAt の追従を確認）。
- **未検証（実機）**: 実機での長考時 recap の体感は次段（実機検証）で確認する。

## 判断ログ（iOS ADR を起こさない理由）

- iOS の recap は macOS ADR 0100 の共有コア（`AgentDomain.ThinkingRecap`）を消費するだけで、新規の設計判断は無い。共有パッケージ参照の方針は既に iOS ADR 0001 が記録済みのため、iOS 側 ADR は起こさず本 worklog に留める。
