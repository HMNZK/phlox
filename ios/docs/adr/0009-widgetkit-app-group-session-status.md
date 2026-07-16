---
status: active
last-verified: 2026-07-15
---

# ADR 0009: ロック/ホーム画面ウィジェットは WidgetKit 拡張＋App Group 共有 UserDefaults で実装する

> **このファイルの役割**: セッション状態をロック画面／ホーム画面に表示する WidgetKit 拡張（`PhloxWidget`）を追加し、本体アプリとの状態共有を App Group + `UserDefaults` で行う判断を記録する。
> **書かないもの**: ウィジェットの見た目の詳細実装（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

セッションの実行状態（Running/Waiting/Finished/Error）をロック画面・ホーム画面ウィジェットから確認したい、という要件に対し、iOS のウィジェット実装は必ず**別プロセスの app extension**（`WidgetKit` の `TimelineProvider`）として動く。本体アプリと拡張プロセスはメモリ空間を共有しないため、本体が持つ `[Session]` をそのまま参照できず、プロセス間で読み書きできる共有ストレージが要る。

## 決定

新規ターゲット `PhloxWidget`（`ios/PhloxWidget/`、`type: app-extension`、`deploymentTarget: 17.0`）を `ios/project.yml` に追加した。本体 `PhloxMobile` に `embed: true` で依存させる。

- **App Group**: `group.com.phlox.mobile` を本体・拡張の両エンタイトルメント（`ios/App/PhloxMobile.entitlements`・`ios/PhloxWidget/PhloxWidget.entitlements`）に追加。バンドル ID は本体 `com.phlox.mobile.PhloxMobile`、拡張 `com.phlox.mobile.PhloxMobile.PhloxWidget`。
- **共有ストア**: `PhloxCore/Shared/SharedSessionStore`（`public struct`、`PhloxCore` に配置し本体・拡張の双方から `import PhloxCore` で参照可能にする）。`UserDefaults(suiteName: "group.com.phlox.mobile")` を薄くラップし、`SharedSessionSummary`（`id`/`statusLabel`/`title`/`detail`/`updatedAt` の5フィールドのみ、`Session` 全体ではなく表示に必要な最小限に絞った DTO）を JSON（`millisecondsSince1970`）で `write`/`read` する。**純ロジックで UIKit/WidgetKit に非依存**なため round-trip の単体テストが書ける（`Wave4SharedSessionStoreTests`）。
- **書き込み**: `PhloxCore/Shared/SharedSessionWriter` が `[Session]` → `[SharedSessionSummary]` への変換（`updatedAt` 降順ソート）と `SharedSessionStore.write` を担い、書き込み成功後に `WidgetCenter.shared.reloadTimelines(ofKind:)` を呼んでウィジェットの再描画をトリガする。`AppRoot` が起動時 `.task` と `listVM.lastKnownSessions` の `onChange` の両方で `writeSharedSessionState(_:)` を呼ぶ。
- **空配列上書きガード**: `writeSharedSessionState` 冒頭に `guard !sessions.isEmpty else { return }` を置く。起動直後は `listVM` が新規生成され `lastKnownSessions` が未ロード（空配列）の瞬間があり、ガード無しではその空配列でストアを無条件上書き→`reloadTimelines`→ウィジェットが毎回「NO SESSIONS」に潰れるバグがあった（stage-2 Codex レビューで検出、decision-log.md task-6 stage-2 HIGH 参照）。ガード追加により未ロード/一時的な空では直近の非空状態を保持する。**トレードオフ**: 全セッションを実際に削除して空になった場合もウィジェットには前状態が残る（status ウィジェットとして許容。厳密化は「ロード完了フラグ」導入の follow-up 候補）。
- **表示**: `SessionStatusWidget`（`StaticConfiguration`、`.accessoryRectangular`＋`.systemSmall` の2ファミリ）。`TimelineProvider` はストア読み取り失敗時（App Group 未設定・decode 失敗等）に空配列へフォールバックし、ウィジェット自体はクラッシュさせない。

## 結果

- 本体・拡張間の状態共有は同期 API（`UserDefaults`）で完結し、ネットワーク層・XPC 等の追加インフラは不要。
- 拡張は `PhloxCore` のみに依存し `PhloxNetworking`/`Features` には依存しない（`APPLICATION_EXTENSION_API_ONLY: YES` の制約とも整合）。
- **既知の実機ビルドブロッカー**: Apple Developer portal 側で App ID `com.phlox.mobile.PhloxMobile` と `com.phlox.mobile.PhloxMobile.PhloxWidget` の双方に App Group `group.com.phlox.mobile` を登録しないと、実機向けコード署名が `application-groups` entitlement 不一致で失敗する。ローカル `project.yml`/entitlements の変更だけでは実機ビルドは通らない（→ [delivery/0002](../delivery/0002-mobile-ui-overhaul-wave4-worklog.md) に詳細）。

## 却下した代替案

- **App Group を使わず Darwin通知やXPCで都度問い合わせる**: WidgetKit のタイムラインは本体アプリが起動していない間も描画されるため、本体プロセスへの都度問い合わせは前提として成立しない（拡張は独立プロセスとして単独起動されうる）。ディスクベースの共有ストレージが必須という制約に合わせ App Group + UserDefaults を採用した。
- **`Session` 型をそのまま共有ストアへ書く**: ウィジェット表示に不要なフィールド（ネットワーク層の内部状態等）まで JSON にシリアライズすることになり、拡張側の依存を `PhloxCore` の一部に絞る意図に反するため、表示専用の `SharedSessionSummary` DTO を新設した。
