---
status: active
last-verified: 2026-07-15
---

# Phlox ⇔ Phlox-mobile API 拡張契約（凍結版 v1）

Phlox 本体（サーバー側、`feature/mobile-api-extensions`）と Phlox-mobile（クライアント側、`feature/chat-parity-review-fixes`）が**独立に実装するための凍結契約**。両側の受け入れテストはこの JSON 形状を共通フィクスチャとして使う。変更が必要になったら実装を続けず、両 run の PM 間で改版を合意してから進める（改版は v2 として本ファイルに追記し、旧節を superseded 表記にする）。

共通事項:
- 認証: 既存エンドポイントと同一（`Authorization: Bearer <token>`。不正は 401）
- セッション ID: パスセグメント。UUID 形式（既存 `parseSessionID` と同じ percent-decode → UUID）
- エラー body: 既存の `{"error": "..."}`（ErrorDTO）に合わせる

## 1. POST /sessions/{id}/interrupt — 実行中ターンの停止

- 成功: **204 No Content**（interrupt を受理。完了を待たない）
- セッション不在: 404
- interrupt 非対応のセッション（PTY 等、構造化クライアントを持たない）: **409** + `{"error":"interrupt unsupported"}`
- 冪等: running でないセッションへの interrupt も 204（no-op）

## 2. GET /sessions/{id}/subagents — サブエージェント一覧

- 成功: 200
```json
{
  "sessionId": "5E0C7C6A-…",
  "subAgents": [
    {
      "id": "sa-1",
      "name": "explore-map",
      "status": "running",
      "messageCount": 12,
      "markerMessageId": "msg-42"
    }
  ]
}
```
- `id`: サブエージェント参照子（後続 3. のパスセグメントにそのまま使える不透明文字列）
- `status`: `"running" | "completed" | "unknown"` の3値
- `markerMessageId`: `/messages` 本文中の type=subAgent メッセージの `id` と一致する対応付け（対応が取れない場合は省略可）。**モバイルはこれで「行タップ→サブエージェント詳細」を解決する**
- サブエージェントが無い場合: 200 + `"subAgents": []`
- 構造化チャット非対応セッション: 404（既存 `/messages` と同じ）

## 3. GET /sessions/{id}/subagents/{subAgentId}/messages — サブエージェントのトランスクリプト

- 成功: 200。**body 形状は既存 `/messages` と同一**（`messages` は既存 ChatMessageDTO の配列）:
```json
{ "sessionId": "5E0C7C6A-…", "subAgentId": "sa-1", "messages": [ { "id": "m1", "type": "agent", "text": "…" } ] }
```
- 不明な subAgentId: 404

## 4. GET /sessions/{id}/usage — 直近ターンのコスト・コンテキスト使用量

- 成功: 200
```json
{
  "sessionId": "5E0C7C6A-…",
  "turn": {
    "costUSD": 0.1234,
    "contextUsedTokens": 45678,
    "contextWindowTokens": 200000
  }
}
```
- まだターンが無い/取得不能: 200 + `"turn": null`
- `turn` 内の各フィールドは欠落可（nullable）。クライアントは欠落を「不明」として表示しない
- 構造化チャット非対応セッション: 404

## 5. POST /send の画像添付拡張

- 既存 body `{"to","text","submit","inReplyTo"}` に **追加フィールド `images`（省略可）**:
```json
{ "to": "5E0C7C6A-…", "text": "この画面を見て", "images": [ { "mediaType": "image/png", "dataBase64": "iVBORw0…" } ] }
```
- 制限（デスクトップ ComposerAttachments と同一）: 最大 **4 枚**・1 枚あたりデコード後 **4 MiB**・合計 **8 MiB**。超過は **413** + `{"error":"attachment too large"}`
- `mediaType` は `image/png` / `image/jpeg` を必須サポート
- 画像添付非対応のセッション（PTY 等）: **409** + `{"error":"images unsupported"}`
- `images` が空配列または省略なら従来と完全に同一挙動（後方互換）

## 6. GET /sessions/{id}/messages の差分取得拡張（ポーリング改善）

- 既存レスポンスに **追加フィールド `cursor`（常に付与、不透明文字列）**:
```json
{ "sessionId": "…", "messages": [ … ], "cursor": "c-000042" }
```
- **`?since=<cursor>`**（省略可）: 指定 cursor より後のメッセージのみを返す（無ければ `"messages": []`）。**既存メッセージの編集・置換が起きた場合は全量スナップショット（since 無視）へフォールバックしてよい**（その場合もレスポンス形状は同じ。クライアントは「since 指定時も全量が来ることがある」前提で、返却 messages の先頭 id が手元と重複したら全量置換として扱う → 判定を単純化するため、**全量フォールバック時はレスポンスに `"snapshot": true` を必ず付ける**）
- **`?wait=<seconds>`**（省略可、1〜25 秒に clamp）: since 以降の新規メッセージが無い間は最大 wait 秒待って返す（long-poll）。タイムアウト時は `"messages": []` と現行 cursor
- 不正・期限切れ cursor: 400 にせず全量スナップショット（`"snapshot": true`）で応答
- `since` も `wait` も無ければ従来と完全に同一挙動＋`cursor` 付与（後方互換）

## モバイル側の公開 API 面（PhloxAPI プロトコル拡張・凍結）

```swift
// PhloxCore（新型）
public struct SubAgentSummary: Sendable, Equatable { id, name, status(SubAgentStatus), messageCount, markerMessageID: String? }
public enum SubAgentStatus: String, Sendable { case running, completed, unknown }
public struct TurnUsage: Sendable, Equatable { costUSD: Double?, contextUsedTokens: Int?, contextWindowTokens: Int? }
public struct MessagesDelta: Sendable, Equatable { messages: [ChatMessage], cursor: String?, isSnapshot: Bool }
public struct SendAttachment: Sendable, Equatable { mediaType: String, data: Data }
// SendRequest は images: [SendAttachment] を追加（既定 [] で後方互換）

// PhloxAPI プロトコル（追加メソッド。実装まで既定実装が server(501) を throw）
func interrupt(sessionID: String) async throws
func subAgents(sessionID: String) async throws -> [SubAgentSummary]
func subAgentMessages(sessionID: String, subAgentID: String) async throws -> [ChatMessage]
func usage(sessionID: String) async throws -> TurnUsage?
func messagesDelta(sessionID: String, since: String?, wait: Int?) async throws -> MessagesDelta
```

## 検証の分担

- **サーバー側 run（Phlox / feature/mobile-api-extensions）**: 上記 1〜6 の wire 挙動を AppBootstrapTests / ControlServerTests の既存ハーネス流儀で受け入れテスト化し green にする
- **モバイル側 run（Phlox-mobile / feature/chat-parity-review-fixes）**: 上記 JSON をフィクスチャに URLProtocol スタブで PhloxAPIClient の各メソッドをテストし green にする
- **統合（フェーズ4）**: 両ブランチを突き合わせ、実サーバーに対する実機/シミュレータ疎通で確認する

## 6. モデル選択 API（2026-07-14 追加・実装済み）

セッションのモデルをモバイルから参照・変更する。ワイヤ定数の正本はコード側の
`ControlModelWireContract`（macOS `ControlServer`）と `PhloxModelWireContract`（iOS
`PhloxNetworking`）で、両者は一字一句一致（凍結テスト `Task5AcceptanceTests` /
`Task6AcceptanceTests` が固定）。

### GET /sessions/{id}/settings

- 成功: 200
```json
{
  "selectedModel": "opus",
  "availableModels": [
    { "id": "opus", "displayName": "Opus 4.8" },
    { "id": "sonnet", "displayName": "Sonnet 5" }
  ]
}
```
- モデル選択非対応セッション（codex app-server・復元失敗プレースホルダ等、
  実際に設定を適用できないもの）: 200 + `"selectedModel": null` + `"availableModels": []`
  （クライアントはチップ非表示にする）。GET と POST の能力ゲートは同一
  （`canApplySpawnAgentSettings`）。
- 未知のセッション id: 404

### POST /sessions/{id}/model

- body: `{"model": "sonnet"}`
- 成功: 200（適用は macOS 側 `ChatSessionViewModel.setSpawnAgentModel` 経由＝
  model/permission/effort のフルスナップショット適用で、permission-mode を失わない）
- 未知 id・モデル選択非対応セッション: 404
- body 不正（model 欠落・空文字）: 400

## 7. wave-2 ワイヤ拡張（spawn 前モデル選択・プロジェクト情報・アカウント使用量。2026-07-15 追加・実装済み）

上記 §6（セッション内でのモデル**変更**）とは別物。本節は **spawn 前**のモデル一覧取得・セッション一覧への
project 付与・アカウント単位の CLI 使用量取得を扱う。正本は作業用 `docs/agent-output/wire-contract.md`
（task-1 macOS 産出 ↔ task-2 iOS 消費の凍結契約）。

### 7.1 POST /sessions（spawn）— model 追加

既存 body（`kind`/`backend`/`workingDirectory`/`role`）に **`model`（任意）** を追加:
```json
{ "kind": "claudeCode", "backend": "appServer", "model": "opus" }
```
- `model` 省略時は従来どおり（サーバ既定モデル）。
- サーバ挙動: spawn 成功で session id が確定した後にのみ、`model` が非nilなら既存の
  setSessionModel 経路で適用する。適用失敗は spawn 自体を失敗させずログのみ（ベストエフォート）。
  カタログに存在しない不正 model 文字列は **400 にせず黙って無視**（既定モデルのまま spawn 成功）。
- レスポンスは不変: `201 { "id": "<uuid>" }`。

### 7.2 GET /sessions（list）— project 追加

既存の `{"sessions":[...]}` 包装を維持（後方互換）。各要素の既存 id/name/kind/status/workspace に
`projectId`/`projectName`（**両方 nullable**）を追加:
```json
{ "sessions": [
  { "id": "…", "name": "…", "kind": "claudeCode", "status": "running",
    "workspace": "my-repo", "projectId": "P-123", "projectName": "My Repo" }
] }
```
- プロジェクト未所属セッションは `projectId`/`projectName` の**キー自体を省略**（null 値ではない）。
  iOS 側は欠落を nil として decode する。

### 7.3 GET /agents/{kind}/models（新設）— spawn 前のモデル一覧

`{kind}` は AgentKind rawValue。
```json
{ "models": [ { "id": "opus", "displayName": "Opus 4.8" },
              { "id": "sonnet", "displayName": "Sonnet 4.5" } ],
  "defaultModel": "sonnet" }
```
- claudeCode: 静的カタログ（4種）。cursor: 静的 fallback。
- codex: `{ "models": [], "defaultModel": null }`（モデル選択非対応、意図的空）。
- 未知 kind: `404`。

### 7.4 GET /usage（新設）— アカウント単位の CLI 使用量

```json
{ "agents": [
    { "kind": "claudeCode", "state": "ok",
      "updatedAt": "2026-07-14T09:00:00Z", "dataAsOf": "2026-07-14T08:55:00Z",
      "buckets": [ { "id": "5h", "label": "5-hour", "usedPercent": 42.0, "resetsAt": "2026-07-14T12:00:00Z" },
                   { "id": "weekly", "label": "Weekly", "usedPercent": 12.5, "resetsAt": null } ] },
    { "kind": "codex", "state": "unavailable",
      "updatedAt": null, "dataAsOf": null, "buckets": [] }
] }
```
- `state`: `"ok" | "unavailable"`。日付は ISO8601（Z）、null 可。`usedPercent` は 0.0〜100.0 の Double。
- 既存 `GET /sessions/{id}/usage`（**ターン**単位 costUSD/context、§4）とは**別物**。命名衝突を避け、
  iOS 側は `CLIUsage`/`UsageBucket`（アカウント）と `TurnUsage`（ターン）を別型で保持する。

### モバイル側の公開 API 面（追加分）

```swift
// PhloxCore（新型）
public struct SessionModelOption: Sendable, Equatable, Identifiable, Decodable { id, displayName }
public struct AgentModels: Sendable, Equatable, Decodable { models: [SessionModelOption], defaultModel: String? }
public enum CLIUsageState: String, Sendable, Equatable, Decodable { case ok, unavailable }
public struct UsageBucket: Sendable, Equatable, Identifiable, Decodable { id, label, usedPercent: Double, resetsAt: Date? }
public struct CLIUsage: Sendable, Equatable, Decodable { kind: AgentKind, state: CLIUsageState, buckets: [UsageBucket], updatedAt: Date?, dataAsOf: Date? }
// SpawnRequest.model: String? / Session.projectId・projectName: String? を追加

// PhloxAPI プロトコル（追加メソッド。実装まで既定実装が server(501) を throw）
func agentModels(kind: AgentKind) async throws -> AgentModels
func cliUsage() async throws -> [CLIUsage]
```

### 検証の分担

- **task-1（macOS ControlServer）**: 上記 7.1〜7.4 の wire 挙動を AppBootstrapTests / ControlServerTests
  の既存ハーネス流儀で受け入れテスト化し green にする（凍結: `Wave2WireContractTests`）。
- **task-2（iOS PhloxKit）**: 上記 JSON をフィクスチャに decode 契約テスト化する（凍結:
  `Wave2WireDecodeContractTests`）。
- **統合（フェーズ4）**: 両者を突き合わせ、実サーバーに対する疎通で確認する。
