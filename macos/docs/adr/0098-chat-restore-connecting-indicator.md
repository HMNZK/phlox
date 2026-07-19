---
status: active
last-verified: 2026-07-18
---

# 0098: セッション復元中の接続ローディング表示（ChatRestoreState.restoring・ChatConnectingIndicator）

> **このファイルの役割**: セッション復元中（履歴ロード〜一括反映の間）に接続ローディングアニメを中央表示し「描画のため待っている」ことを示す決定と、その状態モデル（`ChatRestoreState.restoring`）・表示ゲート・部品移植の設計理由を記録する。
> **書かないもの**: 履歴の件数制限（→ ADR 0051/0094/0097）。現行の実装仕様（→ `SessionFeature/ChatSessionView.swift`・`ChatSessionViewModel.swift`）。

## 文脈

macOS の `SessionRestoreCoordinator.restoreChatSession` は、空 transcript の `ChatSessionViewModel` を UI に追加してから `await vm.restore()` を待ち、完了時に `restoreTranscriptFromStore()` で全件を一括反映する。この間 transcript は空のままで、**復元中は空白**が表示されていた。macOS には接続中アニメが無く、ユーザーには描画待ちであることが伝わらない（iOS ADR 0023 と同種のUX不具合の macOS 版）。

## 決定

1. **復元中を状態モデルに明示する**。`ChatRestoreState`（従来 `notRestored`/`restored`/`failed`）に **`case restoring` を追加**（public・Equatable・Sendable 維持）。`ChatSessionViewModel.restore(...)` の**入口で `restoreState = .restoring`** を設定し、既存の完了経路で `.restored`、失敗経路で `.failed` へ遷移する（既存ロジックは不変）。
2. **表示ゲートは `restoreState == .restoring` かつ transcript が空**。`ChatSessionView` はこの条件の間だけ `ChatConnectingIndicator` を中央にオーバーレイ表示し、`.restored`/`.failed` で消す。View が `restoreState` を観測して出せるため、`SessionRestoreCoordinator` は変更不要（配線を最小に保つ）。不変条件: 復元中のみ表示・完了/失敗後は残らない・空データ/失敗で永久表示にならない。
3. **iOS の接続インジケータを macOS へ移植**。新規 `ChatConnectingIndicator`（SessionFeature 内）を作り、iOS `DSConnectingIndicator` の Canvas + `TimelineView(.animation)` レーダー風アニメを移植。色は macOS DesignSystem の `DSColor.chatAccent`、Reduce Motion 時は静的フォールバック、`accessibilityHidden(true)`。

## 棄却案

- **`SessionRestoreCoordinator` に表示制御を持たせる**: View が状態を観測すれば足り、Coordinator への配線を増やさない方が結合が小さい。採らない。
- **`default` で新 case を吸収する網羅 switch 前提の実装**: `ChatRestoreState` を網羅 switch する箇所はリポジトリ全体に存在せず、`default` 吸収の必要がない。新 case の握り潰しを避けるため明示遷移のみとした。
- **「どこかで indicator を出す」だけの literal 実装**: 復元完了後も残る／早すぎ／失敗時永久表示になる。表示を `.restoring && transcript 空` に厳密に紐付けた。

## 結果

- 白箱 `ChatConnectingLoadingWhiteboxTests`（3件）: `restore()` の状態遷移（入口 `.restoring`→完了 `.restored`／失敗 `.failed`）と表示条件（`.restoring` かつ transcript 空→表示真・`.restored`→偽）を fake client/store で決定論検証。`swift test --package-path macos/Packages/SessionFeature`（176）と `--package-path macos/Packages/DashboardFeature`（1374）全数 green（enum case 追加で網羅 switch が壊れない＝コンパイル通過が回帰ゲート）。
- 復元中の空白が接続アニメに置き換わり、描画待ちが可視化される。
- **未検証（フェーズ4/実機）**: 実機での復元体感は次段で確認する。
