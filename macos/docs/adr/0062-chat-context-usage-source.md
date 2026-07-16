---
status: active
last-verified: 2026-07-10
---

# ADR 0062: チャットのコンテキスト使用率は result/modelUsage と tokenUsageUpdated から実値供給する

> **このファイルの役割**: 入力欄フッターのコンテキスト使用率ドーナツの分母・分子をどこから取るか（定数ではなく CLI 実値）と、イベント配線で既存 `.turnUsage` を再利用した決定理由。
> **書かないもの**: ドーナツの描画実装（→ Packages/SessionFeature/Sources/SessionFeature/ComposerContextIndicator.swift）、プラン残量（5h/週次）の供給（→ adr/0059・0061、architecture/claude-usage-supply.md）。

## 文脈

チャットモードで「会話がコンテキストウィンドウをどれだけ使っているか」を可視化したい。Claude CLI からウィンドウ最大値を取る手段が自明でなく、当初は定数 200k の仮置きを検討した。ユーザー指示で「Usage 同様に取得できないか」を調査した。

## 決定

- **Claude**: `result` イベントの `modelUsage[<model>].contextWindow` を実値として採用する（CLI v2.1.205 実機確認・実測 200000）。`parseTurnUsage` が `TurnUsage.contextWindowTokens` に格納。複数エントリ（サブモデル併用）時は **input+cacheRead+cacheCreation の消費合計が最大のエントリ**を採用し、同値なら contextWindow が大きい方（辞書列挙順に依存しない全順序）。使用量side は既存トークン明細から UI 側純関数（`ComposerContextGauge`）が導出する。
- **Codex**: 従来 nil 破棄していた `.tokenUsageUpdated` 通知を `NormalizedChatEvent.turnUsage` へマップする。`contextUsedTokens = last.totalTokens ?? total.totalTokens`（直近リクエスト総トークン≒ウィンドウ占有の近似）、`contextWindowTokens = modelContextWindow`。両方 nil なら従来どおり不発。
- **`NormalizedChatEvent` に新 case を追加しない**。`TurnUsage` に optional フィールド2つ（`contextUsedTokens`/`contextWindowTokens`）を後方互換で追加し、既存の `.turnUsage` → `lastTurnUsage` 経路をそのまま使う（Codex はターン中ライブ更新になる副次効果あり）。
- **データが無い場合はドーナツ非表示**（Cursor・旧バージョン CLI・ターン未実行）。分母不明のまま推測表示しない。

## 棄却案

- **定数 200k**: 1M コンテキストモデル等で恒常的に不正確。実値が取れると判明したため棄却。
- **statusLine の `context_window.*`**: 事前計算済みの理想データだがヘッドレス（stream-json）では発火しないことを実機検証で確認。棄却。
- **control_request（initialize/get_usage 等）**: 総当たりで contextWindow 相当が無いことを確認。`get_usage` はプラン課金クォータでコンテキストとは別物。棄却。
- **新しい NormalizedChatEvent case**: 全エージェント Kit の switch 網羅に波及するわりに、既存 `.turnUsage` で意味が足りる。棄却。

## 結果

- 受け入れテスト: AcceptanceContextWindowTests（ClaudeAgentKit）・AcceptanceContextUsageTests（CodexAppServerKit）・AcceptanceComposerContextIndicatorTests（DashboardFeatureTests）が凍結。
- 制約: Claude はターン完了時のみ更新（ターン中のライブ更新イベントが無い）。Codex の last/total は近似であり厳密なウィンドウ占有ではない。
