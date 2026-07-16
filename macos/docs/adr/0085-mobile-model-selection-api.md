---
status: active
last-verified: 2026-07-14
---

# 0085: モバイル向けモデル選択 API（GET settings / POST model）

## 決定

モバイルコンパニオンからセッションのモデルを参照・変更できるよう、Control API に
`GET /sessions/{id}/settings` と `POST /sessions/{id}/model` を追加する。適用可否は
エージェント種別ではなく**実際の設定適用能力**（`ChatSessionViewModel.canApplySpawnAgentSettings`
= `SpawnAgentSettingsControlling` な spawn 設定クライアントの実在）で判定し、GET / POST の
能力ゲートを同一にする。モデル適用は `setSpawnAgentModel` 経由（model/permission/effort の
フルスナップショット）に限定し、`applySpawnAgentSettings(model:)` の置換セマンティクスで
permission-mode（既定 bypassPermissions）が失われる事故を防ぐ。

## 文脈

- iOS 側の入力欄モデル選択チップ（Claude アプリ相当の UX）は、従来のモバイル API
  （`POST /sessions` = kind/backend のみ、`POST /send` = text/images のみ）では実現不能だった。
- レビューで2つの罠を検出し設計に反映した: ①種別ベース判定では「一覧を広告するのに適用は
  no-op で 200」という虚偽反映が起こる（復元失敗プレースホルダ・設定クライアント欠如）
  ②model 単独の設定適用は置換セマンティクスで permission を剥がす。

## 結果

- 非対応セッション（codex app-server 等）は 200 + `availableModels: []` を返し、iOS は
  チップを非表示にする（404 は未知 id のみ）。
- ワイヤ形状の正本はコード内定数 `ControlModelWireContract` / `PhloxModelWireContract`
  （凍結テストで両側一致を固定）。契約全文は
  `ios/docs/specs/mobile-api-extensions-contract.md` §6。

## 却下した代替案

- `POST /sessions`（spawn）への model パラメータ追加のみ: 既存セッションのモデル変更が
  できず、依頼の主目的（チャット中の切替）を満たさない。
- iOS 側 UI のみ先行: 選択しても Mac に反映されない見た目だけの機能になるため却下。
