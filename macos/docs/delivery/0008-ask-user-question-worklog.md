---
status: completed
last-verified: 2026-07-19
---

# 0008: AskUserQuestion 対応（control protocol・macOS 質問カード・wire 配線）worklog

agentic-loop（backend=external・mode=multi）による run 記録。Claude チャットの `AskUserQuestion` ツール（選択肢提示→回答返送）対応を、CLI control protocol の最小実装から macOS UI・wire 配線まで一気通貫で追加した。実装バックエンドは external（standard=Cursor / deep=Codex）、フェーズ0/1/4/5 とステージ1レビューは PM（Claude）。

## この run でやったこと

| task | 担当 | 内容 | 主な変更 |
|---|---|---|---|
| task-0 | PM 直接実装 | 共有契約の骨組み＋凍結受け入れテスト（task-1〜4 契約）。Swift はテストモジュール全体がコンパイルできないと受け入れテストを実走できないため、共有型・enum ケース・全網羅 switch の最小アーム・スタブ API を walking skeleton として著した | `ChatItem`/`ChatMessage` 新ケース、`StructuredChatTypes.swift`、`ControlQuestionWireContract` 骨組み |
| task-1 | Codex（deep） | ClaudeAgentKit control protocol — `can_use_tool` 受信・`control_response` 送信・AskUserQuestion 中継 | `ClaudeChatClient+ControlProtocol.swift`（新規）、`Respawn.swift`（`--permission-prompt-tool stdio`） |
| task-2 | Cursor（standard） | macOS 質問カード — VM 状態遷移・`UserQuestionCell` UI・回答返送配線 | `ChatSessionViewModel.swift`、`UserQuestionCell.swift`（新規） |
| task-3 | Cursor（standard） | wire 配線 — `userQuestion` DTO・`POST /question` ルーティング・dashboard 転送 | `ControlActionHandler.swift`、`ControlServer.swift`、`ControlQuestionWireContract.swift`（`implemented` 反転） |
| task-4 | Cursor（standard） | iOS ミラー実装（[iOS worklog 0010](../../../ios/docs/delivery/0010-ask-user-question-worklog.md) 参照） | — |

レビューは全task二段構え（stage1=独立レビュー、stage2=最終判定）。凍結受け入れテストの無改変は各段で `git diff` により独立確認した。

## 主要な検出と修正

- **task-1 stage2 MEDIUM（608db5b）**: `interrupt()` の deny 対象スナップショットが `isResponding`（allow 送信 suspend 中）を除外しておらず、同一 `request_id` へ allow+deny の二重 `control_response` が届きうるレース。deny 対象フィルタに `!isResponding` を加える1行で修正。競合再現テストで red（`["deny","allow"]`）→ green を実証。
- **task-2 stage1 MUST（0ca0431）**: `ChatSessionViewModel.respondToUserQuestion` の pending 判定が `await client.respondToUserQuestion(...)` をまたいで再検証されず、真の同時呼び出しで二重に true が返り transcript の answers が競合上書きされうるレース。送信中 requestId 集合（`respondingUserQuestionIds`）による `@MainActor` 同期ガードで修正。gate 付き fake client の競合再現テストで red（両方 true・2回送信）→ green を実証。
- **task-3「実アプリ経路は常時404」の裁定**: 実装者は App 層の `ControlActionDashboard` witness 未実装を開示したが、Swift の retroactive conformance 規則（型自身のモジュールの同シグネチャ public メソッドが自動 witness し、protocol extension default は使われない）により**誤りと裁定**した。stage1 の swiftc 3モジュール実験と stage2 の `sendMessage` 前例（2026-07-12 実クラッシュ）照合で独立に裏取り。App 層への転送ラッパ追加を明示的に禁止した（詳細は [ADR 0103](../adr/0103-user-question-wire-mirror.md)）。

いずれも「実装者の自己申告どおりに終わらせず、レビューで検証してから確定する」プロセスで拾えた。詳細は [ADR 0102](../adr/0102-ask-user-question-control-protocol.md)（control protocol・二重応答ガード）、[ADR 0103](../adr/0103-user-question-wire-mirror.md)（wire ミラー・App 層 witness）を参照。

## 最終状態

- 7パッケージ合計 2,376 テスト green（`ClaudeAgentKit` 116・`StructuredChatKit` 22・`SessionFeature` 205・`DashboardFeature` 1384・`AppBootstrap` 140・`ControlServer` 113・`PhloxKit`（iOS）396。フェーズ4で全パッケージ `--no-parallel` の全数スイープを実走、各 task の個別実走は stage1/stage2 レビューでも独立確認）。
- 凍結受け入れテスト（task-0〜4 契約）は全task で無改変（`git diff` で差分ゼロを都度確認）。
- macOS デバッグビルド・iOS デバッグビルドとも成功。
- **実 Claude セッションでの E2E は未検証**（課金となるためフェーズ0の方針どおり別途承認時のみ実施とし、本 run ではモック transport / fixture 検証まで）。

## 状態スナップショット / 積み残し

- 生の CLI（SDK 不使用）が実際に `--permission-prompt-tool stdio` を尊重するか、二重 `control_response` を CLI 側がどう扱うかは実セッションでの確認待ち。
- レビューで LOW と裁定された残課題（interrupt 中の同世代 `can_use_tool` の握り・malformed AskUserQuestion / 重複 request_id での無応答）は契約外の稀ケースとして未対応（[ADR 0102](../adr/0102-ask-user-question-control-protocol.md) 参照）。
- feature ブランチへの統合はマージスクリプト＋一時 detach 方式（task-1 統合時に確立。以後の task→feature 統合すべてに適用）。全4task done、`feature/ask-user-question`（25234ab）まで ff 統合済み。
