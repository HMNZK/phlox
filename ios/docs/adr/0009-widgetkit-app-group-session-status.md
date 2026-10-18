---
status: active
last-verified: 2026-10-18
---

# ADR 0009: ロック/ホーム画面ウィジェットは WidgetKit 拡張＋App Group 共有 UserDefaults で実装する

> **このファイルの役割**: セッション状態をロック画面／ホーム画面に表示する WidgetKit 拡張（`PhloxWidget`）を追加し、本体アプリとの状態共有を App Group + `UserDefaults` で行う判断を記録する。
> **書かないもの**: ウィジェットの見た目の詳細実装（→ [architecture/overview.md](../architecture/overview.md)）。

## 文脈

セッションの実行状態（Running/Waiting/Finished/Error）をロック画面・ホーム画面ウィジェットから確認したい、という要件に対し、iOS のウィジェット実装は必ず**別プロセスの app extension**（`WidgetKit` の `TimelineProvider`）として動く。本体アプリと拡張プロセスはメモリ空間を共有しないため、本体が持つ `[Session]` をそのまま参照できず、プロセス間で読み書きできる共有ストレージが要る。

## 決定

新規ターゲット `PhloxWidget`（`ios/PhloxWidget/`、`type: app-extension`、`deploymentTarget: 18.0`）を `ios/project.yml` に追加した。本体 `PhloxMobile` に `embed: true` で依存させる。

- **App Group**: `group.com.phlox.mobile` を本体・拡張の両エンタイトルメント（`ios/App/PhloxMobile.entitlements`・`ios/PhloxWidget/PhloxWidget.entitlements`）に追加。バンドル ID は本体 `com.phlox.mobile.PhloxMobile`、拡張 `com.phlox.mobile.PhloxMobile.PhloxWidget`。
- **共有ストア**: `PhloxCore/Shared/SharedSessionStore`。App Group の JSON キーは v1 のまま、`SharedSessionSummary` の既存5項目に optional な `displayState: String?` を足す。未読・無応答は解決済みの値で渡し、エージェント種別や UI 型は保存しない。旧データは英語ラベル・補足から復元し、未知の値は状態不明にする。日付は `millisecondsSince1970` のまま。
- **書き込み**: `SharedSessionWriter.write(summaries:)` が入力順のまま保存し、成功後に `WidgetCenter.shared.reloadTimelines`。`DesignSystemIOS/SessionGlanceProjection` の `write(sessions:)` が `Session.displayState`（共有の判定規則）を最小の表示値へ変換する。本体の一覧状態変更から呼び、拡張は最新の `updatedAt` の1件を選ぶ。
- **空の扱い**: `AppRoot.writeSharedSessionState()` は未取得・通信失敗のときは直近値を保持する。取得成功の `.loaded([])` / `.empty` は空を保存し、削除後に古いセッションを残さない（段階7で従来の非空ガードを置換）。
- **配色**: 状態の色の数値は `PhloxCore/SessionGlanceState` で共有し、`IOSColor` も参照する。拡張には `DesignSystemIOS`（Markdown 等を含む）の依存を足さず、SwiftUI への変換だけを `GlanceStyle` に置く。端末の `colorScheme` に従い、アプリの `ThemeStore` は参照しない。背景・状態別の地の透明度は `GlanceCatalog` の値。
- **遷移**: セッションの表示に `widgetURL(phlox://session/<id>)`。通知と同じ保留経路を使う（ADR 0011 の段階7追記）。空表示にはセッション URL を付けない。
- **表示**: `SessionStatusWidget`（`StaticConfiguration`、`.accessoryRectangular`＋`.systemSmall` の2ファミリ）。`TimelineProvider` はストア読み取り失敗時（App Group 未設定・decode 失敗等）に空配列へフォールバックし、ウィジェット自体はクラッシュさせない。

## 結果

- 本体・拡張間の状態共有は同期 API（`UserDefaults`）で完結し、ネットワーク層・XPC 等の追加インフラは不要。
- 拡張は `PhloxCore` のみに依存し `PhloxNetworking`/`Features` には依存しない（`APPLICATION_EXTENSION_API_ONLY: YES` の制約とも整合）。
- **既知の実機ビルドブロッカー**: Apple Developer portal 側で App ID `com.phlox.mobile.PhloxMobile` と `com.phlox.mobile.PhloxMobile.PhloxWidget` の双方に App Group `group.com.phlox.mobile` を登録しないと、実機向けコード署名が `application-groups` entitlement 不一致で失敗する。ローカル `project.yml`/entitlements の変更だけでは実機ビルドは通らない（→ [delivery/0002](../delivery/0002-mobile-ui-overhaul-wave4-worklog.md) に詳細）。

## 却下した代替案

- **App Group を使わず Darwin通知やXPCで都度問い合わせる**: WidgetKit のタイムラインは本体アプリが起動していない間も描画されるため、本体プロセスへの都度問い合わせは前提として成立しない（拡張は独立プロセスとして単独起動されうる）。ディスクベースの共有ストレージが必須という制約に合わせ App Group + UserDefaults を採用した。
- **`Session` 型をそのまま共有ストアへ書く**: ウィジェット表示に不要なフィールド（ネットワーク層の内部状態等）まで JSON にシリアライズすることになり、拡張側の依存を `PhloxCore` の一部に絞る意図に反するため、表示専用の `SharedSessionSummary` DTO を新設した。
