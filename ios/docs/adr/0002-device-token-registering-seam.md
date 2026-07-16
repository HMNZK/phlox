# ADR 0002: デバイストークン登録は PhloxAPI 非拡張の独立プロトコル（DeviceTokenRegistering）で切る

- **ステータス**: 承認済み（agentic-loop フェーズ1 契約・フェーズ3 レビュー通過）
- **日付**: 2026-07-11
- **決定者**: PM オーケストレーター
- **関連**: `doc/apns-implementation-request.md`（契約 v1）、`doc/architecture.md` §push、`Packages/PhloxKit/Sources/PhloxCore/Push/`

---

## コンテキスト

APNs push 対応（契約 v1）で `POST /device-tokens` の送信口が必要になった。既存の Mac 向け HTTP API は `PhloxAPI` プロトコル（PhloxCore の DI シーム）に集約されており、素直な案は `PhloxAPI` に `registerDeviceToken` を追加することだった。

## 決定

`PhloxAPI` を変更せず、**独立プロトコル `DeviceTokenRegistering`**（PhloxCore/Push）を新設し、`PhloxAPIClient` が extension で追加準拠する。利用側（`PushRegistrationService`）は `any DeviceTokenRegistering` のみに依存する。

## 理由

- `PhloxAPI` に要求を足すと、**全既存準拠体（本体 actor＋テスト用モック多数）が一斉にコンパイル破壊**される。デバイストークン登録はセッション操作と読み手が異なる narrow な関心であり、巻き添えに見合わない。
- 利用側の必要最小面（登録1メソッド）だけを注入でき、テストダブルが1メソッドで済む。
- 実装は `PhloxAPIClient` の既存ヘルパー（`encode`/`data(method:path:bodyData:retry:)` — 本 run で internal 化）を再利用するため、Bearer 注入・エラー正規化の挙動は既存 API と完全に同一。

## 棄却した代替案

- **PhloxAPI へのメソッド追加**: 上記の一斉破壊。protocol extension のデフォルト実装（throw する仮実装）で回避する案は「準拠し忘れが実行時まで発覚しない」ため不採用。
- **独立クライアントクラスの新設**: Bearer/エラー正規化/接続先解決の重複実装になる。実際に task-1 初回実装が（private スコープ制約の誤解から）Mirror 反射＋POST 重複実装で提出され、レビューで棄却された経緯が重複実装の脆さを裏づける。

## 帰結

- 新しい狭い関心（例: 将来の QR ペアリング API）も同じパターン（独立プロトコル＋extension 準拠）で足せる。
- `PhloxAPIClient` のヘルパー2つが private→internal になった（別ファイル extension からの再利用点。Swift の private はファイルスコープ）。
