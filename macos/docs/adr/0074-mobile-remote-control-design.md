---
status: active
last-verified: 2026-07-11
---

# ADR 0074: モバイル遠隔操作は Tailscale 前提の pull 型 ControlServer API として扱う

> **このファイルの役割**: iPhone から Mac 上の Phlox を操作するために実装済みの MobileProxy・モバイルトークン・ControlServer API について、後追いで設計決定を記録する。
> **書かないもの**: iOS アプリ本体の画面設計（→ `docs/specs/design-system-ios.md`）や、今後の WebSocket / APNs / push 化の新判断。

## 文脈

モバイル連携の土台は `feat(mobile): iPhone↔Mac 接続基盤とモバイル向けチャット API を追加`（commit `4b62974`）で追加され、その後 `fix(audit): 基盤層(PM-1)の監査所見を再現テスト付きで修正`（commit `bb51bb9`）で MobileProxy / ControlServer 周辺の監査修正が入った。

delivery 0018 は、Tailscale 経由 MobileProxy、モバイル専用トークン、ControlServer の spawn/send/approve/messages/wait/rename/remove、特権 requester が実装済みである一方、APNs push 基盤は未実装と記録している（`docs/delivery/0018-mobile-integration-remaining-tasks.md:14`, `docs/delivery/0018-mobile-integration-remaining-tasks.md:18`, `docs/delivery/0018-mobile-integration-remaining-tasks.md:21`, `docs/delivery/0018-mobile-integration-remaining-tasks.md:28`）。同文書は C-1 として本 ADR 起票を残タスク化していた（`docs/delivery/0018-mobile-integration-remaining-tasks.md:39-41`）。

## 決定

### 1. 脅威モデル: モバイルトークン漏洩は Mac 遠隔操作権限の漏洩として扱う

**決定**: モバイル専用 Bearer トークンは、漏洩時に Mac 上の Phlox 操作権限を広く奪われる機密として扱う。特に、モバイルトークンに紐づく安定 requester は `remove` の特権 requester であり、cascade delete を含む全 remove を許可する。

**文脈**: `MobileToken` は 32 バイト乱数由来の 64 hex で、Keychain 永続化を前提にし、平文 UserDefaults / ログへ残さない不変条件を持つ（`Packages/AgentDomain/Sources/AgentDomain/MobileToken.swift:4-9`, `Packages/AgentDomain/Sources/AgentDomain/MobileTokenStore.swift:4-8`）。`MobileTokenProvisioner` は token と安定 requester SessionID を生成・永続化し、`SessionTokenStore` へ token -> requester を登録する（`Packages/AgentDomain/Sources/AgentDomain/MobileTokenProvisioner.swift:16-22`, `Packages/AgentDomain/Sources/AgentDomain/MobileTokenProvisioner.swift:59-65`）。ControlServer は Bearer token を `SessionTokenStore` で requester に解決できない場合 401 にする（`Packages/ControlServer/Sources/ControlServer/ControlServer.swift:132-165`）。

**結果**: App 起動時にモバイル requester は Dashboard の特権 requester として配線される（`App/CompositionRoot.swift:237-290`, `App/CompositionRoot.swift:357-360`）。`SpawnPolicy.isAuthorizedToRemove` は `privilegedRequester` と一致する requester を無条件許可し、そのコメントは「モバイルトークン漏洩 = Mac の全権奪取」と明記する（`Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/SpawnPolicy.swift:57-72`）。なお実装上、特権化が明示されているのは remove だが、同じ Bearer token で ControlServer の spawn/send/read/approve/rename/remove に到達するため、漏洩時の影響は remove だけに限定しない（`Packages/AppBootstrap/Sources/AppBootstrap/ControlActionHandler.swift:76-119`, `Packages/AppBootstrap/Sources/AppBootstrap/ControlActionHandler.swift:191-224`, `Packages/AppBootstrap/Sources/AppBootstrap/ControlActionHandler.swift:262-289`）。

### 2. Mac 側は Tailscale 前提の薄いリバースプロキシを置く

**決定**: iPhone は直接 ControlServer に入らず、Mac 側の `MobileProxy` が Tailscale 側の待ち受けから `127.0.0.1:<ControlServer port>` へ HTTP を生 TCP で中継する。

**文脈**: `MobileProxy` は既定で Tailscale インターフェースの固定ポートを待ち受け、受けた TCP 接続を `127.0.0.1:<targetPort>` の ControlServer へ双方向中継する、と実装コメントで定義している（`Packages/MobileProxy/Sources/MobileProxy/MobileProxy.swift:54-65`, `Packages/MobileProxy/Sources/MobileProxy/MobileProxy.swift:84-95`）。CompositionRoot も ControlServer のポートをメモリから直接 MobileProxy へ渡し、HTTP を無改変に中継するフェーズとして起動している（`App/CompositionRoot.swift:204-214`）。

**結果**: 認証・認可判断は MobileProxy ではなく転送先 ControlServer に集約される。MobileProxy は Authorization ヘッダを含む HTTP バイト列を解釈せず透過する（`Packages/MobileProxy/Sources/MobileProxy/MobileProxy.swift:62-65`, `Packages/MobileProxy/Sources/MobileProxy/SocketRelay.swift:34-35`）。これによりモバイル用の公開面は、既存 ControlServer API の Bearer 認証と Dashboard 操作ハンドラに寄せられる。

### 3. Tailscale 未検出時は fail-closed にし、暗黙に全インターフェースへ開かない

**決定**: `listenHost` 未指定で Tailscale IPv4 を解決できない場合、MobileProxy は `127.0.0.1` 限定に倒す。暗黙の `0.0.0.0` バインドはしない。

**文脈**: `BindMode.resolve` は、明示 host、Tailscale 解決成功、loopbackOnly の順で露出範囲を決める（`Packages/MobileProxy/Sources/MobileProxy/MobileProxy.swift:39-51`）。`TailscaleIPResolver` は `tailscale ip -4` を実行し、失敗・非 0・不正出力では nil を返す（`Packages/MobileProxy/Sources/MobileProxy/TailscaleIPResolver.swift:14-17`, `Packages/MobileProxy/Sources/MobileProxy/TailscaleIPResolver.swift:31-51`）。

**結果**: loopbackOnly は `127.0.0.1` に束縛され、外部露出なし・モバイル到達不可としてログされる（`Packages/MobileProxy/Sources/MobileProxy/MobileProxy.swift:15-21`, `Packages/MobileProxy/Sources/MobileProxy/MobileProxy.swift:112-118`, `Packages/MobileProxy/Sources/MobileProxy/MobileProxy.swift:174-184`）。Tailscale / 非 loopback host の実 bind は macOS の utun 配送制約により `0.0.0.0` を使うが、接続元 CIDR を Tailscale CGNAT + loopback に制限し、LAN / global 由来は accept 後に閉じる（`Packages/MobileProxy/Sources/MobileProxy/MobileProxy.swift:147-160`, `Packages/MobileProxy/Sources/MobileProxy/POSIXSocketListener.swift:30-36`, `Packages/MobileProxy/Sources/MobileProxy/POSIXSocketListener.swift:172-180`）。したがって `0.0.0.0` は「Tailscale 未検出時のフォールバック」ではなく、非 loopback 動作時の配送制約回避と CIDR フィルタの組で扱う。

### 4. NWListener ではなく生 BSD / POSIX ソケットを採用する

**決定**: MobileProxy の listener / relay は Network.framework の `NWListener` / `NWConnection` ではなく、BSD / POSIX ソケットで実装する。

**文脈**: 実装コメントは、`NWListener` が `requiredLocalEndpoint` / `requiredInterface` のどちらでも Tailscale の utun アドレスで accept できず、LISTEN 表示のみになる実機バグがあるため、と理由を明記している（`Packages/MobileProxy/Sources/MobileProxy/MobileProxy.swift:57-60`, `Packages/MobileProxy/Sources/MobileProxy/POSIXSocketListener.swift:27-36`）。commit `4b62974` は MobileProxy パッケージと `POSIXSocketListener.swift` / `SocketRelay.swift` を同時に追加している。

**結果**: `POSIXSocketListener` は `socket`、`setsockopt`、`bind`、`listen`、`accept` を直接呼ぶ（`Packages/MobileProxy/Sources/MobileProxy/POSIXSocketListener.swift:63-127`, `Packages/MobileProxy/Sources/MobileProxy/POSIXSocketListener.swift:141-191`）。`SocketRelay` も loopback 上流へ `socket` / `connect` し、2 本のスレッドで read/write を行う（`Packages/MobileProxy/Sources/MobileProxy/SocketRelay.swift:18-35`, `Packages/MobileProxy/Sources/MobileProxy/SocketRelay.swift:66-91`, `Packages/MobileProxy/Sources/MobileProxy/SocketRelay.swift:93-164`）。監査後は SIGPIPE 抑止、同時リレー上限、remote CIDR フィルタも追加・維持されている（commit `bb51bb9`; `Packages/MobileProxy/Sources/MobileProxy/SocketRelay.swift:6-16`, `Packages/MobileProxy/Sources/MobileProxy/POSIXSocketListener.swift:53-57`, `Packages/MobileProxy/Sources/MobileProxy/POSIXSocketListener.swift:168-191`）。

### 5. push ではなく `GET /sessions/{id}/wait` とポーリングで更新を取得する

**決定**: 現行のモバイル連携は APNs / WebSocket / サーバー push を持たず、ControlServer の pull API で状態を取得する。完了待ちは `GET /sessions/{id}/wait`、チャット履歴は `GET /sessions/{id}/messages`、承認待ちは `GET /approvals` を使う。

**文脈**: ControlServer は `/sessions/{id}/wait` を `ControlRequest.Action.wait` にルーティングし、timeout と任意 sentinel を受け取る（`Packages/ControlServer/Sources/ControlServer/ControlServer.swift:288-310`, `Packages/ControlServer/Sources/ControlServer/ControlServer.swift:352-374`, `Packages/ControlServer/Sources/ControlServer/ControlTypes.swift:21-24`）。AppBootstrap は `wait` を 1〜600 秒に丸めて Dashboard の `waitUntilDone` へ委譲し、Dashboard は内部で完了状態をポーリングする（`Packages/AppBootstrap/Sources/AppBootstrap/ControlActionHandler.swift:262-275`, `Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardViewModel.swift:1071-1132`）。`/messages` と `/approvals` も ControlServer / AppBootstrap で pull API として実装されている（`Packages/ControlServer/Sources/ControlServer/ControlServer.swift:180-184`, `Packages/ControlServer/Sources/ControlServer/ControlServer.swift:301-309`, `Packages/ControlServer/Sources/ControlServer/ControlServer.swift:397-426`, `Packages/AppBootstrap/Sources/AppBootstrap/ControlActionHandler.swift:239-249`, `Packages/AppBootstrap/Sources/AppBootstrap/ControlActionHandler.swift:278-289`）。

**結果**: delivery 0018 は「APNs 基盤は現状コード皆無」「モバイル側の更新取得はロングポーリング + ポーリングに依存」と記録する（`docs/delivery/0018-mobile-integration-remaining-tasks.md:28-32`）。push を採らなかった積極的理由を記した一次 ADR / 仕様は見つからないため、理由は推定に留める。推定: Mac ローカル ControlServer を Tailscale 越しに HTTP pull で公開する構成なら、APNs 証明書管理・デバイストークン登録・通知トリガーを追加せず、既存の Bearer 認証付き ControlServer API だけで MVP の遠隔操作を成立させられるため、push は未実装の残タスクとして残された。

## 棄却案

- **Tailscale 未検出時に全インターフェースへ開く**: 露出範囲が大きすぎる。現行コードは loopbackOnly に倒し、モバイル到達不可を明示する。
- **MobileProxy で HTTP / 認証を解釈する**: 認証判断が二重化する。現行コードは生 TCP リレーに留め、Bearer 検証を ControlServer に集約する。
- **APNs / WebSocket を今の実装済み決定として記録する**: コードも恒久 ADR も無い。delivery 0018 上も未実装・設計判断候補であり、本 ADR では現行の pull 型 API だけを記録する。

## 結果

- モバイル連携の公開面は、Tailscale 到達性、Bearer token、ControlServer API、Dashboard の操作認可に分解して監査できる。
- モバイルトークンは利便性のため安定 requester として永続化されるが、漏洩時の影響は大きい。表示 UI は iPhone コンパニオン同梱まで非表示にされている（`Packages/MobileProxy/Sources/MobileProxy/POSIXSocketListener.swift:17-25`, `App/SettingsView.swift:124-126`, `App/SettingsView.swift:257-315`）。
- リアルタイム化や push 通知は本 ADR の決定ではない。delivery 0018 の A-1 / B-2 として、APNs / WebSocket / サーバー push の要否を別途決める必要がある（`docs/delivery/0018-mobile-integration-remaining-tasks.md:28-37`）。
