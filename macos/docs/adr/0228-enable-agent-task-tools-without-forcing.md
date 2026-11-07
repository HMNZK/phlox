# ADR 0228: Claude と Codex のタスクの道具を有効にして起動する（使用は強制しない）

日付: 2026-11-07。状態: 採用。

要件は [specs/agent-status-card.md](../specs/agent-status-card.md)、設計は [specs/agent-status-card-design.md](../specs/agent-status-card-design.md)。[ADR 0226](0226-agent-status-card-derived-from-transcript.md) を補う。

## 文脈

エージェント状態カードは、エージェントが自分で登録したタスクを出す（ADR 0226）。2026-11-07 に、Debug 版と本物の CLI で画面を確かめた。その結果、どちらのエージェントでもタスクが一度も出なかった（`.verification` の実画面の確認）。

- **Claude Code 2.1.319**: Phlox の起動方式（`-p`、stream-json）では、TodoWrite・TaskCreate などのタスクの道具を既定で持たない。環境変数 `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` を渡すと、TaskCreate・TaskUpdate などが遅延読み込みの道具として使えるようになる。
- **Codex 0.167.0**: Phlox の起動方式では計画の道具 `update_plan` が使えない。`-c tools.update_plan.enabled=true` を付けると使える（`codex exec` で確認。既定で無効であることは Codex の資料では確かめていない）。

あわせて、Claude の TaskCreate の結果の読み取りの不具合が見つかった。CLI は結果を `tool_use_result` で返すが、Phlox は `toolUseResult` を読んでいた。

## 決定

- Phlox が起動する Claude には `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` を渡す。
- Phlox が起動する Codex の app-server には `-c tools.update_plan.enabled=true` を付ける。
- 道具を使えるようにするだけで、使うように指示しない。指示の注入やツールの拒否はしない（ADR 0226 の「強制しない」を保つ）。タスクを登録するかはエージェントが決める。
- Claude の TaskCreate の結果は `tool_use_result` を読む。

## 結果

- エージェントがタスクを登録すれば、カードにタスクが出る。登録しなければ、今と同じく「タスク外の作業」だけになる。
- Claude では道具は遅延読み込みなので、会話の容量への影響は小さい見込み（未計測）。
- CLI の版が上がり、既定や変数名が変わると、また出なくなりうる。実画面の確認を版の更新時に繰り返す。
