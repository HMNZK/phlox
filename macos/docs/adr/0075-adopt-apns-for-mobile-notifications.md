---
status: active
last-verified: 2026-07-11
---

# ADR 0075: サーバー→モバイルの通知経路として APNs を採用する

> **このファイルの役割**: リアルタイム更新方式（delivery 0018 の A-1 / B-2）の方向を決める。ADR 0074 の決定5（現行は pull 型）を「当時の実装済み事実」として維持したまま、将来方向として APNs 採用を記録する。
> **書かないもの**: APNs 基盤の詳細設計（実装 run の設計成果物に委ねる）。

## 文脈

現行のモバイル連携は pull 型（`GET /sessions/{id}/wait` ロングポーリング + ポーリング）で、サーバー→モバイルの push 経路を持たない（ADR 0074 決定5、`docs/delivery/0018-mobile-integration-remaining-tasks.md` A-1）。2026-07-11 の agentic-loop run（mobile-remaining、worklog 0039）で3案——(a) APNs push / (b) WebSocket / (c) 現状ポーリング維持——を現行コードに接地して比較分析し、ユーザーが方向を判断した。

比較の要点（詳細は worklog 0039 の要旨）:
- APNs のみが iPhone のバックグラウンド/ロック中・離席時の通知に対応できる。
- WebSocket はフォアグラウンドの即時性最良だが、ControlServer（現在は 1 リクエスト応答後 close の request/response 型）を接続維持型へ改修する幅が大きく、バックグラウンド通知の代替にならない。
- ポーリング維持は追加リスク最小だが、離席時の即時通知を提供できない。

## 決定

**サーバー→モバイルの通知経路として APNs を採用する**（2026-07-11 ユーザー決定）。

- 通知の役割は「シグナル」に限定する: セッション完了・承認待ち発生をモバイルへ通知し、データ本体の同期は従来どおり既存の pull API（`/wait`・`/messages`・`/approvals`）で行う。ADR 0074 の pull 型 API 面は変更しない。
- 実装は本 ADR のスコープ外（別 run）。delivery 0018 A-1 の分解（APNs 送信基盤・デバイストークン登録エンドポイント・通知トリガー）を出発点とする。

## 棄却案

- **WebSocket（サーバープッシュ）**: バックグラウンド/ロック中の通知に応えられず、ControlServer の接続維持型への改修コストが APNs の外部依存コストに見合わない。
- **現状ポーリング維持の恒久化**: 離席時・ロック中の通知という要件を満たせない。

## 結果

- delivery 0018 の A-1 は「設計判断待ち」から「採用決定済み・実装待ち」へ遷移し、B-2（WebSocket）は不採用が確定する。
- 実装の前提条件が確定する: Apple Developer の APNs Auth Key/証明書と鍵管理、ControlServer へのデバイストークン登録 API、Mac 側送信クライアント、通知トリガー（完了・承認待ち）、および Phlox-mobile（別リポジトリ、D-1）側の APNs 登録・受信実装。
- iOS のバックグラウンド push は配信保証がないため、通知は「取得の合図」であり、正確な状態は受信後の pull で確定する設計とする（Apple の background remote notifications の制約に従う）。
