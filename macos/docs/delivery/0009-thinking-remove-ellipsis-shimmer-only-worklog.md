---
status: completed
last-verified: 2026-07-20
---

# 0009: Thinking の跳ねドット廃止・シマーのみに統一（macOS/iOS）worklog

agentic-loop（backend=external）による run 記録。実装は外部エージェント（Cursor ヘッドレス）へ委譲、PM（Claude）が問題定義・契約凍結・レビュー・統合・蒸留を担当。ユーザー要望「Thinking の "..." アニメーションを消してシマーだけにする」を、macOS メインチャットと iOS の両方へ適用（iOS はシマー未実装だったため新規移植＝ユーザー決定 B）。

## 何をしたか

| task | サーフェス | 内容 |
|---|---|---|
| task-1 | macOS メインチャット | `ThinkingIndicatorCell` から `StaticThinkingDots` を除去し、孤児化した `ThinkingAnimationModel.dotState`/`DotState`/`period` とドット専用テスト2件を削除。シマー純関数・viewport pause は不変 |
| task-2 | iOS `DSThinkingIndicator` | `DSThinkingAnimationModel` を点滅ドット用（period/dotCount/opacity）から macOS 同型のシマー純関数（`shimmerPhase`/`shimmerBandCenter`/`shimmerBrightness`）へ置換。body を `LinearGradient` シマー化、reduceMotion 時は静的。入力は iOS 慣習の `TimeInterval`。`init(reasoningPreview:)` 不変 |

## スコープ外（不変）

- ダッシュボードの別実装 `AgoraThinkingDots`（`AgentChatRowPolicy`）— 別サーフェスのため今回触らず。
- iOS 呼び出し元 `SessionDetailView` — public API 不変ゆえ無改修。

## 検証

- 客観ゲート（verify-task）: allowed_paths 逸脱なし・verify.sh 再実走 green・開示レポート completed。
- 独立レビュー（persona-reviewer）: iOS 424 tests 再実走 green、MUST/HIGH/MEDIUM 0。純関数の式・定数が macOS 正本と厳密一致・凍結受け入れ非改変・アサーション非弱体化を確認。
- 統合検証: 全4パッケージ green（AgentDomain 167 / PhloxKit 424 / SessionFeature 224 / DashboardFeature 1375、計 2190 tests・0 failures）。
- 未検証: 実機／シミュレータでの視覚確認（描画の滑らかさ・reduceMotion 見た目）は未実施。純関数仕様はテストで担保。

## 蒸留した永続ドキュメント

- [ADR 0067](../adr/0067-thinking-wave-animation-and-viewport-pause.md) に拡張注記（2026-07-20）: 跳ねドット廃止・iOS シマー移植の決定と経緯。タイトルを「サイン波アニメーション」→「シマーアニメーション」へ整合。
- [architecture/chat-mode-ux-components.md](../architecture/chat-mode-ux-components.md) の Thinking インジケータ節を現行（シマーのみ・ドットなし）へ更新。
