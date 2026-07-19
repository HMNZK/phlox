---
status: completed
last-verified: 2026-07-19
---

# 0006: UI 修正バッチ（Usage アイコン化・入力欄ハイライト・Thinking シマー・サブエージェント集約）worklog

agentic-loop（backend=external）による UI 修正4件の run 記録。実装は外部エージェント（Codex ヘッドレス）へ委譲、PM（Claude）が契約凍結・レビュー・統合・蒸留を担当。

## この run でやったこと

| task | 難度 | 内容 | 主な変更 |
|---|---|---|---|
| task-1 | standard | 右サイドバー Usage のエージェント名をブランドアイコン化＋「N日前」鮮度注記テキストの撤去（dimming は維持） | `UsageSidebarView.swift`・`UsageTopBarView.swift`（`AgentKindBadge`→`AgentBrandIcon`、可視 `Text(staleNote)` 3件削除） |
| task-2 | deep | チャット入力欄（NSTextView 実装）で `/`コマンド・`@`参照を前景色ハイライト | 新規純関数 `ComposerHighlight.spans(in:)`＋`ChatComposer.swift` の `textStorage` 属性適用（IME 変換中は非適用・選択/undo/typingAttributes を保護・UTF16 オフセット） |
| task-3 | deep | 「Thinking...」テキストに明度が左→右へ流れるシマー | `ThinkingAnimationModel` に純関数 `shimmerPhase`/`shimmerBrightness`＋`ChatMessageCells+Structured.swift` の `LinearGradient` mask 適用（ADR 0067 準拠） |
| task-4 | standard | サブエージェント右ペインのツールコールを1つの折りたたみカードに集約（メイン同等） | `SubAgentDrawerView.swift` の `transcriptBody` を `ChatTranscriptGrouping.blocks`＋`CommandGroupCell` 配線へ変更（既存の集約ロジックを再利用） |

## 蒸留した永続知見

- [ADR 0099](../adr/0099-usage-staleness-note-text-removed-keep-dimming.md): Usage 鮮度注記の可視テキスト撤去（ADR 0039 の可視注記部分を一部覆す。dimming と行常時表示は維持）。
- [ADR 0067](../adr/0067-thinking-wave-animation-and-viewport-pause.md) に拡張注記: Thinking シマーを同 ADR の純関数方針で追加（task-3）。
- task-2/task-4 は既存資産（NSTextView 属性適用の作法／`ChatTranscriptGrouping`＋`CommandGroupCell`）の実装・再利用であり、新規 ADR は起こさない。

## 検証（客観シグナル）

- 凍結受け入れテスト（PM 著・不変）: `AcceptanceComposerHighlightTests`（9件・task-2）／`AcceptanceThinkingShimmerTests`（7件・task-3）を先に red-for-the-right-reason で確認し凍結。
- 独立レビュー（persona-reviewer）: 全4件 pass。MUST/HIGH/MEDIUM ゼロ（deep 2件に到達不能な理論エッジ等の LOW メモのみ）。
- 統合検証: 統合後の全走で SessionFeature 190件／DashboardFeature 1383件すべて green。
- 目視: Debug ビルドで task-4 の集約カード（「ツール実行 ×N」）と task-3 の Thinking 描画を確認。残りはユーザーが実機確認（「確認完了」）。
- マージ: `feature/ui-fixes`（06164f9）を `dev` へ fast-forward 済み。

## 状態スナップショット / 積み残し

- **task-6（AskUserQuestion のデスクトップ/モバイル正しい表示）は本 run 対象外**。スコープ A2（表示だけでなく回答配送まで含む対話対応）でユーザー承認済みだが、wire 契約（DTO/REST）拡張・回答配送経路の設計調査が要る規模のため、設計フェーズ付きの別 run に切り出す。
- task-2 の横展開（`TeamComposer`/Agora のチーム入力欄ハイライト）は意図的に先送り（本 run はメイン `ChatComposer` のみ）。

## run 運用の教訓

- `debug-build-restart.sh` はセッションをホストしているリリース版 Phlox を終了して Debug 版に差し替えるため、目視のためにこれを回すとリリース版が自動復帰して二重起動（hook/control ポート競合）を招く。目視は Debug 版単体でなく、二重起動の後始末（どちらを残すか）まで含めてユーザーと合意してから行う。
