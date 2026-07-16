---
status: active
last-verified: 2026-07-05
---

# ADR 0031: チャット履歴リバートは「ローカル転写の切り詰め＋会話リセット＋文脈リプレイ」で実現する

## 文脈

チャットモードに「esc 2連打で過去のユーザーメッセージを選び、その時点まで会話を巻き戻す」（Claude Code の rewind 相当）を要求された。前提調査（2026-07-05）の結果、統合済み 3 エージェントのいずれも**特定メッセージ時点への文脈巻き戻しを公開 API で提供しない**:

- claude CLI: `--resume <id>` / `--fork-session` はセッション全体の再開・分岐のみ（メッセージ粒度なし）
- cursor-agent: `--resume <chatId>` のみ
- codex app-server（本リポジトリの client kit が包む範囲）: thread の rollback/fork API なし

## 決定

全エージェント一律で次の方式にする（`ChatSessionViewModel.revert(toUserMessageID:)`）:

1. **ローカル転写を切り詰める**: 選択 userMessage の直前まで（当該メッセージと以降を除去）。`TranscriptStore.replaceTranscript` で永続側も同一化（追記キューを flush してから replace＝順序保証）。
2. **CLI 側は新規会話へリセット**: `StructuredAgentClient.resetConversation()`（既定 no-op）を各クライアントが実装——Cursor=`resumeSessionId` クリア（次 spawn から `--resume` が外れる）、Claude=transport close→resume なし新規 spawn、Codex=直近 thread/start 引数で新 thread 開始（`threadResume` 時も再開始用 params を捕捉。復元セッションでも reset 可能）。
3. **次回送信時に文脈リプレイ**: 保持転写から user/agent メッセージを整形したプリアンブル（上限 12,000 字・古い側から切り捨て）を **client への入力にのみ** 前置する。UI 表示と store には新規入力のみを記録。リプレイは 1 回きり（送信成功後にクリア。送信 throw 時は保持され再送で 1 回だけ適用）。

## 棄却した代替案

- **claude のセッション JSONL を直接切り詰めて `--fork-session` 再開**: CLI 内部フォーマットへの依存が強く壊れやすい。claude 専用になり他 2 エージェントと非対称。
- **ローカル転写のみ巻き戻し（CLI 文脈は放置）**: エージェントが「巻き戻したはずのターン」を記憶し続け、以降の応答が UI と乖離する。無音の不整合は許容しない。
- **Claude のみ完全対応・他は機能非表示**: UX の一貫性を優先し、能力差はリプレイ合成で均す方をとった（ゲート①のユーザー選択「全エージェント・可能な範囲で」）。

## 結果

- 文脈の忠実度は「転写からの再構成」の範囲（ツール実行の内部状態や 12,000 字超の古い文脈は失われる）。完全パリティではないことを明示して受け入れる。
- reset 境界の一貫性がハザード: 旧 thread/セッション宛ての遅延イベントは adapter 層（threadId 不一致 drop）＋ VM 層（threadId ガード・nativeSessionId 採用条件）の多層で遮断する（差し戻しレビューで穴を検出→修正済み）。
- esc UI（1回=中断・2連打=ピッカー・1.5 秒窓・running 中の確定は先に中断完了）を含む挙動の正本はコードと受け入れテスト（`ChatRevertAcceptanceTests` / `EscapeKeyStateMachineAcceptanceTests`）。
- 将来 CLI がメッセージ粒度の rewind API を出したら、`resetConversation` の実装を差し替えるだけで方式を昇格できる（プロトコル境界は維持）。
