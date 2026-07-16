---
status: active
last-verified: 2026-07-11
---

# APNs 連携契約 v1 — Phlox（Mac）↔ Phlox-mobile（iOS）

> **このファイルの役割**: APNs push 通知（ADR 0075）の Mac↔iOS 間シーム契約の凍結、および **Phlox-mobile リポジトリへの iOS 側実装依頼ドキュメント**。両リポジトリはこの契約に対して並行実装する。
> **書かないもの**: Mac 側の内部設計（パッケージ構成・トリガー実装）。契約の変更は両リポジトリ承認なしに行わない（追記は v2 として節を分ける）。

## 背景（iOS 実装者向け・3行）

Phlox は Mac 上の AI エージェントセッションを管理する macOS アプリで、iPhone からは Tailscale 経由のリバースプロキシ（MobileProxy）越しに Bearer トークン認証付き HTTP API（ControlServer）で遠隔操作できる（現行構成: `docs/architecture/mobile-proxy.md`）。更新取得は pull 型 API のみだったが、ロック中・離席時にも「セッション完了」「承認待ち発生」を通知するため APNs を採用した（`docs/adr/0075-adopt-apns-for-mobile-notifications.md`）。通知は「取得の合図」であり、正確な状態は受信後に既存 pull API で確定する。

## 契約1: デバイストークン登録 API（Mac 側が提供・iOS 側が呼ぶ）

既存のモバイル向け API と同一オリジン（Tailscale 経由 MobileProxy の待ち受け、既存の接続先・ポート）・同一認証。

```
POST /device-tokens
Authorization: Bearer <モバイルトークン>   ← 既存 API と同じトークン
Content-Type: application/json

{
  "deviceToken": "<APNs デバイストークンの hex 文字列（小文字）>",
  "bundleId": "<iOS アプリの bundle identifier>",
  "environment": "sandbox" | "production",
  "tokenType": "device" | "liveactivity-push-to-start" | "liveactivity-update",
  "activityId": "<update token の Activity ID。update のとき必須>",
  "sessionId": "<update token が属するセッション ID。update のとき必須>"
}
```

- `tokenType`・`activityId`・`sessionId` はライブアクティビティ拡張フィールド。既存クライアントが省略した場合、`tokenType` は `device` として扱う。
- `liveactivity-push-to-start` はアプリ全体の push-to-start token、`liveactivity-update` は Activity ごとの update token。後者は `activityId` と `sessionId` を必須とする。

- **応答**: 成功 = HTTP **200**（body は最小 JSON。iOS はステータスコードだけを成否判定に使うこと）。**401** = Bearer 不正/欠落。**400** = body 不正（JSON でない・必須キー欠落・deviceToken が hex でない）。
- **冪等 upsert**: 同じ deviceToken の再登録は上書きで常に 200。iOS は「アプリ起動のたび」「APNs からトークン変更を受けたとき」に再登録してよい（すべきである）。
- **environment**: その deviceToken が APNs の sandbox / production どちらで発行されたか（Debug ビルド = sandbox、TestFlight/App Store = production）。Mac 側はこれで送信先 APNs ホストを切り替える。
- 登録解除 API は v1 には無い。Mac 側は APNs の `410 Unregistered` 応答で失効トークンを自動削除する。

## 契約2: push ペイロード（Mac 側が送る・iOS 側が受ける）

APNs ヘッダ: `apns-push-type: alert`・`apns-topic: <登録された bundleId>`・`apns-priority: 10`。同一セッション×同一種別は `apns-collapse-id: <sessionId>:<type>` で collapse する。

```json
{
  "aps": {
    "alert": { "title": "<セッション名>", "body": "<種別に応じた短文>" },
    "sound": "default",
    "thread-id": "<sessionId>"
  },
  "phlox": {
    "v": 1,
    "type": "session_completed" | "approval_pending",
    "sessionId": "<セッション ID>",
    "sessionName": "<セッション表示名>"
  }
}
```

- **機密を載せない**（凍結・セキュリティ制約）: メッセージ本文・トークン・コマンド内容はペイロードに含めない。iOS は受信後に既存 pull API（`GET /sessions/{id}/messages`・`GET /approvals`・`GET /sessions/{id}/wait`）で実データを取得する。
- **配信保証なし前提**: APNs push は落ちうる。iOS はフォアグラウンド復帰時の pull 再同期を必ず持ち、push を唯一の更新経路にしない。
- 未知のキー・未知の `type` 値は無視する（前方互換）。

### 契約2-LA: ライブアクティビティ push

APNs ヘッダは `apns-push-type: liveactivity`、`apns-topic: <bundleId>.push-type.liveactivity`、`apns-priority: 10`。collapse ID は `<sessionId>:liveactivity` とする。既存 update token があるセッションには `update` / `end` を送り、ない場合は push-to-start token に `start` を送る。

```json
{
  "aps": {
    "timestamp": 1700000000,
    "event": "start" | "update" | "end",
    "content-state": {
      "sessionId": "<セッション ID>",
      "sessionName": "<セッション表示名>",
      "status": "approval_pending" | "session_completed",
      "summary": "Approval pending" | "Session completed"
    },
    "stale-date": 1700000900,
    "attributes-type": "SessionActivityAttributes",
    "attributes": {
      "sessionId": "<セッション ID>",
      "sessionName": "<セッション表示名>"
    }
  }
}
```

- `attributes-type` と `attributes` は `start` のときだけ含める。
- iOS の `SessionActivityAttributes.ContentState` の Codable キーは `sessionId`・`sessionName`・`status`・`summary` と一字一致させる。
- `approval_pending` の `stale-date` は `timestamp + 900`、`session_completed` は `timestamp + 60`。
- 通常 alert は従来どおり別送し、ライブアクティビティ追加後も温存する。

## iOS 側（Phlox-mobile）への実装依頼

1. **通知権限とリモート通知登録**: `UNUserNotificationCenter` の権限要求＋`registerForRemoteNotifications`。
2. **デバイストークンの登録送信**: `didRegisterForRemoteNotificationsWithDeviceToken` で hex 化し、契約1の `POST /device-tokens` へ送信（起動時・トークン変更時に再送。失敗時は次回起動/復帰時に再試行でよい）。environment はビルド構成から判定。
3. **受信処理**: 通知タップで該当セッション（`phlox.sessionId`）の画面へ遷移し、pull API で再同期。フォアグラウンド受信時はアプリ内で更新（バナー表示は任意）。
4. **再同期の独立性**: push に依存しない復帰時 pull 再同期を維持（契約2の配信保証なし前提）。
5. **Apple Developer 情報の共有（Mac 側設定に必要）**: 次の4点を Mac 側へ提供すること——**APNs Auth Key（.p8）・Key ID・Team ID・bundle ID**。Mac 側はこれを設定して送信する（本 run では注入可能な設定として実装し、供給後に有効化）。

## 検証（両側）

- iOS 側: sandbox 環境で実機受信を確認（Mac 側資格情報の設定後）。それまでは `POST /device-tokens` が 200 を返すことまで確認できる（Mac 側実装のマージ後）。
- Mac 側: フェイク APNs サーバーに対する送信・410 処理のテストまで本 run で green にする。実機到達の end-to-end は両側が揃った時点（D-1 統合検証）で実施し、それまで「未検証」と明示する。

## 参照

- 採用決定: `docs/adr/0075-adopt-apns-for-mobile-notifications.md`
- 現行の接続・認証面: `docs/architecture/mobile-proxy.md`（Bearer トークン・Tailscale 経由・API 一覧）
- 脅威モデル（トークン=Mac 全権）: `docs/adr/0074-mobile-remote-control-design.md`
- 次段の UX 改善（QR ペアリング・A-1 の後に実装）: `docs/adr/0076-adopt-qr-pairing-for-mobile.md`
