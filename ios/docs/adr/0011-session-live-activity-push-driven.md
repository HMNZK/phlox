---
status: active
last-verified: 2026-07-15
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

## 結果

- ロック画面へのライブアクティビティ自動表示・更新が push 駆動で実装され、既存の alert 通知・device token 登録・静的ウィジェット（ADR 0009）は無改変のまま温存された。
- 多重起動防止は macOS 側 `(sessionId, deviceToken)` 予約と iOS 側 `sessionId` 単位のインデックスの2層で担保される（stage-2 レビューで「多重起動防止が未実装」の MUST 差し戻しを経て実装、decision-log wave-5 フェーズ2/3）。
- **未検証**: ロック画面への実表示と APNs 実配信は実機＋実 Mac push が必要なため本 run では確認できていない（シミュレータでのユニット・契約テスト・ビルドまでは green）。

## 却下した代替案

- **ローカル駆動**（iOS アプリがフォア/バックグラウンドで自ら Activity を開始・更新する）: アプリを閉じている間の自動受信という目的を満たさないため却下（ユーザーが push 駆動を明示選択）。
- **macOS 側の多重起動防止を `sessionId` のみのユニーク制約にする**（`deviceToken` を無視）: 複数デバイス登録時に一部デバイスへの push-to-start が予約漏れで送られなくなるため、`(sessionId, deviceToken)` の複合キーを採用した。
