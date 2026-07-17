---
status: active
last-verified: 2026-07-17
---

# モバイル連携（MobileProxy・ControlServer）

**役割（ここにしか書かない）**: iPhone（Phlox-mobile）から Mac 上の Phlox を操作するための現行構成＝**今こう動いている**（Tailscale 経由の TCP 中継・Bearer トークン・ControlServer HTTP API）。

**書かないもの**: なぜこの構成にしたか（→ [`docs/adr/0074-mobile-remote-control-design.md`](../adr/0074-mobile-remote-control-design.md)）／iOS アプリ本体の画面設計。

**Diátaxis**: Reference

## 全体像

```
iPhone (Phlox-mobile)
    │  HTTP (Authorization: Bearer <mobile-token>)
    │  Tailscale ネットワーク (100.64.0.0/10)
    ▼
MobileProxy  … Packages/MobileProxy/ … 既定 listen :8765
    │  生 TCP 双方向リレー（HTTP をパースしない）
    │  127.0.0.1:<controlPort>
    ▼
ControlServer  … Packages/ControlServer/ … loopback のみ listen
    │  Bearer → SessionTokenStore で requester SessionID に解決
    │  ControlRequest.Action にルーティング
    ▼
ControlActionHandler  … Packages/AppBootstrap/Sources/AppBootstrap/ControlActionHandler.swift
    │  DashboardViewModel へ委譲
    ▼
セッション spawn/send/remove/rename、チャット messages、wait、承認 approve 等
```

起動順と配線は `App/CompositionRoot.swift` が担う。

| フェーズ | 処理 | 参照 |
|---|---|---|
| 6 | `ControlServer` を `127.0.0.1` で起動。`savedPorts.controlPort` があれば優先、使用中なら OS 任せの空きポート | `CompositionRoot.startControlServer`（`App/CompositionRoot.swift:178-202`） |
| 7 | `MobileProxy(targetPort: controlPort)` を起動。listen 既定ポート 8765 | `CompositionRoot.startMobileProxy`（`App/CompositionRoot.swift:204-235`） |
| 8 | モバイルトークンを load/provision し `SessionTokenStore` へ register | `CompositionRoot.provisionMobileToken`（`App/CompositionRoot.swift:237-292`） |
| 9 | `dashboard.setPrivilegedRequester(mobileRequesterSessionID)` | `CompositionRoot.swift:360` |

`ControlServer` と `HookServer` は同一の `SessionTokenStore` インスタンスを共有する（`CompositionRoot.createWorkspaceAndPersistenceStores` のコメント、`App/CompositionRoot.swift:169-171`）。

## MobileProxy（`Packages/MobileProxy/`）

### 役割

`MobileProxy` actor（`MobileProxy.swift`）は、Tailscale 側で待ち受けた TCP 接続を `127.0.0.1:<targetPort>`（ControlServer）へ**生バイトのまま**双方向中継する薄いリバースプロキシ。HTTP の method / path / Authorization ヘッダ等は一切解釈せず、認証判断は転送先 ControlServer が行う（`MobileProxy.swift:62-64`）。

実装は Network.framework ではなく BSD/POSIX ソケット（`POSIXSocketListener`・`SocketRelay`）。listener は `socket` → `bind` → `listen` → `accept`、relay は `127.0.0.1` へ `connect` した上流 fd と client fd を 2 スレッドで read/write する（`POSIXSocketListener.swift:63-127`, `SocketRelay.swift:18-35`）。

### 既定パラメータ

| 項目 | 値 | 参照 |
|---|---|---|
| listen ポート | `8765`（`listenPort` 引数省略時） | `MobileProxy.swift:92` |
| 転送先 | `127.0.0.1:<targetPort>`（CompositionRoot が ControlServer の実ポートを渡す） | `MobileProxy.swift:87`, `CompositionRoot.swift:214` |
| 同時リレー上限 | `128`（超過は accept 直後に close） | `MobileProxy.swift:69`, `POSIXSocketListener.swift:183-189` |

起動失敗（ポート使用中など）は warning ログに留め、アプリ起動自体は続行する（`CompositionRoot.swift:231-233`）。

### Tailscale IP 解決

`TailscaleIPResolver`（`TailscaleIPResolver.swift`）は PATH 上の `tailscale` 実行ファイルを定番パスから探索し、`tailscale ip -4` を実行する。終了コード 0 かつ出力行が IPv4 形式ならその IP を返し、それ以外は `nil`（`TailscaleIPResolver.swift:31-51`, `68-94`）。

### バインド方針（`BindMode`）

`BindMode.resolve(listenHost:resolveTailscaleIPv4:)`（`MobileProxy.swift:43-51`）が露出範囲を決める。

| 条件 | `BindMode` | 実 bind アドレス | 許可する接続元 CIDR | モバイル到達 |
|---|---|---|---|---|
| `listenHost` 明示 | `explicitHost(host)` | loopback 系なら `127.0.0.1`、それ以外は `0.0.0.0` | loopback のみ / Tailscale CGNAT + loopback | host 依存 |
| 未指定 + Tailscale 解決成功 | `tailscale(ip)` | `0.0.0.0`（utun 配送制約） | `100.64.0.0/10`, `127.0.0.0/8` | 可 |
| 未指定 + Tailscale 未解決 | `loopbackOnly` | `127.0.0.1` | `127.0.0.0/8` のみ | **不可**（外部露出なし） |

`bindPlan(for:)`（`MobileProxy.swift:153-160`）が bind アドレスと CIDR を返す。Tailscale モードでも macOS は utun 特定 IP bind へトンネル着信を配送しないため listen は `0.0.0.0` だが、`POSIXSocketListener` の accept ループで接続元 IP を `AcceptFilter.shouldAccept`（`AcceptFilter.swift:27-37`）により CIDR 判定し、範囲外（LAN・グローバル等）は accept 直後に close する（`POSIXSocketListener.swift:172-180`）。

**暗黙の `0.0.0.0` バインドは Tailscale 未検出時には行わない**。未検出時は `loopbackOnly` に倒す（`MobileProxy.swift:18-19`, `49-50`）。

起動後の確定値は `MobileProxy.bindMode` から参照できる（`MobileProxy.swift:82`）。

### 自己回復（Tailscale 遅延起動への再解決・再バインド）

起動時に Tailscale がまだ上がっていないと `.loopbackOnly` に倒れる。プロキシは起動時ワンショットではなく、モバイル到達可能（`.tailscale`）でない間は**再解決・再バインドで自己回復**する。決定は [ADR 0092](../adr/0092-mobile-proxy-self-heal-on-tailscale-late-start.md)。

- `MobileProxy.refresh()`（`MobileProxy.swift`）: `.tailscale` / `.explicitHost` は no-op、`nil` / `.loopbackOnly` は現行 listener を停止して再解決・再バインドする（冪等・actor 直列化）。
- `MobileProxy.recoverUntilReachable(maxAttempts:delay:sleep:)`: 有限回だけ `refresh()` を試み、`.tailscale` 到達で早期打ち切り（`sleep` は DI シーム）。
- **再バインドのソケット安全性**: `POSIXSocketListener.stop()` は `shutdown(SHUT_RDWR)` + `close()` 後、accept ループの終了を `DispatchSemaphore`（`acceptLoopExited`）で確実に待ってから返す。固定ポート 8765 の貼り替え時の fd 再利用レース・二重 accept を封じる。
- 現在の束縛ポートは `MobileProxy.boundPort` から参照できる（再バインドで変わり得る値。本番は 8765 固定）。
- **トリガー**（UI 側配線は task-2）: 設定のモバイル接続セクション表示時の on-demand 再解決（`SettingsView` の `.task`）と、起動直後の短いバウンド付きリトライ（`MobileTokenViewModel.startAutoRecovery`）。NWPathMonitor による常時監視は入れていない。

## トークン管理（`Packages/AgentDomain/MobileToken*.swift`）

### トークン形式

`MobileToken`（`MobileToken.swift`）は 32 バイトの暗号乱数を 64 文字小文字 hex にした文字列。生成は `MobileToken.generate()`（既定 `SecRandomCopyBytes`、失敗時 `arc4random_buf` フォールバック、`MobileToken.swift:21-40`）。

### 永続化

| 実装 | 用途 | 保存先 |
|---|---|---|
| `KeychainMobileTokenStore` | 本番 | Keychain `kSecClassGenericPassword`。service は `AppFlavor.current.mobileTokenKeychainService`（Release: `com.phlox.Phlox.mobileToken` / Debug: `com.phlox.Phlox.debug.mobileToken`）。token と requester SessionID を別 account で upsert（`MobileTokenStore.swift:51-75`, `136-155`） |
| `InMemoryMobileTokenStore` | テスト・フォールバック | プロセス内メモリのみ（`MobileTokenStore.swift:17-48`） |

`MobileTokenProvisioner`（`MobileTokenProvisioner.swift`）のライフサイクル:

1. **初回**: `loadOrProvision()` が requester SessionID を生成・永続化し、トークンが無ければ `MobileToken.generate()` して Keychain（または store）へ保存（`MobileTokenProvisioner.swift:39-47`, `67-74`）。
2. **2 回目以降**: 永続化済み token + requester をロード。requester SessionID は一度確定したら変わらない（`MobileTokenProvisioner.swift:37-38`）。
3. **再発行**: `regenerate()` が token のみ更新。requester は維持（`MobileTokenProvisioner.swift:49-57`）。
4. **register**: `register(_:into:)` が `SessionTokenStore.register(token, for: requesterSessionID)` を呼ぶ（`MobileTokenProvisioner.swift:59-65`）。

### 検証フロー（ControlServer）

1. リクエストの `Authorization` ヘッダから `Bearer <token>` を抽出（`ControlServer.swift:151-164`）。
2. ヘッダ欠落・`Bearer` プレフィックス不一致・空 token → `401`（同箇所）。
3. `SessionTokenStore.session(forToken:)` で requester `SessionID` を解決。解決不能 → `401`（`ControlServer.swift:132-135`, `164`）。
4. 解決した requester を `ControlRequest.requester` として `ControlActionHandler` へ渡す（`ControlServer.swift:146-148`）。

`SessionTokenStore`（`SessionTokenStore.swift`）は token ↔ session の双方向マップを actor 内に保持。同一 session への再 register は旧 token エントリを削除する（`SessionTokenStore.swift:9-20`）。

### 起動時供給（`App/CompositionRoot.swift`）

| 条件 | store | 参照 |
|---|---|---|
| Release | `KeychainMobileTokenStore`（失敗時 `InMemoryMobileTokenStore` へフォールバック） | `CompositionRoot.swift:272-282` |
| Debug + `PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN=1` | `InMemoryMobileTokenStore` のみ（Keychain 非接触） | `CompositionRoot.swift:250-259` |
| Debug（上記 env なし） | Keychain 経路（失敗時インメモリ） | `CompositionRoot.swift:260-270` |

`PHLOX_TEST_EPHEMERAL_MOBILE_TOKEN` 分岐は `#if DEBUG` 内にのみ存在し、Release バイナリでは env に関わらず Keychain 経路のみ（`CompositionRoot.swift:250-254`, `272-283`）。

provision 後、`mobileRequesterSessionID` が Dashboard の特権 requester として設定される（`CompositionRoot.swift:360`）。

### 設定 UI（QR 表示・再発行）

`MobileTokenViewModel`（`App/MobileTokenViewModel.swift`）が QR ペアリング用ペイロードの生成と、トークンの再発行（`regenerate` + `SessionTokenStore` 再 register）を担う。設定 UI にトークン文字列の表示・クリップボードコピーはなく、接続情報の供給手段は QR コード表示のみ。

`SettingsView` は `MobileConnectionGuidePolicy.showsSettingsConnectionSection` が `true` のときのみ `MobileTokenSection` を表示する（`App/SettingsView.swift:124-126`, `257-315`）。

## モバイル向け ControlServer API

すべて `Authorization: Bearer <mobile-token>` 必須。ルーティングは `ControlServer.route(request:)`（`ControlServer.swift:172-213`）、処理は `ControlActionHandler.handle`（`ControlActionHandler.swift:76-119`）。

| 操作 | メソッド | パス | リクエスト | 成功時 | ハンドラ |
|---|---|---|---|---|---|
| **list** | `GET` | `/sessions` | — | `200` + `{ "sessions":[…] }`（既存包装を維持。各要素に `projectId`/`projectName` が付与。wave-2） | `handleListSessions` |
| **spawn** | `POST` | `/sessions` | JSON: `{ "kind", "backend"?, "workingDirectory"?, "model"? }`。`backend` 省略時 `.pty`。モバイルは `"appServer"` を送る例あり（`ControlServer.swift:255`）。`model`（任意・wave-2）は spawn 後に既存 setSessionModel 経路でベストエフォート適用 | `201` + `{ "id" }` | `ControlActionHandler.handleSpawn` |
| **send** | `POST` | `/send` | JSON: `{ "to", "text", "submit"?, "inReplyTo"?, "images"? }`。`to` は SessionID UUID または名前。`images` は下記参照 | `200` 他（404/409/413/425 等） | `handleSendText` |
| **approve** | `POST` | `/approvals/{id}` | JSON: `{ "decision" }`（`ApprovalDecision` rawValue） | `200` / 未知 id は `404` | `handleRespondApproval` |
| **messages** | `GET` | `/sessions/{id}/messages?since=<cursor>&wait=<秒>` | `since`/`wait` とも省略可（下記「差分取得」参照） | 構造化: `200` + `{ messages, cursor, snapshot? }`。非構造化/不在: `404` | `handleMessagesDelta` |
| **interrupt** | `POST` | `/sessions/{id}/interrupt` | — | `204`（no-op 含む）/ interrupt 非対応（PTY 等）: `409` / 不在: `404` | `handleInterrupt` |
| **subagents** | `GET` | `/sessions/{id}/subagents` | — | 構造化: `200` + `{ subAgents:[…] }`（空は `[]`）。非構造化/不在: `404` | `handleSubAgents` |
| **subagent messages** | `GET` | `/sessions/{id}/subagents/{subAgentId}/messages` | `subAgentId` は不透明文字列 | `200` + `{ subAgentId, messages }`（形状は `/messages` と同一）。不明 id/不在: `404` | `handleSubAgentMessages` |
| **usage** | `GET` | `/sessions/{id}/usage` | — | 構造化: `200` + `{ turn:{ costUSD, contextUsedTokens, contextWindowTokens } \| null }`。非構造化/不在: `404` | `handleUsage` |
| **wait** | `GET` | `/sessions/{id}/wait?timeout=<秒>&sentinel=<任意>` | `timeout` 必須（正の整数）。Handler 側で 1〜600 秒に丸め | 完了/タイムアウト等の DTO | `handleWait` |
| **rename** | `PATCH` | `/sessions/{id}` | JSON: `{ "name" }` | `200` / 認可失敗: `403` | `handleRename` |
| **remove** | `DELETE` | `/sessions/{id}` | — | `200` / 認可失敗: `403` / 不在: `404` | `handleRemove` |
| **agent models** | `GET` | `/agents/{kind}/models` | `{kind}` は AgentKind rawValue | `200` + `{ "models":[…], "defaultModel" }`（未知 kind: `404`。wave-2） | `handleAgentModels` |
| **usage (account)** | `GET` | `/usage` | — | `200` + `{ "agents":[…] }`（wave-2） | `handleCLIUsage` |

**approve の一覧取得**（操作の前提）: `GET /approvals` → `handleListApprovals`（`ControlServer.swift:180-184`, `ControlActionHandler.swift:278-281`）。

### モバイル向け拡張（2026-07-11 追加。契約正本＝[`docs/specs/mobile-api-extensions-contract.md`](../specs/mobile-api-extensions-contract.md) v1）

- **画像添付（`/send` の `images`）**: `[{ "mediaType": "image/png"|"image/jpeg", "dataBase64": … }]`。制限＝**最大 4 枚・1 枚デコード後 4 MiB・合計 8 MiB**（デスクトップ composer と同一定数）。超過は `413` + `{"error":"attachment too large"}`、base64 不正は `400`、画像非対応セッション（PTY・非 Claude）は `409` + `{"error":"images unsupported"}`。省略・空配列は従来と完全同一挙動。8 MiB 画像の base64（≒11 MB）受信のため、ControlServer だけ transport body 上限を `16 MiB`（`ControlServer.maxRequestBodyLength`）へ拡張（HookServer は既定 256 KiB のまま）。実体は `ChatInput.image` へ配線し `client.turnStart` に載る。
- **差分取得（`/messages` の `since`/`wait`）**: レスポンスに `cursor`（常時・不透明文字列）を付与。`?since=<cursor>` で以降の差分のみ返す（`?since=` 空は `400`）。`?wait=<秒>`（非整数は `400`、Handler で 1〜25 秒に clamp）で long-poll（新規が来るまで待って返す。since 省略時は wait 無視で即応答）。既存メッセージの**編集・置換・不正/期限切れ cursor** は全量スナップショットへフォールバックし `snapshot: true` を付与（差分の誤配信を避ける保守設計）。差分エンジンは `ChatSessionViewModel.transcriptDelta(since:)`（`Packages/SessionFeature/…/TranscriptDelta.swift`）＝内容ハッシュを毎回ライブ再計算して prefix 安定性を判定する純関数（transcript 変更経路には非依存）。
- **interrupt / subagents / usage**: 実体は既存の `ChatSessionViewModel`（`turnInterrupt()` / `subAgentControlSummaries()` / `subAgentTranscript(for:)` / `lastTurnUsage`）を露出。写像は `DashboardViewModel` の `control*`（`Packages/DashboardFeature/…/ControlDashboardSupport.swift`）に集約し、App 準拠（`App/ControlActionDashboard+DashboardViewModel.swift`）は1行委譲。サブエージェントの `status` wire 値は `running|completed|unknown` の3値（domain の `failed` は `unknown` へ写像）。

### モバイル向け拡張 wave-2（2026-07-15 追加。契約正本＝[`docs/specs/mobile-api-extensions-contract.md`](../specs/mobile-api-extensions-contract.md) §7）

新規タスク画面のモデル選択・セッション一覧のプロジェクト表示・アカウント単位の使用量表示（iOS Usage 画面）向け。

- **spawn の model 適用**: `ControlServer.parseSpawn` が `SpawnBody.model` を `AgentModelCatalog.models(for: kind)` に
  存在する `id` かどうかで検証し、不一致は 400 にせず黙って `nil` に丸める（`normalizedSpawnModel`）。built-in kind
  （claudeCode/codex/cursor）のみ対象、custom agent は常に `nil` 固定。`ControlActionHandler.handleSpawn` は
  spawn で生成された session id が確定した後にだけ `ControlSpawnModelApplier.apply` 経由で適用し、失敗は
  ログ警告のみ（spawn 自体は失敗させないベストエフォート）。
- **`GET /sessions` の project 付与**: `ControlSessionListItem` に `projectId`/`projectName` を追加（標準
  `Encodable` 合成のため、両方 `nil` ならキー省略。null 値では出力しない）。供給元は
  `App/ControlActionDashboard+DashboardViewModel.swift` の `controlSessionSummaries`（`node.projectID` から
  `projects.first{...}` で解決）。
- **`GET /agents/{kind}/models`**: 新規 `ControlServer/AgentModelCatalog.swift` が静的カタログを持つ
  （claudeCode 4種・cursor 静的 fallback・codex は意図的に空＝モデル選択非対応）。pre-spawn（生存 session 無し）
  のため provider 連携ではなく静的定義。
- **`GET /usage`**: `ControlActionHandler.handleCLIUsage` が `dashboard.controlCLIUsages`
  （`ControlDashboardSupport.usageMonitor?.usages ?? [:]`、`usageMonitor` は既存 `UsageMonitor` インスタンスへの
  **weak** 参照）を `AgentKind` でソートして DTO 化。`UsageMonitor` 自体は無変更（既存の `usages: [AgentKind:
  CLIUsage]` を読み取り専用で新規露出しただけ）。既存 `GET /sessions/{id}/usage`（ターン単位）とは別エンドポイント。

非自明な設計判断の詳細は [ADR 0087](../adr/0087-mobile-wave2-wire-extensions.md) を参照。

**認可の現行挙動**（`ControlActionHandler.swift`）:

- **remove / rename**: `dashboard.isAuthorizedToRemove(id, requester:)` が false なら `403`。モバイル requester は `privilegedRequester` として全 remove を許可される配線（`handleRemove` `191-201`, `handleRename` `203-218`）。
- **output / messages / wait / listSessions**: 有効 token を持つ requester からの読み取りは operator モデルで横断参照可（コメント `220-224`）。

クエリ付き POST（`/send?…` 等）は `404`（`ControlServer.swift:187-189` 等）。

## 設定画面ゲート（`MobileConnectionGuidePolicy`）

正本は `Packages/MobileProxy/Sources/MobileProxy/POSIXSocketListener.swift` の `MobileConnectionGuidePolicy` enum。

| シンボル | 現在値 | 役割 |
|---|---|---|
| `isCompanionClientBundled` | `false` | 配布物に iPhone コンパニオンアプリが同梱されているかのフラグ（`POSIXSocketListener.swift:21`） |
| `showsSettingsConnectionSection` | `isCompanionClientBundled` と同一 | `SettingsView` のモバイル接続セクション（QR 表示・再発行・接続案内）の表示可否（`POSIXSocketListener.swift:24`, `SettingsView.swift:124-126`） |

現行は `false` のため、設定画面のモバイル接続 UI（`MobileTokenSection`）は表示されない。`App/SettingsView.swift` は `import MobileProxy` して正本を直接参照する。

## APNs push 通知経路（2026-07-11 追加）

サーバー→モバイルの通知経路。方針の記録は [ADR 0075](../adr/0075-adopt-apns-for-mobile-notifications.md)、iOS 側との契約の正本は [specs/apns-companion-contract.md](../specs/apns-companion-contract.md)。通知は「取得の合図（シグナル）」であり、データ本体の同期は上記 pull API のまま。

```
SessionViewModel（完了 / 承認待ちの観測点）
  → RemoteSessionNotifier プロトコル（Packages/SessionFeature。APNs 非依存の注入面）
  → APNsNotificationBridge（Packages/AppBootstrap。契約2のペイロード組み立て・全登録トークンへ送信・410 でトークン削除）
  → APNsSender（Packages/APNsClient。ES256 JWT〔CryptoKit〕+ URLSession HTTP/2。sandbox/production 切替）
  → APNs（api.push.apple.com / api.sandbox.push.apple.com）
```

- **デバイストークン登録**: iOS 側が `POST /device-tokens`（Bearer 認証は既存機構）で登録し、`KeychainDeviceTokenStore`（`Packages/AgentDomain/DeviceTokenStore.swift`。`AppFlavor` で Release/Debug 分離）へ冪等 upsert される。
- **フック合成**: `DashboardViewModel.sessionDidSpawn` は `DashboardSessionSpawnHooks`（`Packages/AppBootstrap/APNsNotificationBridge.swift`）のキー付き多重購読で合成され、analytics フックと APNs 注入フックが共存する（単一クロージャの所有者二重化による上書き事故の再発防止）。
- **資格情報**: 環境変数 `PHLOX_APNS_KEY_ID` / `PHLOX_APNS_TEAM_ID` / `PHLOX_APNS_AUTH_KEY_PEM`（または `_PATH`）から読む暫定注入面。未設定時は送信系全体が完全 no-op（既定状態）。
- **対象**: PTY セッション（`SessionViewModel`）のみ。appServer チャットセッションは対象外（別タスク）。

## QR ペアリング（2026-07-11 追加）

ペアリング UX。契約の正本は [specs/qr-pairing-contract.md](../specs/qr-pairing-contract.md)、採用決定は [ADR 0076](../adr/0076-adopt-qr-pairing-for-mobile.md)。

- **ペイロード生成**: `PairingPayload`（`Packages/MobileProxy/Sources/MobileProxy/PairingPayload.swift`）が `phlox://pair?v=1&host=<Tailscale IPv4>&port=…&token=…&name=…` を検証付きで生成。`.loopbackOnly` / `.explicitHost` からは生成不可（失敗を型で返す）。
- **QR 表示**: `App/PairingQRView.swift`（CoreImage `CIFilter.qrCodeGenerator`）。設定画面の `MobileTokenSection` 内で明示操作により表示し **60秒で自動非表示**（トークン=Mac 全権のため）。ペイロードは表示のたび都度生成（キャッシュなし）。Tailscale 未検出時はボタン無効化＋理由表示。
- **配線**: `CompositionRoot` が起動時の bind mode / listen port に加え `MobileProxy` 参照を `MobileTokenViewModel` へ注入し、構築直後に `startAutoRecovery()` を一度キックする。`MobileTokenViewModel` の `bindMode` / `mobileProxyPort` は `@Published`（不変スナップショットではない）で、自己回復（設定表示時の `refreshReachability()` ／起動後リトライ）の結果をアプリ再起動なしで反映する。Tailscale 未検出時はボタン無効化＋理由表示だが、設定を開き直す／Tailscale が上がると回復して有効化される（[ADR 0092](../adr/0092-mobile-proxy-self-heal-on-tailscale-late-start.md)）。
- **ゲート**: 既存の `showsSettingsConnectionSection`（`isCompanionClientBundled`）配下＝iOS アプリ同梱（D-1）まで非表示。
