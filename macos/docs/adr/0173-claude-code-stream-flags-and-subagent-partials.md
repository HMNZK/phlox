---
status: accepted
last-verified: 2026-08-21
---

# ADR 0173: Claude Code の stream フラグとサブエージェント部分メッセージ

## 文脈

Claude Code 2.1.238 では、サブエージェント本文を親の stream-json へ転送する
`--forward-subagent-text` と、本文・thinking の部分メッセージを通知する
`--include-partial-messages` を利用できるようになった。従来の完了メッセージ中心の入力から、
部分メッセージを含む入力へ変わるため、既存セッションの表示回数とメインスレッドの負荷特性が変わる。

## 決定

1. `--forward-subagent-text` は常に付与し、`--include-partial-messages` は既定で有効にする。
   部分メッセージが不要な呼び出し元だけは `includePartialMessages: false` で明示的に無効化できる。
2. 部分メッセージと後着する完了メッセージは、メッセージ ID・親の tool_use ID・コンテンツ種別で
   同一系列として扱い、完了本文を二重表示しない。メインとサブエージェントの本文・thinking delta は
   同じ transcript stream coalescer でまとめ、サブエージェント本文の重複比較は累積全文を毎回走査せず、
   初回本文または追記差分だけを空白除去して比較する。
3. ネストした Task/Agent は最も近い tool_use ID に本文・prompt・tool_result を付ける。
   `.subAgentStarted` は親子関係を運ばないため、深さ3のツリーも UI ではフラットな兄弟として表示される。
   ここでいう「ネスト深さ3対応」は階層表示ではなく、孫の本文を失わず最も近い tool_use ID に付ける意味である。
4. `--fork-session` の fork 元 ID は `currentSessionId` に設定せず、CLI の `system.init` が返す新しい
   session ID を正本にする。fork 初期化前の設定変更で fork 元へ `--resume` しない。
5. `mcp_server_errors` は CLI の配列要素 `{name, type, message}` だけを正規化し、想定外形状は無視する。
   同じ warning 本文は安定 ID で置換する。サブエージェント partial の追跡状態は `result` 境界で全廃棄せず、
   `.subAgentCompleted` または `task_notification` で完了を観測した tool_use ID だけを解放する。
   background サブエージェントは launcher の `result` 後も本文を流し続けるため、完了観測まで抑制キーを保持する。

## 棄却案

- **`--include-partial-messages` を既定オフにする** — 既存の完了メッセージ経路だけなら負荷と二重表示リスクは
  小さいが、Claude Code のサブエージェント本文をリアルタイムに表示できず、今回の追随目的を満たさないため不採用。
- **部分メッセージをサブエージェントだけ別経路で即時処理する** — main と subagent で flush と UI 無効化の規則が
  分かれ、token 単位の入力で再びメインスレッドを圧迫するため不採用。
- **MCP エラーの辞書・文字列形状も互換処理する** — 2.1.238 の CLI スキーマに存在しない死にコードを増やすため不採用。
- **サブエージェントの親子関係を `subAgentStarted` へ追加する** — 今回の公開イベント契約を変更して階層 UI まで同時に
  配線する範囲ではないため、最寄り tool_use ID への隔離に限定する。

## 結果

- 既存セッションを含め、Claude の本文・thinking が部分メッセージ単位で表示される。background サブエージェントでは
  launcher の `result` 後に届く本文も同じ item ID へ追記され、完了本文は二重表示されない。完了を観測した ID の
  partial 追跡状態は解放される。
- delta は coalescer でまとめ、重複比較は追記差分の空白除去に限定するため、デルタ数に対する走査量は線形になる。
- ネストしたサブエージェントはフラットなチップとして表示され、深さ1の main user と深さ2以上の child user の
  tool_result を観測すると完了する。
- MCP warning は同じ本文を積み上げず、想定外形状を表示しない。

## 検証

- `ClaudeAgentKit` の `StreamFlagsAndNestedSubAgentTests` で、部分本文・thinking、result 後も続く background 本文、
  完了済み partial 状態の解放、深さ1・深さ2の完了イベント、ネスト隔離、fork 初期化前の respawn、MCP 形状を検証する。
- `SessionFeature` の `SubAgentTranscriptMergeWhiteboxTests` で、transcript 置換時のサブエージェント delta 保全、
  サブエージェント本文の生存信号、完了時の dedup キャッシュ解放、1デルタ単位の空白除去走査量、warning の安定 ID 置換を検証する。
