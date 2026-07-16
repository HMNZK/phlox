---
status: active
last-verified: 2026-07-04
---

# ADR 0018: Cursor 会話継続の native session id を Cursor 限定で永続化する

- ステータス: 採択（2026-06-28）— 実装・検証済み（リリース障害是正 run, task D）
- last-verified: 2026-06-28
- 関連: ADR 0016（表示と継続の分離・全 appServer backend で transcript を Phlox 永続化）, ADR 0012（ClaudeCode resumeId ネイティブ追従）

> ADR 0016 は「表示(transcript)は Phlox 永続化、継続(resume)は各 backend のネイティブ機構」を決めた。その「Cursor の継続」経路が未配線で、再起動後に Cursor の会話文脈だけサイレントに破綻していた。本 ADR でその書き戻し方式を決定する。

## コンテキスト

- `PersistedSessionDescriptor.updating(chatNativeSessionId:)` は定義のみで**呼び出し 0 件**だった。Cursor は確定した native session id が descriptor へ書き戻されず、再起動後の復元が空/別セッションを resume していた（リリース障害 D）。
- 復元時の resume id 選択は全 appServer backend で `descriptor.chatNativeSessionId ?? descriptor.codexThreadId ?? descriptor.resumeID`（`DashboardViewModel`）。
- Claude は resumeID=phloxUUID 戦略（ADR 0012）、codex は codexThreadId を継続に使う。

## 決定

1. **ターン確定時に native session id を `chatNativeSessionId` として永続化する**（`SessionPersistenceCoordinator.persistChatNativeSessionID`）。
2. **書き戻しはデータ層で `descriptor.agentRef.builtinKind == .cursor` にゲートする。** Cursor 以外（Claude / codex）は `chatNativeSessionId` を一切書かない。
3. これにより Claude は resumeID（phloxUUID, ADR 0012）、codex は codexThreadId で継続し、`chatNativeSessionId` は nil のまま復元優先からフォールスルーする。

## 結果

- Cursor の会話継続が再起動を跨いで復元される（確定→永続化→再ロード→`resume(sessionRef:)` の往復を回帰テストで固定）。
- Claude / codex の resume は無傷（`chatNativeSessionId == nil` のままで従来フィールドへフォールスルー）。

## 根拠（なぜ Cursor 限定ゲートか）

復元優先順位は全 agent で `chatNativeSessionId` を先頭に見るため、**ゲートしないと Claude が session id を再採番した場合に `chatNativeSessionId` が resumeID(phloxUUID) を上書きし、Claude の resume を壊しうる**。この破壊可能性は独立レビューで指摘され（runtime 依存で「壊れる/壊れない」が割れた）、**「どちらが正しいか」に賭けず Cursor 限定ゲートで争点を構造的に排除する**方針を採った。書き戻しの機構は callback の dead code を除去し NotificationCenter 経路の 1 本に集約した。
