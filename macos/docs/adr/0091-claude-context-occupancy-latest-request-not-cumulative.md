---
status: active
last-verified: 2026-07-17
---

# 0091: Claude のコンテキスト占有量は「最新リクエスト」で近似する（ターン累積ではない）

## 文脈

チャット入力欄（`SessionFeature/ComposerContextIndicator.swift` の `ComposerContextGauge`）の
コンテキスト占有ゲージが、Claude セッションで著しく過大表示された（100万トークンウィンドウで会話開始
直後から 70% 超、20万ウィンドウなら 100% 張り付き。稼働中セッションほど悪化）。

`ComposerContextGauge.resolvedUsedTokens` は、Claude では `TurnUsage.contextUsedTokens` が未設定のため
`inputTokens + cacheReadTokens + cacheCreationTokens` を合算する。これらは `ClaudeChatClient` の
`parseTurnUsage` が **result イベントのターン集計 `usage`** から取得していた。Claude Code の
result.usage の `cache_read_input_tokens` は **ターン内の全 API ラウンドトリップ横断の累積**であり、
ツール呼び出し回数に比例して膨れる（＝現在の占有量ではない）。

実測: 1ターンで各 API コールの実占有 51K〜57K に対し、result 集計の合算は 156K〜640K（3〜11倍）。
Codex 経路（`CodexAppServerClient`）は同じ罠を「Context occupancy は最新リクエストで近似。累積 total より
last を優先」と明示コメント付きで既に回避しており、Claude 経路だけが外れていた。

## 決定

1. **占有量は「直近のメインターン assistant メッセージ」の
   `usage.input_tokens + cache_read_input_tokens + cache_creation_input_tokens` で近似する**
   （＝最新 API コールの入力側＝現在のコンテキスト占有）。`ClaudeChatClient` が turn スコープの
   `currentTurnLatestContextTokens` に記録し、`parseTurnUsage` が `TurnUsage.contextUsedTokens` へ
   明示設定する。result の累積 `usage`（コスト計算に使う生トークン）は変えず、占有量の意味だけを
   「累積」→「現在占有」に修正する。表示側 `resolvedUsedTokens` は `contextUsedTokens` を優先するため、
   composer とモバイル wire（`ControlActionHandler`→iOS）が同時に是正される。
2. **メインターン判定は `(event["parent_tool_use_id"] as? String) == nil` で行う**（キー欠落と JSON null の
   双方をメインとみなす）。実 stream-json のメイン assistant は `"parent_tool_use_id": null` を持ち、
   `JSONSerialization` はこれを **`NSNull`** にするため、`event["parent_tool_use_id"] == nil` は
   **偽**になる（辞書に NSNull 値が存在する）。`== nil` だと本番でメイン usage を取りこぼし、占有量が
   nil のまま累積フォールバックに戻る。既存のサブエージェント隔離分岐が `as? String` を使うのと同じ
   null 安全パターンに揃える。サブエージェント（文字列の親ID）は占有量に数えない。
3. リセットは turn 境界（`turnStart` / `resetConversation` / `spawn`）で行う。

## 棄却した代替案

- **`result.usage.iterations.last` を占有量に使う** — 最新コールの内訳を持つが、`iterations` の有無・構造が
  Claude Code のバージョン依存で不安定。assistant メッセージ単位の usage 追跡の方が版非依存で堅牢。
- **`modelUsage[model]` のトークンを使う** — window（分母）選択には有効だが、内訳トークンは result 集計と
  同じく累積のため占有量には使えない（実測: modelUsage.cacheRead も result.usage.cacheRead と同値の累積）。
- **表示側 `resolvedUsedTokens` のフォールバック合算を消す** — 出所（ClaudeAgentKit）で正しく設定すれば
  フォールバックは実運用で到達しないデッドパスになるため、表示側は変更せず出所のみ直す（最小差分）。

## 結果

- ClaudeAgentKit パッケージ 105/105 green。受け入れテスト `AcceptanceContextOccupancyTests` が
  **実 stream-json 形状（`parent_tool_use_id: null`）**で「最新占有（累積でない）」と「サブエージェント除外」を
  凍結。実データ形状は稼働セッションのトランスクリプトと live stream-json キャプチャで確認済み。
- 教訓（再発防止）: (a) **Claude Code の result.usage は cache_read が往復横断で累積する**——占有量に
  そのまま使わない。(b) **stream-json の `parent_tool_use_id` は null（NSNull）で来る**——キーの有無は
  `== nil` でなく `as? String` で判定する。初版はモックがキー自体を省略していたため (b) を取りこぼし、
  多モデル独立レビュー（Codex）が本番形状の欠陥を検出して是正した。
