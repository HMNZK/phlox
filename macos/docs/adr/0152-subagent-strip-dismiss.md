---
status: accepted
last-verified: 2026-08-01
---

# ADR 0152: サブエージェントタブの「閉じる」はストリップからの除去だけを行う

> **このファイルの役割**: ストリップ（上部のサブエージェントタブ列）に残り続けるタブを、ユーザーが
> 閉じられるようにした決定と、その「閉じる」がどこまで消すかの線引き。
> **書かないもの**: サブエージェント表示の全体構造（→ [architecture/chat-subagent-display.md](../architecture/chat-subagent-display.md)）、
> タイル選択の入力経路（→ [ADR 0153](0153-pane-tile-click-selection.md)）。

## 文脈

サブエージェントは `status != .completed` の間ストリップに残る（`stripSubAgents`）。完了すれば自動で
消えるが、**エラー終了（`.failed`）したものは残り続ける**——`failRunningSubAgents()` は状態を `.failed`
へ書き換えるだけで、配列からは取り除かない。これは「失敗に気付けるように残す」という意図的な設計
だったが、気付いたあとに消す導線が存在しなかったため、失敗タブがセッションの寿命いっぱい居座り、
タブ列を圧迫していた。

## 決定

**ホバー時のみ現れる閉じるボタンをタブに置き、押下でそのサブエージェントを「ストリップからだけ」
取り除く。**

1. `ChatSubAgentModel.dismissSubAgent(id:)` を追加する。閉じた id は sticky に記録し、`stripSubAgents`
   から除外する。**`subAgents` 本体からは取り除かない**——完了済みサブエージェントと同じく、本文の
   インラインマーカー（`subAgentMarker`）とドロワーからの閲覧経路を残すため。
2. 閉じた id は sticky なので、後着イベント（`subAgentCompleted` 等）で同じ id が更新されても
   ストリップへ復活しない。「消したのに戻る」を構造的に防ぐ。
3. 閉じた対象が選択中なら `selectedSubAgentId = nil`（メインへ戻す）。選択中でなければ選択は変えない。
4. **永続化しない**。サブエージェントはライブのストリームイベントからのみ積まれ、保存済み
   トランスクリプトから復元されないため、アプリ再起動でストリップは空から積み直される。
   閉じた事実を保存する必要がない。

## 検討した代替案

- **`.failed` を自動でストリップから除外する**: 気付く前に消えるため、失敗を残す元の意図を壊す。採らない。
- **`subAgents` 本体から削除する**: 本文マーカーとドロワーの参照先が消え、履歴を失う。採らない。
- **常時表示の閉じるボタン**: タブ幅を常に消費し、既存の `ChatMessageCopyButton` のホバー流儀と揃わない。

## 結果

- ホバーしていないときはボタンが不可視かつヒットテストを受けない（`SubAgentDismissButtonPresentation`
  として純粋関数に切り出し、テストで凍結）。
- 3 つの呼び出し元（単一表示 `ChatSessionView`・グリッド `GridChatColumn`・`SessionActivityOverlayStrip`）
  すべてで同じ `SubAgentStrip` を通るため、配線は 1 か所。
- 既存契約（`completed` はストリップから除外・`subAgents` には残す＝`SubAgentStripFilterAcceptanceTests`）は不変。
- 受け入れテスト: `SubAgentDismissAcceptanceTests`（DashboardFeature）。
