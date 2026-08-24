---
status: accepted
last-verified: 2026-08-21
---

# ADR 0172: Claude のツール許可要求をユーザー承認へ中継する

> **このファイルの役割**: Claude CLI の `can_use_tool` を Phlox の承認カードへ中継し、permission-mode ごとの spawn 引数と失効動作を決める。
> **書かないもの**: Claude セッション全体の spawn / respawn 状態機械（→ [architecture/claude-chat-session-lifecycle.md](../architecture/claude-chat-session-lifecycle.md)）、質問カードの iOS wire ミラー（→ [ADR 0103](0103-user-question-wire-mirror.md)）。

## Context

[ADR 0102](0102-ask-user-question-control-protocol.md) は `AskUserQuestion` だけを保留し、その他の `can_use_tool` を即時 deny していた。その後、Phlox の承認ポリシーが常に `defaultAllowedTools` を spawn 引数へ付ける経路と組み合わさり、Bash・Edit・Write などの通常ツールでは CLI が `can_use_tool` を発行しなかった。Manual や Auto を選んでも通常ツールの承認カードへ到達しないため、ツール単位のゲートが実質無効だった。

## Decision

1. `--permission-prompt-tool stdio` を spawn に常時付け、`can_use_tool` の通常ツール要求も `pendingUserQuestions` へ登録して `.userQuestionRequested` として UI へ中継する。`AskUserQuestion` の回答経路は従来どおり維持する。
2. `preApprovalPolicy` があり、明示 `allowedTools` が無い場合の blanket allow は permission-mode で分ける。
   - `acceptEdits` / `bypassPermissions` / `plan`: `defaultAllowedTools` を適用する（Plan は従来どおり）。
   - `auto` / `manual` / `dontAsk`: `--allowedTools` を付けない。
   - モード未指定 (`nil`) は従来どおり `defaultAllowedTools` を適用し、未知のモード文字列は blanket allow を付けない。
   - 明示された `allowedTools` はどのモードでもその値だけを渡す。
3. 通常ツールの許可カードでは Allow だけを allow とし、元の `pending.input` を `updatedInput` に返す。Deny・未知ラベル・空回答は deny にする。`allowedTools` に含まれるツールと `bypassPermissions` はカードを出さず即時 allow する。
4. 保留要求の close / respawn / interrupt では、該当する旧 transport へ deny を送ってから `.expired` にする。CLI プロセスが既に終了した stream 終了経路では deny を送らず、プロセス死後の無意味な書き込みとユーザー可視エラーを避ける。
5. 承認カードの toolName と input summary は制御文字・方向制御文字を除去し、TAB・改行はスペースへ置換する。summary を 200 文字に制限する場合は `…（全 N 文字）` を末尾に付け、切り詰めを明示する。

## Why

通常ツールの承認を CLI の既存 control protocol に載せることで、承認対象を turn 単位からツール単位へ細かくできる。長命 `-p` プロセスを維持したまま実装でき、モードを選んだユーザーの期待と実際に表示される承認境界を一致させられる。従来の Accept Edits / Bypass / Plan の許可範囲は維持する。

## Rejected alternatives

- **`can_use_tool` の通常ツール即時 deny を維持する**: Manual / Auto でも通常ツールの承認カードが出ず、今回の欠陥を残すため却下。
- **常に `defaultAllowedTools` を付ける**: CLI が許可済みと判断して `can_use_tool` を発行しないため、ツール単位ゲートへ到達できない。却下。
- **turn 単位の pre-approval を per-tool ゲートへ拡張する**: 長命 CLI の spawn 時権限とツールごとの実行要求を対応づけられず、質問単位の Allow / Deny を表現できないため却下。
- **Claude Agent SDK へ全面移行する**: 既存の stream-json、resume、self-heal、transport ライフサイクルの置換範囲が大きく、今回の control protocol 拡張には過剰なため却下。

## Consequences

- Manual / Auto では、明示的に許可したツール以外の通常ツールが承認カードへ到達する。Don't Ask は承認を求めず操作をスキップするため、承認カードによる確認を期待しない。
- Accept Edits / Bypass / Plan は既存の `defaultAllowedTools` による自動許可を維持する。明示 `allowedTools` は引き続き優先される。
- Don't Ask の意味は、CLI 2.1.238 のバイナリ内にある `This session is in Don't Ask mode, so browser actions that need approval are skipped rather than prompted.` という文言から記録した。headless で AskUserQuestion が表示される再現は未実測である。
- process death では保留 permission の deny を送らないため、到達不能な stdin への書き込みエラーを本当の死因エラーへ重ねない。close / respawn / interrupt の明示的な後始末では deny を維持する。
- `PendingToolPermission` は toolName の識別だけを保持し、元の input は共通の `PendingUserQuestion.input` を使う。

## Repository verification

以下はリポジトリのテストとして登録し、決定の境界を固定する。

- `ClaudeChatClientTests`: 明示 `allowedTools` なしでの6モード表（`auto` / `manual` / `dontAsk` は付与なし、`acceptEdits` / `bypassPermissions` / `plan` は `defaultAllowedTools`）と、未知モードの fail-closed、および明示 `allowedTools` の優先。
- `AcceptanceToolPermissionControlTests`: auto-allow、bypass、fail-closed、summary の告知、サニタイズ、stream 終了・respawn・interrupt の失効。
- `ComposerModeMenuAcceptanceTests`: Claude のモード一覧の完全一致。

---
