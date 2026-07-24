---
status: completed
last-verified: 2026-07-24
---

# 0018: 処理中インジケータ desync 修正 worklog（processing-indicator-desync run / task-1）

「セッションが停止表示になっているのに背景処理（バックグラウンド Bash・サブエージェント等）が動き続ける」ユーザー観測バグを修正した。ADR 0064 が導入した処理中の真実源 `showsProcessingIndicator` を、状態を読む4つの表示面（グリッド/サイドバーのドット・アイコン、Agora 手番、チームタイムライン Thinking）へ、表示専用の実効状態 `displayStatus` として配線した。backend=codex(gpt-5.6-terra) の agentic-loop（N=1・single 相当）で実施。

## 決定・成果物
- 決定: **ADR 0118**（処理中を表す表示面は生 status ではなく displayStatus を読む）。ADR 0064 を拡張、ADR 0081 を参照。
- 実装（`macos/Packages/SessionFeature`・`macos/Packages/DashboardFeature`）:
  - 新規 `Sources/SessionFeature/SessionDisplayStatus.swift`（純関数 `resolve(rawStatus:isProcessing:)` = `(rawStatus == .idle && isProcessing) ? .running : rawStatus`）。
  - 変更 `Sources/SessionFeature/ControllableSession.swift`（protocol に `isProcessing`/`displayStatus` 追加。`displayStatus` は extension 既定実装、`SessionNode.displayStatus` は controllable へ委譲）。
  - 変更 `Sources/SessionFeature/ChatSessionViewModel.swift`（`isProcessing = showsProcessingIndicator`）、`Sources/SessionFeature/SessionViewModel.swift`（PTY: `isProcessing = status == .running`）。
  - 変更（4表示面 → displayStatus）: `SessionGridView.swift`（StatusDot・AgentSessionIcon）、`DashboardSidebarView.swift`（StatusDot・AgentSessionIcon）、`DashboardViewModel.swift`（Agora 手番 `isIdle`）、`TeamTimelineView.swift`（AgoraThinkingPolicy へ渡す状態）。
  - 新規 `Tests/SessionFeatureTests/SessionDisplayStatusWhiteboxTests.swift`（実 VM 構築＋イベント注入の白箱）。
  - PM 著の凍結受け入れ `Tests/SessionFeatureTests/SessionDisplayStatusAcceptanceTests.swift`（resolve 真理値表・コミット 1b88107。ハーネス欠陥修理 191ff25）。
- 追随実装 task-2（Gate② 承認・実行中計数の同種 desync を解消）:
  - 変更 `SessionFeature/Sources/SessionFeature/SessionTree.swift`（`SessionTreeInput`/`SessionTreeNode` に `displayStatus` 面を追加。既定=生 status）。
  - 変更 `DashboardFeature/.../DashboardViewModel.swift`（`runningBreakdown` の計数を `isRunning(node.displayStatus)` へ、`sessionTreeInputs` で `displayStatus: node.displayStatus` を populate）。
  - PM 著の凍結受け入れ `DashboardFeature/Tests/.../RunningBreakdownDisplayStatusAcceptanceTests.swift`（idle+processing→数える / 純 idle→数えない / 生 running→数える・コミット 3f8714f）。
  - `SessionTree` の他消費者（`sessionForest` グリッド・`AgoraParticipantsPolicy`・`TeamTimelineView`）は生 `.status` を読み続け挙動不変（persona-reviewer が実コードで確認）。
  - backend 逸脱: 実質4行のため課金 Codex を起こさず PM 直実装（single-mode）＋ persona-reviewer 独立レビューで担保（decision-log 記録）。
- 不変（変更なし）: `SessionStatus` 型、`showsProcessingIndicator` の定義、DesignSystem の StatusDot/AgentSessionIcon シグネチャ、status の書き込み経路、PTY の表示挙動。

## 状態スナップショット（検証）
- SessionFeature: 335 tests 全 pass。DashboardFeature: 1,457 tests 全 pass（task-1+task-2 合算後・`swift test` を verify.sh で PM 再走）。
- persona-reviewer（ステージ1）: task-1 pass、task-2 pass（62 tests 自走 green・MUST/HIGH/MEDIUM 0）。`agentic-loop-verify-task.sh task-1`: pass:true。
- アプリ全体の xcodebuild（統合ビルド）と実行時 UI 確認は**未実施**。理由: worktree に `macos/Phlox.xcodeproj` が存在せず（生成物 or 別管理で dev ブランチに未コミット）、プロジェクト生成の追加セットアップが要る不釣り合いな作業だったため。統合リスクは分析で代替担保した — `ControllableSession` の準拠型はリポジトリ全体で2つ（`ChatSessionViewModel`・`SessionViewModel`）のみで両方修正済み、`displayStatus` は defaulted な protocol extension、StatusDot/AgentSessionIcon のシグネチャ不変、両パッケージのフル `swift test` 緑＋独立レビュー通過。外部準拠型なし＝アプリ全体のコンパイル破綻リスクはほぼ無い。
- ベースラインフレーク `sessionVM_characterization_sendText_codex_processingObserved_suppressesDiagnostic`（DashboardFeatureTests）が並行負荷下で1度落ち、再走で緑。負荷起因の既知フレークとして記録。

## 残余・後続候補
- （旧 LOW 残件 `DashboardViewModel.runningBreakdown` は task-2 で解消済み。）
- 対象外（別系統・未特定）: interrupt の非対称（SIGINT が claude プロセスの実処理を止めない可能性）、完全なフォアグラウンド Bash 実行中の表示（status は .running のまま）。
- 統合ビルド（xcodebuild）は未実施。プロジェクト生成手順が判明したら build-only（アプリ再起動なし）で1回確認するのが望ましい。

参照: ADR 0118、ADR 0064（拡張元）、ADR 0081（interrupt/述語統一）。
