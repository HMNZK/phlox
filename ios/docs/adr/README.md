---
status: active        # active | completed | superseded | archived
last-verified: 2026-07-16
---

# ADR（アーキテクチャ決定記録）索引 — iOS (PhloxMobile)

iOS コンパニオンアプリ固有の決定の **理由** を残す。追記専用・不変。覆す時は新しい番号で
起こし、旧を `superseded` にしてリンクする。macOS 側と共有する横断的な決定は
`../../../macos/docs/adr/` を参照。

- 命名: `NNNN-短い決定名.md`（4 桁ゼロ詰め kebab-case）

## 一覧
| 番号 | 決定 | ステータス |
|---|---|---|
| 0025 | [最低対応を iOS 18.0 へ引き上げ、`TextField(selection:)` でカーソル位置を扱う](0025-ios18-textselection-for-cursor-aware-input.md) | accepted |
| 0024 | [iOS 質問カードミラー（前方互換デコード・成功後楽観更新・確定ボタン式 UI）](0024-user-question-card-mirror.md) | accepted |
| 0021 | [QR ペアリング直後に「接続中…」オーバーレイを出し、閉じ判定をセッション一覧のロード成功でゲートする](0021-connecting-overlay-gated-on-session-list-load.md) | active |
| 0020 | [送信済みメッセージの画像添付バッジをクライアント側 side-map で表示する（サーバ非依存）](0020-chat-attachment-badge-client-side.md) | active |
| 0019 | [到達性のオンデマンド再判定（refresh）で QR ペアリング直後の stale offline を解消する](0019-reachability-on-demand-refresh.md) | active |
| 0018 | [入力欄からドラッグ閉じバーと音声入力ボタンを撤去し、送信/停止を右スロットに常設する](0018-input-bar-remove-drag-and-voice.md) | active |
| 0017 | [起動時 Face ID ゲートを既定オフにする](0017-face-id-launch-gate-default-off.md) | active |
| 0016 | [チャット入力欄をカード型からコンパクトなピル型へ再デザインし、送信/停止を同一スロットに統合する](0016-input-bar-compact-pill-redesign.md) | active |
| 0015 | [音声入力のクラッシュを、危険 API 呼び出し前のガードと nonisolated ブリッジで根絶する](0015-voice-input-crash-hardening.md) | active |
| 0014 | [セッション一覧上部空白バグの修正として UINavigationBar appearance 再適用を冪等化する](0014-navigation-chrome-appearance-idempotent-install.md) | active |
| 0013 | [セッション詳細の右上メニュー由来 presentation を .sheet/.alert の別 View 層分離＋enum 単一ソースにする](0013-session-detail-menu-presentation-single-source.md) | active |
| 0012 | [チャット入力欄の branch 表示は「表示のみ」とし、機能化しない](0012-input-bar-branch-display-only.md) | active |
| 0011 | [セッション状態のライブアクティビティを push 駆動（ActivityKit pushToStart + macOS APNs）で実装する](0011-session-live-activity-push-driven.md) | active |
| 0010 | [入力欄内モデルセレクタチップを復活させ、右上メニューと併存させる](0010-restore-inline-model-selector-chip.md) | active |
| 0009 | [ロック/ホーム画面ウィジェットは WidgetKit 拡張＋App Group 共有 UserDefaults で実装する](0009-widgetkit-app-group-session-status.md) | active |
| 0008 | [新規タスク（spawn）画面を廃止し、セッション一覧からのドラフト compose フローに統合する](0008-spawn-screen-to-draft-compose.md) | active |
| 0007 | [下部タブバーから「概要（overview）」タブを廃止し3タブ構成にする](0007-remove-overview-tab.md) | active |
| 0006 | [下部タブバーは独自実装とし SwiftUI TabView を採用しない](0006-appshell-custom-tab-bar.md) | active |
| 0005 | [モバイル wave-2 ワイヤ消費とアカウント使用量／ターン使用量の型分離](0005-mobile-wave2-wire-consumption.md) | active |
| 0004 | [iOS 外観を rootContent の再マウントで即時反映する](0004-ios-appearance-live-switch-via-root-remount.md) | active |
| 0003 | [Tailscale 接続の平文 HTTP とクライアント側認証ガード](0003-plaintext-http-tailscale-client-guard.md) | active |
| 0002 | [デバイストークン登録は独立プロトコル（DeviceTokenRegistering）で切る](0002-device-token-registering-seam.md) | active |
| 0001 | [AgentDomain を macOS 側パッケージと共有する](0001-shared-agent-domain.md) | active |
