---
status: completed
last-verified: 2026-07-16
---

# 0005: モバイル UI 刷新 wave-7（入力欄整理・顔認証既定オフ）作業ログ

> **このファイルの役割**: この run（base = `task/mobile-chat-live`＝wave-5/6 統合ブランチ・未マージ、in-place 作業、wave-7 = 実機検証で出た入力欄・認証の追要望）で何をしたかの記録・状態スナップショット。
> **書かないもの**: 恒久仕様・現行構成（→ 生成した adr/architecture の各リンク先）。

## 依頼内容（wave-7・実機検証由来）

1. 入力欄のドラッグバーを削除。
2. 顔認証（起動時 Face ID ゲート）をデフォルトでオフにする。
3. 音声入力ボタンを削除し、削除した位置に送信ボタンを配置、停止ボタンもそこに出す。

1・3 を task-1（入力欄 `DSInputBar`）、2 を task-2（顔認証既定＝PM 直接）に分解した。file-disjoint（DesignSystemIOS ↔ Features）だが共有ワーキングツリーのため逐次実行した。

## 何をしたか（task-1・task-2）

- **task-1**（`DSInputBar.swift`／`DSInputBarWave5Tests.swift`／`DSInputBarWave6Tests.swift`・実装＝Cursor ヘッドレス）: 入力欄からドラッグ閉じバー（`dragDismissAffordance`/`dismissInput`）と音声入力ボタン（`voiceInputButton`/`voiceInputController` 参照/音声ステータス）を撤去。`DSInputBarActionState.none` を廃止し `actionState` を「`isRunning → .stop` / それ以外 → `.send(isEnabled: canSubmit)`」へ変更、右端スロットに送信/停止を常設（空文字時は無効・淡色）。契約フラグ `providesDragToDismiss = false` / `providesVoiceInput = false`。`SessionDetailView` は API 不変で無変更（→ [ADR 0018](../adr/0018-input-bar-remove-drag-and-voice.md)）。
  - **孤児化の受容**: マイク撤去で `DSVoiceInputController`（~460行、ADR 0015 でクラッシュ堅牢化済み）と mic/speech 権限（`project.yml`/`Info.plist`）が production 未参照になる。依頼は「ボタン削除」でありサブシステム/権限撤去はスコープ外・surgical のため温存。後続判断事項として残す。
- **task-2**（`AppSettingsStore.swift`／`AppSettingsStoreTests.swift`・PM 直接）: `UserDefaultsAppSettingsStore.faceIDEnabled` の未設定フォールバックを `true`→`false` に変更（新規インストール時にロックしない）。setter・永続化・通知/外観の既定・`AppModel.initialAuthState`/`shouldRelock`（明示引数）は不変（→ [ADR 0017](../adr/0017-face-id-launch-gate-default-off.md)）。凍結 `SettingsAcceptanceTests` は要件変更として PM が新既定へ再著。
- **PM（テスト整合）**: 凍結受け入れ `Wave7InputBarContractTests.swift` を新規著（入力欄新契約の不変オラクル）。XCUITest `Wave5RegressionUITests` を整合（ドラッグ/音声アフォーダンスの描画検証を「廃止確認＋常設送信ボタン確認」の `testInputBarAffordancesAfterCleanup` へ置換、`testDragHandleDismissesKeyboard` を削除）。

## 生成・更新した永続ドキュメント

- [ios/docs/adr/0017-face-id-launch-gate-default-off.md](../adr/0017-face-id-launch-gate-default-off.md)（起動時 Face ID ゲートを既定オフにする決定）
- [ios/docs/adr/0018-input-bar-remove-drag-and-voice.md](../adr/0018-input-bar-remove-drag-and-voice.md)（入力欄からドラッグ閉じバー・音声入力ボタンを撤去し送信/停止を右スロットに常設する決定。ADR 0016 を精緻化・0015 を supersede せず）
- [ios/docs/architecture/overview.md](../architecture/overview.md)（`DSInputBar` のドラッグ/音声撤去・送信/停止常設スロット、Face ID 既定オフを反映）
- [ios/docs/adr/README.md](../adr/README.md)・[ios/docs/delivery/README.md](README.md)（索引追記）

## 検証結果（run 内で実施）

- 凍結オラクルの red-for-the-right-reason を確認後に凍結。`Wave7InputBarContractTests` と再著 `SettingsAcceptanceTests` は未実装ゆえのアサーション失敗のみ（Build complete＝ハーネス欠陥なし）。
- task-1: 権威ゲート `agentic-loop-verify-task.sh task-1` = `pass:true, tests:pass, scope:gate, out_of_scope:[], report:completed`。ステージ1 persona-reviewer = pass（自走 `swift test` 361 passed、凍結 Wave7=7・SettingsAcceptance=9 green、MUST/HIGH 0、誠実性問題なし）。
- task-2: PM 自走 `swift test`（Settings 関連 13 passed）で green 確認。
- 独立性: task-1 実装＝Cursor（ヘッドレス）×レビュー＝Claude（persona-reviewer）のクロスツール。
- **統合検証 = pass**: `.claude/verify.sh` 実走で `verify: OK`（PhloxKit 361・macOS 134 passed・iOS シミュレータビルド成功）。`Wave5RegressionUITests` を iOS シミュレータで実走し 4/4 pass（`testInputBarAffordancesAfterCleanup` 含む）。
- task-1・task-2 を `done` に確定。

## 積み残し・後続判断事項

- **音声サブシステムの撤去要否**: `DSVoiceInputController`（~460行）と mic/speech 権限文言が孤児化。App Store 審査で未使用権限が問われうるが、開発用途では非ブロッキング。撤去 or 意図的保持はユーザー判断。
- **実機体感は未検証**: 常設送信ボタンのタップ領域・視覚バランス、顔認証既定オフの起動挙動（設定 ON/OFF の切替）は次回実機検証で裏取り。
- `InMemoryAppSettingsStore` の既定 `faceIDEnabled = true`（テストダブル）は production の false と乖離（既存テストは明示上書きで無害・LOW）。
- wave-5/6 の積み残し（ライブアクティビティのロック画面実配信等）は本 run のスコープ外で継続。dev への統合マージは未実施（ユーザー明示承認待ち。wave-5/6/7 すべて `task/mobile-chat-live` 上）。
