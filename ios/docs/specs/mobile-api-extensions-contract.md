---
status: active
last-verified: 2026-10-17
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
- 受信の制限: 最大 **4 枚**・1 枚あたりbase64復号後 **4MiB**・合計 **15MB**（MBは10進）。旧iOSとの互換性のため各4MiBを受け付けるが、新クライアントの送信は各3.75MB以下。元画像はクライアントで各20MB・合計80MBまで受け付け、共有ImageAttachmentKitで送信前に調整する。HTTP bodyはControlServerのみ24MiBまで。超過は **413** + `{"error":"attachment too large"}`
- `mediaType` は `image/png` / `image/jpeg` を必須サポート
- 画像添付非対応のセッション（PTY 等）: **409** + `{"error":"images unsupported"}`
- 同じセッションで画像送信を準備中: **409** + `{"error":"image send in progress"}`。準備後に再送できる。本文のみ・画像付きともに拒否し、元の送信と添付を保持する。
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
`PhloxNetworking`）で、両者は一字一句一致（凍結テスト `ControlModelRoutingTests` /
`SessionModelAPITests` が固定）。

### GET /sessions/{id}/settings

- 成功: 200
```json
{
  "selectedModel": "opus",
  "availableModels": [
    { "id": "opus", "displayName": "Opus 5" },
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
- 2026-10-17 改版（§8.8）: Mac が変更を受け付けない状態（権限の切り替え中）は **409** `{"error":"settings update in progress"}`（以前は 500）。Codex の thread 開始前は 425（従来どおり）。本当の適用失敗は 500 のまま。

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

#### 7.1.1 POST /sessions（spawn）— projectId 追加（所属指定・上り方向。2026-07-30）

§7.2 が下り方向で返す `projectId` に対応する**上り方向**。省略可の **`projectId`**（ProjectID の
UUID 文字列）を追加する:
```json
{ "kind": "codex", "backend": "appServer", "model": "gpt-5.6",
  "projectId": "6C2F0E2A-1111-4222-8333-444455556666" }
```

| 条件 | 応答 |
|---|---|
| `projectId` 省略 | `201`。従来どおり未所属（macOS サイドバーの「その他」）で作成＝完全な後方互換 |
| UUID かつ該当プロジェクトあり | `201`。そのプロジェクト配下に作成し、CWD をプロジェクトの `directoryPath` にする |
| UUID として parse 不能（空文字含む） | `400 {"error":"invalid projectId"}`。spawn しない |
| UUID だが該当プロジェクトなし | `422 {"error":"unknown projectId"}`。spawn しない |

- **形式の誤り＝400（パース層）／存在しない＝422（ハンドラ層）** で切り分ける。422 を選ぶのは、
  iOS が 422 のときだけ `PhloxError.spawnRejected(reason:)` としてサーバの `error` 文字列を画面に
  出せるため（400 は汎用エラーに丸められて理由が埋もれる）。
- `projectId` と `workingDirectory` を同時指定した場合は **`workingDirectory` が CWD を決める**。
  `projectId` は所属の決定にのみ効く。
- **iOS の送信条件**: セッション一覧のグループは `session.projectId ?? projectName` を id にする
  フォールバックを持つため、id をそのまま送ってはならない。`ProjectGroup.projectID`（本物の
  `session.projectId` のときだけ非 nil）を送る。「その他」グループとグループ皆無時は送らない。
- **旧 macOS との組み合わせ**: 未知フィールドは無視されるため、`201` が返りつつセッションは
  「その他」に作られる（サイレント劣化）。能力ネゴシエーションは行わない。
- 決定理由: [macos/docs/adr/0141](../../../macos/docs/adr/0141-spawn-project-id-wire.md)。

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
{ "models": [ { "id": "opus", "displayName": "Opus 5" },
              { "id": "sonnet", "displayName": "Sonnet 5" } ],
  "defaultModel": "sonnet" }
```
- claudeCode / cursor / codex: 起動時に live provider が取得したスナップショットを返す。取得に失敗した kind は内蔵 fallback を返す。
- `displayName` は**サーバ（macOS）が決める表示用の文字列**で、クライアントはそのまま表示する。Claude は CLI から取得した製品名（例 `Opus 5`）、fallback 時と Cursor / Codex は ID と同値になる。値の内容は契約ではないので、iOS 側でパースしたり対応表を持ったりしない。
- codex も app-server の `model/list` 結果を返し、非空になりうる（CLI 不在などで空になることもある）。
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
  の既存ハーネス流儀で受け入れテスト化し green にする（凍結: `ModelCatalogTests`）。
- **task-2（iOS PhloxKit）**: 上記 JSON をフィクスチャに decode 契約テスト化する（凍結:
  `DomainModelTests` / `ProjectCatalogUsageClientTests`）。
- **統合（フェーズ4）**: 両者を突き合わせ、実サーバーに対する疎通で確認する。

## 8. 入力欄の設定（推論の深さ・権限・Plan）とプロジェクト一覧（2026-10-17 追加）

iPhone の入力欄を Mac の新規チャットと揃えるための拡張。決定理由は
[macos/docs/adr/0216](../../../macos/docs/adr/0216-mobile-composer-settings-and-projects-wire.md)。
すべて**追加のみ**で、既存の項目・応答の意味は変えない（古い iOS は今までどおり動く）。

共通:
- 選択肢は `{"value": String|null, "displayName": String}` の配列で返す。`value` を送り、`displayName` をそのまま表示する。
- `displayName` は **Mac の表示言語**（アプリの言語設定）で返す。iOS 側で訳さない。
- **Plan は権限の選択肢に含めない**。`planMode`（Bool）で別に扱う。`"plan"` を権限の値として送ると 400。
- `value: null` は「既定」（Cursor の「既定」）。送らないのと同じ意味。

### 8.1 POST /sessions（spawn）— effort / permission / planMode 追加

既存 body に、**どれも省略可**の 3 項目を追加する:
```json
{ "kind": "claudeCode", "backend": "appServer", "model": "opus",
  "projectId": "6C2F0E2A-1111-4222-8333-444455556666",
  "effort": "high", "permission": "acceptEdits", "planMode": false }
```

| 条件 | 応答 |
|---|---|
| 3 項目とも省略 | 従来と完全に同じ（`model` は spawn 後のベストエフォート適用。不正な `model` は黙って無視） |
| いずれかを指定し、すべて選択肢の中 | `201`。Mac の新規チャットと同じ「初期設定」として起動時に適用する。`model` もこのとき初期設定に入れ、spawn 後の別適用はしない |
| 型が違う（例 `"planMode": "yes"`） | `400`（body 不正） |
| `effort` / `permission` が空文字・制御文字入り・長すぎ | `400 {"error":"invalid effort"}` / `400 {"error":"invalid permission"}` |
| 実際の起動方式が `appServer` でないのに、いずれかを指定 | `400 {"error":"settings require appServer backend"}` |
| `effort` が §8.2 の `availableEfforts[<model>]` に無い | `400 {"error":"unknown effort: <値>"}`。`<model>` は指定の `model`（省略・不正ならその kind の既定モデル） |
| `permission` が §8.2 の `availablePermissions` の非 null の値に無い（`"plan"` を含む） | `400 {"error":"unknown permission: <値>"}` |
| `planMode: true` だが §8.2 の `planModeAvailable` が false | `400 {"error":"plan mode unavailable"}` |
| Mac が初期設定を適用できず起動に失敗 | `422 {"error":"settings not applied"}` |

- 検証はすべて spawn の前に行う。400 のときセッションは作らない。
- 既存の `projectId`（§7.1.1）・`workingDirectory`・`role` の扱いは不変。

### 8.2 GET /agents/{kind}/settings（新設）— 新規チャットで選べる設定

`{kind}` は AgentKind rawValue。モデルの一覧は従来どおり §7.3 `GET /agents/{kind}/models` から取る。
```json
{
  "availableEfforts": {
    "opus":  [ { "value": "low", "displayName": "低" }, { "value": "medium", "displayName": "中" },
               { "value": "high", "displayName": "高" }, { "value": "xhigh", "displayName": "非常に高" },
               { "value": "max", "displayName": "最大" } ],
    "haiku": []
  },
  "availablePermissions": [
    { "value": "acceptEdits", "displayName": "…" }, { "value": "auto", "displayName": "…" },
    { "value": "bypassPermissions", "displayName": "…" }, { "value": "manual", "displayName": "…" },
    { "value": "dontAsk", "displayName": "…" }
  ],
  "planModeAvailable": true
}
```
- `availableEfforts` のキーは、同じ kind の `GET /agents/{kind}/models` の `models[].id` と同じ集合。値が `[]` のモデルは推論の深さを選べない（チップを出さない）。
- 選択肢は Mac の新規チャット画面と同じ: Claude の推論の深さは low/medium/high/xhigh/max（`haiku` は無し）、Codex・Cursor はモデルの `reasoningEfforts`。権限は Claude が acceptEdits/auto/bypassPermissions/manual/dontAsk、Codex が `:danger-full-access`/`:workspace`/`:read-only`、Cursor が 既定（`value: null`）/`ask`。Plan は 3 つとも `planModeAvailable: true`。
- 未知 kind・クエリ付き: `404`。

### 8.3 GET /sessions/{id}/settings — 項目の追加

§6 の応答に次のキーを**追加**する（既存の `selectedModel` / `availableModels` の意味と能力ゲートは不変）:
```json
{
  "selectedModel": "opus", "availableModels": [ … ],
  "selectedEffort": "high",
  "availableEfforts": [ { "value": "low", "displayName": "低" }, … ],
  "selectedPermission": "bypassPermissions",
  "availablePermissions": [ { "value": "acceptEdits", "displayName": "…" }, … ],
  "planMode": false,
  "planModeAvailable": true
}
```
- 選択肢は Mac の実行中セッションの入力欄と同じ出所（推論の深さはそのセッションで回せる段、Codex の権限は app-server が返すプロファイル）。推論の深さの `displayName` は §8.2 と同じ訳語（「高」など）にする（Mac の実行中の入力欄は値をそのまま表示している）。
- 変えられないセッション（PTY・復元失敗など）: `selectedEffort: null`・`availableEfforts: []`・`selectedPermission: null`・`availablePermissions: []`・`planMode: false`・`planModeAvailable: false`。
- `selectedPermission` が選択肢に無い値（Codex の独自設定など）のときは `null`。
- 未知のセッション id: `404`（従来どおり）。

### 8.4 PATCH /sessions/{id}/settings（新設）— 実行中のセッションの設定変更

body は次のうち**1 つ以上**（モデルの変更は従来どおり §6 `POST /sessions/{id}/model`）:
```json
{ "effort": "medium" }
{ "permission": ":workspace" }
{ "permission": null }
{ "planMode": true }
```
- 適用順は `permission` → `planMode` → `effort`。
- 権限を変えると Plan は解除される（Mac の入力欄と同じ）。同じ body に `"planMode": true` があれば、その後で Plan に入る。
- `"permission": null` は「既定」に戻す。§8.3 の `availablePermissions` に `value: null` があるセッション（Cursor）だけで有効。
- 成功: `200`（body なし）。反映後の値は `GET /sessions/{id}/settings` で取り直す。

| 条件 | 応答 |
|---|---|
| 未知のセッション id | `404` |
| Codex の thread 開始前 | `425 {"error":"session not ready"}`（§6 の model と同じ。wait-ready 後に再送） |
| body 不正・3 項目どれも無い・型違い | `400` |
| 値が空文字・制御文字入り・長すぎ | `400 {"error":"invalid effort"}` / `400 {"error":"invalid permission"}` |
| 値が §8.3 の選択肢に無い（`"plan"` を含む） | `400 {"error":"unknown effort: <値>"}` / `400 {"error":"unknown permission: <値>"}` |
| その設定を変えられないセッション（選択肢が空・PTY など） | `409 {"error":"effort unsupported"}` / `409 {"error":"permission unsupported"}` / `409 {"error":"plan mode unavailable"}` |
| Mac が変更を受け付けない状態（権限の切り替え中・送信中・画像送信の準備中など。どの状態で拒むかは Mac の入力欄と同じ） | `409 {"error":"settings update in progress"}`。少し待って再送できる |
| 適用に失敗 | `500` |

- `404`・`425`・`400`・`409 unsupported` は、何も適用する前に判定する。
- 適用の途中（2 項目目以降）で `409 in progress`・`500` になったときは、先に適用した項目は戻さない。

### 8.5 GET /projects（新設）— プロジェクト一覧

```json
{ "projects": [ { "id": "6C2F0E2A-1111-4222-8333-444455556666", "name": "My Repo" } ] }
```
- Mac のプロジェクト（サイドバー）と同じ順。セッションが 0 件のプロジェクトも含む。プロジェクトが無ければ `[]`。
- `id` は §7.1.1 の `projectId`（送る値）・§7.2 の `projectId`（返る値）と同じ文字列。
- クエリ付き: `404`。

### 8.6 新しい iOS と古い Mac の組み合わせ

- `POST /sessions` の新項目は古い Mac では黙って無視され、既定の設定で `201` になる（§7.1.1 と同じサイレント劣化）。
- `GET /agents/{kind}/settings`・`GET /projects` は `404`、`PATCH /sessions/{id}/settings` は `400` になる。iOS はこれらを「非対応」として扱い、チップを出さない（プロジェクトは §7.2 から組み立てる従来の方法に戻す）。

### 8.7 質問カード — `allowsSessionScope` 追加（Claude の「このセッション中は許可」）

`GET /sessions/{id}/messages` の `type == "userQuestion"` の `questions[]` の各要素に、**省略可**の `allowsSessionScope`（Bool）を追加する:
```json
{ "question": "Bash を実行しますか？", "header": "…", "multiSelect": false,
  "options": [ { "label": "Allow" }, { "label": "Deny" } ],
  "allowsSessionScope": true }
```
- Claude Code のツール使用許可の質問（Mac で承認カードとして出るもの）にだけ付く。`true` なら「このセッション中は許可」を返せる（CLI が同じ種類を通すルールを提案してきたとき）。`false` なら返せない。
- 通常の質問（AskUserQuestion など）・古い保存データでは**キー自体を省略**する。iOS は欠落を false として扱う。
- 返し方: 既存の `POST /sessions/{id}/question` に、その質問の回答として `"AllowForSession"` を送る（Mac の承認カードと同じ値・同じ経路）:
  `{"requestId": "<requestId>", "answers": {"<question文>": ["AllowForSession"]}}`
- `allowsSessionScope` が false・欠落の質問に `"AllowForSession"` を送ると、Mac と同じく通常の「許可」（1 回だけ）になる。
- `options` には `AllowForSession` を足さない（古い iOS が 3 つ目の選択肢として表示しないように）。
- Codex の承認は従来どおり `POST /approvals/{id}` の `acceptForSession`。Cursor には対話的な承認が無い。
- 定数: `ControlQuestionWireContract.allowsSessionScopeKey` / `allowForSessionAnswer`（iOS `PhloxQuestionWireContract` と一字一句一致）。

### 8.8 POST /sessions/{id}/model — 変更中を 409 に（§6 の改版）

- Mac が変更を受け付けない状態（権限の切り替え中）は、以前は 500 だったのを **409 `{"error":"settings update in progress"}`** に変える。§8.4 の PATCH と同じ。
- 本当の適用失敗は 500 のまま。ほかのステータス（200/400/404/425）は不変。
- iOS（`PhloxAPIClient.setModel`）は再試行せず、失敗を黙って現状維持にしているだけで 500 を特別扱いしていない（2026-10-17 確認）。このため iOS の挙動は変わらない。

### 8.9 GET /approvals — `actionKind` 追加（承認の操作の種類。2026-10-17 追加）

承認の見出し「承認待ち · {操作の種類}」を iPhone で出すため、`GET /approvals` の各要素に**省略可**の `actionKind`（String）を追加する:
```json
{ "approvals": [
  { "id": "…", "sessionID": "…", "kind": "codex", "prompt": "…", "actionKind": "command" }
] }
```
- 値は Codex の承認の種類（Mac の `ChatApprovalKind`）: `"command"`（コマンドの実行）・`"fileChange"`（ファイルの変更）・`"permissions"`（権限の変更）。Mac の承認カードの見出し（`ApprovalCard.kindLabel`）と同じ出所。
- 既存の `kind` は今までどおり**エージェントの種類**（`"codex"`）。意味は変えない。
- 種類が分からない承認では**キー自体を省略**する。iOS は欠落・未知の値を「種類なし」として扱い、見出しを「承認待ち」だけにする。
- 古い iOS は知らないキーを無視するので影響しない。古い Mac は `actionKind` を返さない（上と同じく「種類なし」）。
- 表示の文言は iOS 側で持つ（値は 3 つの固定の語で、Mac の表示言語に依存しない）。
- Claude Code の許可は `/approvals` に載らない（§8.7 の質問カード）。質問の `header` にツール名（`Bash` など）が入っている。
