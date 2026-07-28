---
status: completed
last-verified: 2026-07-24
---

# agent-grid-jank run: 5件修正（transcript 切り詰め・Tasks UI・スラッシュコマンド・通知取りこぼし・グリッド選択）worklog

agentic-loop（backend=codex gpt-5.6-terra effort=high、PM=Claude）による multi run。
ブランチ `feature/agent-grid-jank`（fe7a41c〜）。

## やったこと

| タスク | 内容 | 主な成果物 |
|---|---|---|
| task-1 | transcript の「…」切り詰め廃止と展開時の文字重なり根治 | [ADR 0118](../adr/0118-transcript-text-truncation-overlap.md)・`AcceptanceMarkdownNoTruncationTests` |
| task-2 | Claude Code Tasks（task list）を transcript 内カードで表示 | `AgentTaskList.swift`・`TaskListCell`・`ClaudeChatClient+TaskList.swift`・受け入れテスト2本 |
| task-3 | 組み込みスラッシュコマンド 23 件を収録（/config・/plugin 等。/vim・/terminal-setup・/agents は検証のうえ除外） | `ComposerSuggestions.swift`・`AcceptanceBuiltinSlashCommandsTests` |
| task-4 | 完了・待機通知の取りこぼし修正と APNs no-op 診断化 | [ADR 0119](../adr/0119-session-completion-notification-policy.md)・`SessionNotificationPolicy.swift`・`AcceptanceNotificationGapTests`・`NotificationBridgeDiagnosticsTests` |
| task-5 | グリッド選択枠の視認性・ヘッダー即時選択・入力欄フォーカス連動 | `GridTileBorderPolicy.swift`・`AcceptanceGridSelectionFocusTests` |

architecture 反映: `chat-mode-ux-components.md`（切り詰め廃止・タスクリストカード・スラッシュコマンド・ADR 0119 の例外）・`session-grid-layout.md`（選択枠とフォーカス連動）。

## フェーズ4（統合検証）の裁定

task-4 が ADR 0064 の Codex idle 無視ガードを削除しており、既存凍結テスト
`processingIndicator_codexIgnoresIdleThreadStatusWhileTurnIsRunning`（DashboardFeature）が
fail。ADR 0064 を優先してガードを復元し、復元推定ターン（`turnIsRestoredInference`）のみ
idle 終端＋通知を許す例外で task-4 の目的を維持した（詳細は ADR 0119）。task-4 worktree に
未コミットで取り残されていた白箱テスト `NotificationGapWhiteboxTests.swift` も回収した。

## 検証結果（2026-07-24 実走）

- swift test 全 pass: SessionFeature 364 / DashboardFeature 1454 / ClaudeAgentKit 126 /
  StructuredChatKit 22 / AppBootstrap 141
- `xcodebuild -scheme Phlox -configuration Debug` BUILD SUCCEEDED

## 未検証（ユーザー実機確認が必要）

- task-1: 実 GUI での「…」展開時の重なり解消の目視（機序は受け入れテストで凍結済み）
- task-4: APNs 実機 E2E（Mac で完了 → iPhone に push 到達）
- task-5: 実 GUI でのグリッド操作感（テキスト選択・スクロール・D&D との非干渉）
