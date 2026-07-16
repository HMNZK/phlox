---
status: active
last-verified: 2026-07-15
---

# ADR 0087: モバイル wave-2 ワイヤ拡張（spawn 時モデル適用・プロジェクト付与・エージェント別モデル一覧・アカウント使用量）の設計判断

> **役割**: 契約 [`docs/specs/mobile-api-extensions-contract.md`](../specs/mobile-api-extensions-contract.md) §7 の**サーバー側実装で採った非自明な設計決定**を記録する。
> **書かないもの**: エンドポイントの現行 wire 仕様（→ [`docs/architecture/mobile-proxy.md`](../architecture/mobile-proxy.md)）／§6 モデル**変更**API の判断（→ ADR 0085）／wave-1 拡張の判断（→ ADR 0079）。

## 文脈

iOS 側の新規タスク画面でのモデル選択（spawn 前）、セッション一覧のプロジェクトグルーピング、Usage 画面（アカウント単位の CLI 使用量表示）に必要な内部データ・機構はサーバー側に既存で、**wire 露出だけ**が欠けていた。ADR 0085（§6・セッション**内**でのモデル変更）とは別の要求で、spawn**前**の意思決定に必要な情報を露出する。

## 決定

### 1. spawn 時の model 適用はベストエフォート、不正文字列は黙って無視する

`ControlServer.parseSpawn` は `SpawnBody.model` を `AgentModelCatalog.models(for: kind)` に存在する `id` と完全一致するかで検証し、**不一致は 400 にせず `nil` へ丸める**（`normalizedSpawnModel`）。built-in kind（claudeCode/codex/cursor）のみ対象、custom agent は常に `nil` 固定。`ControlActionHandler.handleSpawn` は spawn で生成された session id が確定した**後**にだけ `model` を適用し、適用失敗はログ警告のみで spawn 自体は失敗させない。

- **なぜ**: spawn はユーザー操作の起点であり、model 指定の誤り 1 つで spawn 全体を失敗させると UX 上の損失が大きい。model 適用は spawn の主目的（セッション生成）に対して副次的機能と位置づけた。
- **代償**: クライアントが誤った model id を送っても `201` で「成功したように見える」が実際は既定モデルのまま。iOS 側は spawn 直後に `GET /sessions/{id}/settings`（§6）で `selectedModel` を確認する手段があるため、致命的な不整合ではないと判断した。

### 2. custom agent は model 選択の対象外

built-in kind（catalog に静的定義がある3種）のみ `pendingSpawnModel` を設定する。custom agent（`AgentRegistry` 経由のユーザー定義 descriptor）は常に `nil` 固定とし、モデル選択の対象から外した。

### 3. `GET /agents/{kind}/models` の codex は意図的に空カタログ

`AgentModelCatalog.models(for: .codex)` は `[]`、`defaultModel` は `nil`。ADR 0085 の「codex はモデル選択非対応」判断を pre-spawn の一覧取得にも一貫して適用した。cursor は provider 連携せず**静的 fallback** カタログ（pre-spawn 時点では生存 session が無く、provider 問い合わせの土台が無いため）。

### 4. `projectId`/`projectName` は欠落時キー省略（null 値ではない）

`ControlSessionListItem` は独自 `Encodable` を持たず標準合成に任せる。`nil` の optional プロパティは JSON 上**キー省略**になる（null 値では出力しない）。iOS 側はキー欠落を `nil` として decode する前提で契約化した。

### 5. `GET /usage` は既存 `UsageMonitor` への weak 参照経由で読み取り専用露出

`ControlDashboardSupport.usageMonitor` は既存 `UsageMonitor` インスタンスへの **weak** 参照（所有権は `composition.usage` 側）。`UsageMonitor` 自体は本拡張で無変更、既存の `usages: [AgentKind: CLIUsage]` をそのまま読むだけ。既存 `GET /sessions/{id}/usage`（ターン単位 costUSD/context、ADR 0079 の契約4）とは別エンドポイントとして独立に追加した。

## 結果

- 契約 §7（4項目）を wire 変更・エスカレーションなしで実装。回帰テスト `Wave2SpawnModelApplicationTests`・凍結受け入れテスト `Wave2WireContractTests`・白箱テスト `Wave2ServerWireWhiteboxTests` で green。
- 未解決: 不正 model 文字列のサイレント無視は、クライアント側に「本当に適用されたか」の確認手段への依存を生む（明示エラーではない）。将来 UX フィードバックが必要になれば 400 化を再検討する余地あり（未対応）。

## 却下した代替案

- **不正 model 文字列を 400 で拒否**: spawn 全体を失敗させるリスクがあるため却下（ベストエフォート優先）。
- **`projectId`/`projectName` を null 値で常時出力**: 既存 iOS クライアントの decode 前提（欠落 = nil）を変える wire 変更になるため、標準合成のキー省略挙動をそのまま契約化した。
