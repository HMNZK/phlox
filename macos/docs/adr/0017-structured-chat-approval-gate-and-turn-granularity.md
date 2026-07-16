---
status: active
last-verified: 2026-07-04
---

# ADR 0017: 構造化チャットの承認ゲート配線とツール承認の粒度（turn 単位）

- ステータス: 採択（2026-06-28）— 実装・検証済み（リリース障害是正 run, task A）
- last-verified: 2026-06-28
- 関連: ADR 0015（複数 CLI 共通の構造化チャットバックエンド・承認方式 A1 を採択）, ADR 0012（ClaudeCode resumeId ネイティブ追従）

> ADR 0015 が「承認方式 A1（事前許可）」を採択しつつ **per-tool 承認 UI の配線を MVP スコープ外**とした。その未配線状態が配布リスク（チャットからの無確認シェル実行・ファイル書込み）となっていたため、本 ADR で承認ゲートの配線方式と承認粒度を決定する。

## コンテキスト

dev では構造化チャットのツール実行が無確認で自動実行されていた:
- Claude (`ClaudeChatClient`): 既定 `permissionMode = "acceptEdits"` ＋ 全ツール許可（Bash/Write/Edit/MultiEdit）。
- Cursor (`CursorChatClient`): 起動引数に `-f`（force/trust）をハードコード。
- `AppEnvironment` のクライアント生成箇所（旧 T-SC2/T-SC3 コメント）に「pre-approval policy をここで配線」とあるが未配線。

配布前に「チャットからのツール実行はユーザー承認を介する」状態にする必要があった。

## 決定

1. **承認ポリシー（pre-approval policy）を各 Client に注入し、`AppEnvironment` factory で配線する。** 承認ハンドラの実体は `ChatApprovalBroker`（既存の Codex 承認と同一プラミング）。
2. **安全性は「submit ゲート」に置く。** 拒否時は Claude=`transport.send` 前、Cursor=`runner.run` 前で return し、ユーザー turn を CLI へ渡さない（ツールは実行されない）。
3. **承認時はツールを付与する。** Claude は長命 `-p` プロセスで権限が spawn 時に固定されるため、**preApprovalPolicy がインストールされている場合だけ** spawn 時に `acceptEdits` ＋ `defaultAllowedTools` を付与する。Cursor は承認された turn に `-f` を付与する。policy 不在の既定では一切付与しない（fail-closed）。
4. **承認粒度は turn 単位**（`PreApprovalRequest.summary` ＝プロンプト要約ベース）。Codex の per-command / per-fileChange のような **per-tool 粒度はスコープ外**とする。

## 結果

- 無確認自動実行は解消。承認した turn 内ではツールが走り（per-turn）、拒否すれば一切走らない。
- 承認 API は共有 protocol（`StructuredAgentClient`）ではなく**具象 Client ＋ `AppEnvironment`** に配置した（型 3 重定義の保守負債を受容。共有パッケージ変更のリスク回避を優先）。
- 検証: ClaudeAgentKit / CursorAgentKit / DashboardFeature の swift test で「拒否→未送信/未起動」「承認→許可付き起動」を実副作用（送信バイト・プロセス起動 marker・argv 実ファイル）で固定。App ターゲットの xcodebuild リンク確認済み。

## トレードオフ / 既知の限界

- **per-turn 粒度**: 承認後はその turn 内の複数ツールを個別再承認しない。長命 `-p` プロセスが寿命中に権限を変えられない構造制約の帰結。per-tool 化には claude の `--permission-prompt-tool`（MCP 経由のツール権限照会）等への踏み込みが必要で、別途検討。
- イベント発火順の非対称（deny 時、Claude は `.error` 即時／Cursor は `.turnStarted` の後に `.error`）が残る（安全契約は両者で満たすが UI 状態一貫性の軽微差）。
