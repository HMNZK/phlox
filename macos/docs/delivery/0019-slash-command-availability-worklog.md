---
status: completed
last-verified: 2026-07-26
---

# slash-command-availability run: 補完候補をセッションの提供一覧に一致させる worklog

agentic-loop（backend=codex gpt-5.6-terra、PM=Claude）による multi run。
ブランチ `feature/slash-command-availability`（b0e91f4〜6f5f750）。

きっかけは 1.3.2 リリース直後のユーザー報告「`/plugin` も `/config` も対応できていない」。
補完から選べるのに `/plugin isn't available in this environment.` が返っていた。
詳細な決定と実測値は [ADR 0120](../adr/0120-slash-suggestions-from-session-init.md)。

## やったこと

| タスク | 内容 | 主な成果物 |
|---|---|---|
| task-1 | 公開イベント `NormalizedChatEvent.availableCommandsUpdated(commands:)` の追加 | `StructuredChatTypes.swift`・`AcceptanceAvailableCommandsEventTests` |
| task-2 | Claude の `system`/`init` が運ぶ `slash_commands` の正規化 | `ClaudeChatClient+EventParsing.swift`・`AcceptanceInitSlashCommandsTests` |
| task-3 | 候補生成を一覧ベースへ（静的フォールバックを 23→10 件に是正）＋ViewModel 保持 | `ComposerSuggestions.swift`・`ChatSessionViewModel.swift`・`AcceptanceBuiltinSlashCommandsTests`・`AcceptanceComposerAvailableCommandsTests` |
| task-5 | View 配線（chat・grid 双方の composer へ届ける） | `ChatComposer.swift`・`GridChatColumn.swift`・`ComposerWiringWhiteboxTests` |
| task-6 | provider シグネチャ変更への DashboardFeature テストの追随 | `AsyncSlashSuggestionAcceptanceTests`・`AsyncSlashWhiteboxTests` |

architecture 反映: `chat-mode-ux-components.md` の「組み込みスラッシュコマンドのサジェスト」節を
「セッションの提供一覧が正本」へ差し替え（旧記述は実測で反証されたため STALE 除去）。

## 計画変更（ゲート②を2回通した）

1. **task-4 の分割**: task-1 の独立レビューが「公開 enum への case 追加で
   `ChatSessionViewModel.swift` の網羅 switch が壊れ SessionFeature がビルド不能。しかも
   そのファイルは task-3 の allowed_paths 外」と指摘。ViewModel 側（task-4）と View 配線
   （task-5）へ分けた。
2. **task-3 と task-4 の統合**: 分けた直後に、両者の受け入れテストが同一テストターゲット
   （SessionFeatureTests）に同居しており片方だけでは**どちらのテストも実走できない**と判明。
   タスク単位の検証ゲートが機能しないため統合し task-4 を削除した。

**教訓**: `allowed_paths` の交差ゼロ（ファイル単位）は並列可能性の十分条件ではない。
**同一テストターゲット・同一の網羅 switch といった「コンパイル単位の結合」も分割可能性の
判定に入れる**必要がある。

## 凍結契約の差し替え（PM 権限）

1.3.2 で凍結した `AcceptanceBuiltinSlashCommandsTests` は「`/config`・`/plugin` を含む
組み込み一式を静的に載せる」「`/agents` は載せない」を要求していたが、実測で両方とも
反証された。反証済みの契約を残すと実装側が「使えないコマンドを載せ続ける」ことを
強制されるため、PM 権限で契約を差し替え、旧契約を符号化していた
`BuiltinSlashCommandsWhiteboxTests.swift` は削除した（実装役にアサーション変更は許可していない）。

## 検証結果（2026-07-26 実走）

- クリーンビルドでの全パッケージ実走: 16 パッケージ **2862 tests / 0 failures / 0 skips**
- `xcodebuild -scheme Phlox -configuration Debug` **BUILD SUCCEEDED**
- 実機ビジョン検証（1.3.2 Debug ビルド・pid 隔離）:
  初回送信で init 到着後、チャット・グリッド双方の補完で `/plugin`・`/help` が出ず、
  `/agents`・`/effort`・`/fast`・`/recap` とユーザーのスキルが出ることを目視確認。

**クリーンビルド必須**: 公開 enum に case を追加した後、リポジトリ内 `.build` の古い成果物と
食い違い CursorAgentKit のテストプロセスが signal 11 で決定論的にクラッシュした（3/3 再現）。
`swift package clean` またはスクラッチパス指定後は 31 件全 pass。統合検証は必ずクリーンで行う。

## 副次的に直したもの

- DashboardFeature の Claude 使用量テスト 3 件が、実機に残った
  `phlox.usage.claudeScrape=false`（`UserDefaults.standard`）を読んで落ちていた。
  テストごとに固有の defaults suite を注入して隔離（アサーションは不変）。1.3.1 から
  潜在していた machine-local 依存で、今回の変更とは無関係。

## リリースノートの訂正

1.3.2 は「組み込みスラッシュコマンドを補完に収録」と謳って公開済みだったため、
GitHub Release と `site/appcast.xml` の該当項目を実態（存在しないコマンドを含んでいた旨）に
合わせて訂正し、phlox.cc が訂正版を配信していることを確認した。本 run の修正は次リリースに載る。

## 未検証

- Codex / Cursor セッションでは一覧の供給源が無く、静的フォールバック 10 件のまま
  Claude 固有候補が出る（別 run で扱う）。
