---
status: completed
last-verified: 2026-07-15
---

# Worklog 0001: single モードのプロジェクト選択で新規セッション開始画面を表示

## 概要

macOS デスクトップアプリで、サイドバーのプロジェクト**名**クリックが表示モードに関わらず常にグリッドビューへ切り替わっていたのを、**表示モード別の導線**に変更した。シングルビュー（`.single`）ではグリッドへ切り替えず、プロジェクトを選択して「新規セッション開始画面」（`AgentStartCards`）を表示する。グリッド/チームは従来挙動を維持。

## 変更（コード）

- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Router/AppRouter.swift`: `selectProjectFromSidebar(_:)` を追加（`.single`→`selectProject`＋`selectedSession=nil`／`.grid`・`.team`→`toggleGridFilter`＋`viewMode=.grid`）。
- `macos/Packages/DashboardFeature/Sources/DashboardFeature/Dashboard/DashboardSidebarView.swift`: 名前タップの `onToggleFilter` を上記メソッド1呼び出しへ置換。名前テキストのツールチップを「このプロジェクトを選択」へ。
- テスト: `Tests/DashboardFeatureTests/AcceptanceSingleModeProjectSelectTests.swift`（凍結受け入れテスト2件）。

## 検証

- `DashboardFeature` パッケージ `swift test`: 全 green（1327 件）。ベースライン 1325 件 green から回帰なし（＋新規2件）。
- macOS アプリ Debug ビルド（`xcodebuild ... CODE_SIGNING_ALLOWED=NO`）: **BUILD SUCCEEDED**。
- 独立レビュー（persona-reviewer）: pass。契約完全一致・スコープ内・凍結テスト未改変。

## 生成/更新した docs

- `adr/0086-single-mode-project-select-shows-start-screen.md`（新規・決定）。
- `adr/0071-default-session-backend-chat.md`（line 30 の UI ニュアンスに前方リンク追記。single モードの挙動変更を反映）。
- `architecture/dashboard-empty-state-agent-cards.md`（single モードでサイドバー選択からこの空状態へ入る導線を追記）。
- `adr/README.md`（0086 を索引に追加）。

## 積み残し / 周知

- 既存 flaky: `ChatMessageCellsRenderTests` の TIFF 画像比較がフル並列時のみ間欠失敗（本変更と無関係・描画スナップショットの既存問題）。単体では安定 pass。
- `adr/0085-mobile-model-selection-api.md` が `adr/README.md` 索引に未記載（モバイル側の別作業由来のギャップ。本 run のスコープ外につき未修正）。
- backend=external（Cursor 実装）／mode=multi（N=1）で実施。
