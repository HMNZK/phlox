---
status: active
last-verified: 2026-10-18
---

# ADR 0011: セッション状態のライブアクティビティを push 駆動（ActivityKit pushToStart + macOS APNs）で実装する

> **このファイルの役割**: wave-5（task-5）で、セッション状態変化をロック画面へ自動表示するライブアクティビティ機能を、ローカル駆動でなく push 駆動で実装した決定と、多重起動防止・iOS/macOS 契約一致の設計判断を記録する。
> **書かないもの**: payload/ContentState のフィールド定義そのもの（→ [macos/docs/specs/apns-companion-contract.md](../../../macos/docs/specs/apns-companion-contract.md) 契約2-LA）。現行のライブアクティビティ構成（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

wave-5 task-5 の目的は、セッションの状態変化（実行中→質問待ち/承認待ち/完了など）を、iOS アプリを閉じていてもロック画面に自動表示・更新することだった。導入前は ActivityKit を一切使っておらず、ロック/ホーム画面ウィジェット（wave-4、ADR 0009）は App Group 経由の pull 型静的タイムラインのみで、push は alert 固定（`APNsClient.swift:206` にハードコード）だった。

ゲート①でユーザーが「push 駆動（iOS ActivityKit + macOS APNs）で自動受信」を明示決定した（decision-log wave-5 フェーズ0/1）。iOS 側の push-to-start は iOS 17.2+ が必要で、ユーザー許可プロンプトが実機でのみ発火する。

## 決定

- **iOS**: `SessionActivityAttributes`（`ActivityAttributes` 準拠、`ContentState` は `sessionId`/`sessionName`/`status`/`summary`）を新設。`LiveActivityCoordinator`（`@available(iOS 17.2, *)` の `actor`）が `Activity<SessionActivityAttributes>.pushToStartTokenUpdates` を購読して push-to-start トークンを Mac へ登録し、`activityUpdates` を購読して Activity ごとの update トークンも登録する。`LiveActivitySessionIndex` が `sessionId → activityId` を1対1に保ち、同一セッションに対する重複 Activity は `.end(dismissalPolicy: .immediate)` で即終了させる。
- **macOS**: 既存の通知トリガ受け皿 `APNsNotificationBridge.notify(_:)`（`RemoteSessionNotifier`、`sessionCompleted`/`approvalPending` イベントを `SessionViewModel`/`ChatSessionViewModel` から受ける）に、liveactivity 送信を**追加**する形にした（既存 alert 送信は無改変で温存）。登録済み update token が無いセッションには push-to-start（`event:"start"`）を送り、あれば `update`/`end` を送る。`APNsClient` の `apns-push-type` は呼び出し側からパラメータ化し（従来 alert 固定）、liveactivity 指定を追加した。
- **多重起動防止（2層）**: macOS 側で `actor LiveActivityStartRegistry` が `(sessionId, deviceToken)` を複合キーとする `Set` へアトミックに `insert` し、`.inserted == true` の場合だけ push-to-start を送信（予約）、送信失敗時は `release` して再試行を許す。iOS 側も独立に `LiveActivitySessionIndex` で `sessionId` あたり1 Activity の制約を保証する。
- **契約一致**: iOS の `SessionActivityAttributes.ContentState` の Codable キーと macOS の payload エンコーダのキー（`content-state`/`stale-date`/`dismissal-date`/`attributes-type` 等）を一字一致させ、iOS 側 `SessionActivityContractTests` で凍結。`macos/docs/specs/apns-companion-contract.md` 契約2-LA に文書化した。

## 段階7の表示・遷移（2026-10-18）

- ContentState / APNs の既存キーは変えない。状態コードを `SessionGlanceState` に変換し、記号・状態の語・名前・Mac の summary の順に描く。`session_exited` は非0終了なのでエラーとし、独立した「終了」の状態は作らない。未知コードも状態不明と summary を表示する。
- ロック画面は端末の外観でライト／ダークを解決し、無応答は紫。Dynamic Island の背景は OS の黒、状態の色は必ずダークの値。compact の `Wait` を承認待ち・質問あり・無応答などの状態の語に置き換える。
- ロック画面と Dynamic Island に同じ `phlox://session/<id>` の `widgetURL` を付ける。`PhloxMobileApp` → `PushCoordinator.pendingSessionID` → 解除・タップ後の一覧取得成功 → `AppRoot` の詳細画面（既存の承認・質問カード）へ進む。取得成功後に対象が無ければ一覧へ戻し F8 を表示する。未取得・通信失敗では要求を保留する。
- 通知本文は Mac の `NotificationEvent.body` が生成する（質問は「質問があります」）。iOS の通知本文生成・着色のコードは無く、OS の標準通知を維持する。通知の許可時期も変更しない。
- 拡張のウィジェットと Live Activity の実 View を描画テストにも組み込む。Dynamic Island・通知の OS 枠と APNs の実配信は手元の描画テストの対象外。検証結果と残差は [段階7の作業記録](../delivery/0027-ios-redesign-stage7-worklog.md)。

## 結果

- ロック画面へのライブアクティビティ自動表示・更新が push 駆動で実装され、既存の alert 通知・device token 登録・静的ウィジェット（ADR 0009）は無改変のまま温存された。
- 多重起動防止は macOS 側 `(sessionId, deviceToken)` 予約と iOS 側 `sessionId` 単位のインデックスの2層で担保される（stage-2 レビューで「多重起動防止が未実装」の MUST 差し戻しを経て実装、decision-log wave-5 フェーズ2/3）。
- **未検証**: ロック画面への実表示と APNs 実配信は実機＋実 Mac push が必要なため本 run では確認できていない（シミュレータでのユニット・契約テスト・ビルドまでは green）。

## 却下した代替案

- **ローカル駆動**（iOS アプリがフォア/バックグラウンドで自ら Activity を開始・更新する）: アプリを閉じている間の自動受信という目的を満たさないため却下（ユーザーが push 駆動を明示選択）。
- **macOS 側の多重起動防止を `sessionId` のみのユニーク制約にする**（`deviceToken` を無視）: 複数デバイス登録時に一部デバイスへの push-to-start が予約漏れで送られなくなるため、`(sessionId, deviceToken)` の複合キーを採用した。
