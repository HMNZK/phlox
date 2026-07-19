---
status: accepted
last-verified: 2026-07-19
---

# ADR 0103: 質問カードの iOS ミラー配線（wire DTO・POST /question・App 層 witness）

> **このファイルの役割**: macOS の質問カード（[ADR 0102](0102-ask-user-question-control-protocol.md)）を iOS へミラーするための wire 契約（DTO 形・REST エンドポイント）設計と、App 層の準拠（witness）解決に関する裁定を記録する。
> **書かないもの**: control protocol 自体（→ ADR 0102）、iOS 側のデコード・カード UI 判断（→ [iOS ADR 0024](../../../ios/docs/adr/0024-user-question-card-mirror.md)）、現状の REST API 表（→ [architecture/mobile-proxy.md](../architecture/mobile-proxy.md)）。

## 決定

### 1. messages DTO に `userQuestion` 型を追加

`GET /sessions/{id}/messages` の `ChatMessageDTO` に `type == "userQuestion"` のケースを追加し、以下のフィールドを持たせる:

```
{"requestId": String, "state": "pending"|"answered"|"expired",
 "questions": [{"question","header","multiSelect","options":[{"label","description"?}]}],
 "answers": {"<question文>": [String]}? }
```

`answers` は **present 時のみ**出力（pending は省略・standard `Encodable` 合成ではなく `answers` を `if let` 分岐で custom encode）。`options[].description` も **present 時のみ**出力。

### 2. 回答は POST /sessions/{id}/question

`POST /sessions/{id}/question` body `{"requestId": String, "answers": {"<question文>": [String]}}`。

| 結果 | ステータス |
|---|---|
| 受理 | `200` |
| セッション不在 or pending 質問なし | `404` |
| body 不正（decode 失敗・requestId 空） | `400` |

配線: `DashboardViewModel` へ `POST /question` を渡し、`ChatSessionViewModel.respondToUserQuestion` へ転送する。

### 3. ワイヤキーの正本は macOS/iOS で二重管理

wire キー定数は macOS 側 `ControlQuestionWireContract`（`Packages/ControlServer/Sources/ControlServer/ControlQuestionWireContract.swift`）と iOS 側 `PhloxQuestionWireContract` の**双方**に定義し、値を一字一句一致させる（クロスプラットフォームのため単一ファイル共有はしない。既存の wire 契約群と同じパターン）。両契約とも `implemented` フラグを持ち、`false`（骨組み）→ `true`（本実装完了）で段階制御する。**フラグの反転はその側の実装完了と同時にのみ行う**（虚偽報告防止のため、フラグだけを先行して true にすることを禁じる）。

### 4. App 層 witness の裁定：転送ラッパを書かない

task-3 実装者は「`macos/App/ControlActionDashboard+DashboardViewModel.swift` に `respondToUserQuestion` の witness が無いため、実アプリ経路では protocol extension の default `false` が使われ POST は常時 404」と開示したが、**この開示は誤り（false negative）と裁定した**。

**根拠**: Swift の retroactive conformance では、型自身のモジュール内にある**同シグネチャの public メソッド**が protocol extension の default より優先して witness になる。`extension DashboardViewModel: @retroactive ControlActionDashboard`（App 層、明示 witness なし）に対し、`DashboardViewModel` 本体（DashboardFeature）に task-3 が追加した `public func respondToUserQuestion(id:requestId:answers:) async -> Bool` が要件と一字一句同一シグネチャであるため、これが自動的に witness として解決される。

この裁定は stage1 が `/tmp` での swiftc 3モジュール実験（`Proto`/`Model`/`App` の最小再現）で実証し、stage2 が同ファイル内の `sendMessage` 前例コメント（「本体の同シグネチャ public メソッドが直接 witness する。ここに転送ラッパを書くと無限再帰」）と実コード読解で独立に裏取りした。

**申し送り: App 層に `respondToUserQuestion` の転送ラッパを追加してはならない。** 追加すると `sendMessage` と同型の無限再帰を招く（2026-07-12 に実際に発生したシステムクラッシュの再発）。実アプリ経路は `POST /question → ControlServer → ControlActionHandler.handleRespondQuestion → DashboardViewModel.respondToUserQuestion（retroactive witness）→ ChatSessionViewModel.respondToUserQuestion → 200/404` で完結しており、App 層の変更は不要かつ有害。

## 棄却案

- **wire キー定数を単一ファイルで共有**: macOS/iOS はビルド系が別れており単一ソース共有の仕組みが無い。二重管理＋レビューでの一致確認で代替。
- **実装者の開示どおり App 層に witness を追記**: 上記の理由で無限再帰を招くため却下。裁定はレビュー2段階（swiftc 実験＋前例照合）で独立に確認済み。

## 結果

- `AppBootstrap` 140 / `ControlServer` 113 / `DashboardFeature` 1384 テスト green。凍結受け入れテスト（`AcceptanceUserQuestionWireTests` / `UserQuestionRoutingAcceptanceTests`）無改変で green。
- `ChatMessageDTO` / `SubAgentMessagesDTO` を `Encodable` 化（decode 利用箇所は既存経路で0件のため無害）。既存7種 DTO の出力は `type == messageType` ガード内に新フィールドを閉じ込めるため不変。
- iOS 側の消費（デコード・カード UI）は [iOS ADR 0024](../../../ios/docs/adr/0024-user-question-card-mirror.md) 参照。
