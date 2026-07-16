---
status: active
last-verified: 2026-07-04
---

# ADR 0022: 中断の後始末を中立化し、self-heal を双方向＋ターン内上限つきに拡張する

- ステータス: 採択（2026-07-03・実装完了 / feature/chat-ui-rich）
- last-verified: 2026-07-03
- 関連: ADR 0021（respawn 選択と self-heal）を拡張。worklog `docs/delivery/0005-effort-bg-activity-worklog.md`。現状仕様 `docs/architecture/claude-chat-session-lifecycle.md`。

> 実機の Poppy セッション（CLI トランスクリプト実測）で、ADR 0021 の会話実在判定（success のみ）が不足であることと、中断が赤エラー表示になる欠陥が確定した。本 ADR はその設計拡張を記録する。

## コンテキスト（実測）

- ターンを停止ボタンで中断すると、claude CLI は `error_during_execution` の result を返す（Poppy: hello → 2秒後 interrupt → error 表示）。
- **中断/エラーで終わったターンでも CLI は会話ファイルを既に生成している**。よって「success result のみを会話実在の証拠」とする ADR 0021 の規則では、中断後の設定変更 respawn が `--session-id 既存ID` を選び "already in use" で即死する。
- stream は FIFO なので、中断時にターンが開いていた場合、同一世代の次の `error_during_execution` は「そのターンの後始末」と確定できる。

## 決定

1. **会話実在の証拠拡張**: `.sessionId` spawn では任意の result（success/error）受信で実在とみなす。`.resume` spawn の deferred エラー（heal 判定対象）は証拠にしない。
2. **中断の中立化**: 中断時にターンが開いていた場合のみ吸収をアームし、同一世代の次の `error_during_execution` result を1件だけ吸収する（**次の turnStart では解除しない**——後始末は遅延到着しうる。世代交代では解除）。吸収は「前ターンの後始末の消費」であり、**開いている新ターンの状態（currentTurnOpen/currentTurnLine）には一切触れない**（触れると新ターンのプロセス死が silent hang 化し、heal の再送 line を失う——レビューで実証）。
3. **双方向 self-heal**: `--resume 未存在ID` → `--session-id` respawn＋再送（ADR 0021）に加え、`--session-id 既存ID` の "already in use" 死（result なし・stderr 判定）→ `--resume` respawn＋再送を追加。誤判定がどちらに転んでも自己回復する。
4. **ping-pong 禁止**: heal はターンごとに最大1回。2度目の失敗はエラーとして表面化する（session-id⇄resume の無限 respawn を構造的に禁止）。

## 受け入れたトレードオフ

- CLI が中断後始末の result を送らない挙動に変わった場合、新ターンの本物の `error_during_execution` を最大1件吸収しうる（吸収は1回で解除・ターンは後続 result で決着するため実害は限定的）。

## 結果

- 凍結受け入れテスト 7 本（AcceptanceInterruptAndInUseHealTests）で契約を固定。ClaudeAgentKit 53 tests green。
- 実機確認: 停止ボタン→エラー枠なし／中断後の設定変更→再送信正常（フェーズ4）。
