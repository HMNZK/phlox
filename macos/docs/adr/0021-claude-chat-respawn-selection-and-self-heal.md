---
status: active
last-verified: 2026-07-04
---

# ADR 0021: Claude チャットの respawn 引数は「会話の実在」で選択し、resume 失敗はクライアント内 self-heal で回復する

- ステータス: 採択（2026-07-03・実装完了 / feature/chat-ui-rich）
- last-verified: 2026-07-03
- 関連: ADR 0015〜0017（構造化チャット）。worklog `docs/delivery/0004-claude-chat-first-turn-fix-worklog.md`。現状仕様 `docs/architecture/claude-chat-session-lifecycle.md`。

> コンポーザー設定機能（task-9/11, commit 08f3939）の回帰で、新規 Claude チャットの初回ターンが 100% `error_during_execution` で死んでいた。本 ADR はその根本修正の設計判断を記録する。

## コンテキスト

- `ClaudeChatClient` は設定（model/permission-mode）変更を「次のアイドル時に respawn して反映」する設計。respawn は従来一律 `--resume <currentSessionId>` を使っていた。
- `currentSessionId` は初回 spawn 時に `PHLOX_SESSION_ID` で先取り設定されるため、**会話が 1 つも存在しない初回ターン前の respawn** が `--resume <未存在ID>` になっていた。
- claude CLI の実測（2.1.198・ヘッドレス再現4本＋実機）:
  - `--resume <未存在ID>` → **stdin を待たず起動直後に** `result{subtype:error_during_execution, is_error:true, permission_denials:[]}` を吐いて exit 1（stderr: `No conversation found with session ID`）。
  - `--session-id <既存会話ID>` → `Session ID ... is already in use.` で exit 1（result イベントなし）。
  - → **`--resume`/`--session-id` は「会話の実在」で使い分けが必須**（どちらか一方に寄せることは不可能）。
- さらに `LineDelimitedProcessTransport` は stderr を一切読んでおらず、失敗理由が UI にもログにも出なかった。

## 決定

1. **respawn 引数の選択を状態機械化**する（ClaudeChatClient 内）: 「`resume(sessionRef:)` が呼ばれた」（caller の実在主張）または「success result を受信した」（自己観測）のいずれかが真なら `--resume`、両方偽なら `--session-id <phloxSessionID>`。
2. **resume 失敗はクライアント内で self-heal** する: resume spawn の `error_during_execution` はターンの有無を問わず即時 `.error` にせず stream 終了まで保留し、stderr が `No conversation found with session ID` を含む場合のみ `.error` を出さず `--session-id <ref>` で respawn する。ターン中なら送信済み raw 1 行を再送、ターン外（復元直後の即死）なら待機状態へ戻す。stderr 不一致なら保留エラーを yield（握りつぶさない）。heal 先は `--session-id` spawn のため heal 条件を再び満たさず、**一回性が構造的に担保**される。
3. **transport に stderr tail（上限 64KiB・連続 drain）を追加**し、result なしのプロセス死のエラーメッセージへ含める（`LineDelimitedTransport.stderrTail()`、既定実装 nil で既存 conformer 非破壊）。
4. 修正は **StructuredChatKit＋ClaudeAgentKit に閉じ、呼び出し側（DashboardFeature）は無変更**とする。

## 棄却した代替案

- **resumeID を成功後にのみ永続化する（persistence 意味論の変更）**: codex/cursor と共有する永続化経路への波及が大きく、hooks 不達時に実在会話を fresh 扱いして "already in use" 死する劣化がある。
- **復元時に `~/.claude/projects/` のトランスクリプト実在を直接確認する**: CLI 内部レイアウトへの依存が脆い。
- **self-heal の判定を stderr 文字列に依存させない案**: 「resume spawn の error＝heal」とすると、実在会話の実行時エラーまで `--session-id` respawn して "already in use" で二次死する。stderr 一致を要求し、CLI の文言変更時は透明なエラー表示へフェイルオープンする方を選んだ。

## 結果

- 新規チャット初回ターン・実在会話の復元・会話ゼロセッションの復元（旧 Daffodil）の 3 経路を実機で検証し正常化。凍結受け入れテスト 7＋stderr 3・全 39 tests green・E2E 16 green。
- 既知の残課題: (a) `rate_limit_event` が未知イベント扱いで警告表示される（別件）。(b) 送信失敗時に UI status が running のまま残る VM の papercut（heal 導入で実質的に非発生になるが根治は別件）。
