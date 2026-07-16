---
status: active
last-verified: 2026-07-10
---

# ADR 0066: コンテキスト使用量はセッション単位のサイドカー snapshot で永続化する

> **このファイルの役割**: 復元セッションでコンテキストドーナツが表示されない欠陥への修正で、ChatItem 拡張案を棄却し TranscriptStore のサイドカー snapshot を選んだ決定。
> **書かないもの**: 使用量の供給元（→ ADR 0062）、UI（→ architecture/chat-mode-ux-components.md）。

## 文脈

ドーナツのデータ `ChatSessionViewModel.lastTurnUsage` は `.turnUsage` イベントで置くメモリ値のみで、アプリ再起動後のセッション復元では新しいターンが1回完了するまで表示されなかった（ユーザー報告）。復元直後からの表示には直近ターン使用量の永続化が必要。

## 決定

- `TranscriptStore` に **`loadTurnUsageSnapshot` / `saveTurnUsageSnapshot` を要件として追加**し、プロトコル拡張でデフォルト実装（nil / no-op）を与える（既存準拠実装・テスト用モックを壊さない）。
- `FileTranscriptStore` は転写と同じディレクトリの**サイドカー `<sessionUUID>.usage.json`** へ atomic 書き込み。
- `ChatSessionViewModel` は `.turnUsage` 受信時に fire-and-forget で保存（**costUSD が nil でも保存**＝Codex は cost なしで contextUsedTokens を運ぶ）。`restore` の両経路（claude 系 / codex 系）で転写復元と同段に load し `lastTurnUsage` へ設定する。

## 棄却案

- **`ChatItem.turnCost` に usage を追加**: 参照5ファイル（セル描画・転写ビュー含む）へ波及し、並行タスク（フローティング入力欄）の変更範囲と交差する。転写スキーマの互換管理も増える。棄却。
- **sessions.json への保存**: ChatSessionViewModel は SessionRegistry の書き込み経路を持たず、責務が越境する。棄却。

## 結果

- 受け入れテスト AcceptanceContextUsagePersistenceTests（4件）凍結（ラウンドトリップ・cost なし保存・復元設定）。
- 実機で snapshot 配置→再起動→復元直後のドーナツ表示を確認（2026-07-10）。
- 残余: snapshot は「最後に観測したターン」の値であり、CLI 側で会話が別経路から進んだ場合の鮮度は保証しない（次の `.turnUsage` で上書き）。
