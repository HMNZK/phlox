---
status: completed
last-verified: 2026-07-19
---

# 0010: AskUserQuestion 対応（iOS ミラー実装）worklog

macOS 側 run（[macos/docs/delivery/0008](../../../macos/docs/delivery/0008-ask-user-question-worklog.md)）の task-4。Claude チャットの `AskUserQuestion` 質問カードを iOS（PhloxMobile）へミラーした。実装は Cursor（standard）、レビューは二段構え（stage1/stage2）とも pass。

## やったこと

- `ChatMessage` に `userQuestion` ケースを追加し、`ChatMessageDTO.toDomain()` で `type == "userQuestion"` を前方互換デコード（必須フィールド欠落・未知 state は nil で除外）。
- `PhloxAPIClient.respondToQuestion(sessionID:requestId:answers:)` で `POST /sessions/{id}/question` を送信。
- `SessionDetailViewModel.answerQuestion` が API 成功後にのみローカルの pending→answered 置換を行う楽観更新。
- `UserQuestionCard`（新規 SwiftUI View）を `SessionDetailView` へ配線。single/multi とも確定ボタン方式、自由入力優先。
- `PhloxQuestionWireContract.implemented` を `false → true` へ反転（wire キー定数はこの1行以外無改変）。

3つの設計判断（デコード方針・楽観更新の順序・カード操作様式）の詳細と理由は [iOS ADR 0024](../adr/0024-user-question-card-mirror.md) 参照。

## 検証

- `swift test --package-path ios/Packages/PhloxKit --no-parallel` → 396 tests green（凍結受け入れ2スイート `UserQuestionDecodingAcceptanceTests`（4件）・`UserQuestionAnswerAcceptanceTests`（5件）含む。stage1 レビューが自分で実走確認）。
- 凍結受け入れテスト2ファイルは契約凍結時点（ec1082b）から無改変（`git diff` で確認済み）。
- MUST/HIGH/MEDIUM 指摘なし。LOW 情報1件（incremental delta 経路での state 収束の既知制約。task-4 導入ではなく既存の全メッセージ種共通の挙動）。

## 状態

- feature ブランチへ統合済み（7deb17b。macOS 側 `feature/ask-user-question` へ ff マージ済み）。
- 実 Claude セッションでの E2E は未検証（macOS 側 run 全体の制約。[macos/docs/delivery/0008](../../../macos/docs/delivery/0008-ask-user-question-worklog.md) 参照）。
- iOS デバッグビルド成功を確認済み（macOS 側 run の統合検証フェーズで実施）。
- 積み残しなし。iOS 固有の追加設計判断（デコード前方互換・成功後楽観更新・確定ボタン式 UI）は [iOS ADR 0024](../adr/0024-user-question-card-mirror.md) に蒸留済み。
