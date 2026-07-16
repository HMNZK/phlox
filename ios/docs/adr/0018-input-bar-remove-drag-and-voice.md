---
status: active
last-verified: 2026-07-16
---

# ADR 0018: 入力欄からドラッグ閉じバーと音声入力ボタンを撤去し、送信/停止を右スロットに常設する

> **このファイルの役割**: wave-7 で、コンパクトピル型入力欄（[ADR 0016](0016-input-bar-compact-pill-redesign.md)）から上部ドラッグ閉じバーとマイク（音声入力）ボタンを撤去し、右端スロットに送信ボタンを常設（実行中は停止）へ変更した決定を記録する。ADR 0016 を supersede せず**精緻化**する（ピル外形・中立枠・送信/停止同一スロットの核は不変）。
> **書かないもの**: 入力欄の現行の詳細構成（→ [architecture/overview.md](../architecture/overview.md)）。音声入力のクラッシュ堅牢化（→ [ADR 0015](0015-voice-input-crash-hardening.md)、本 wave で supersede しない）。

## 文脈

ADR 0016（wave-6）のピル型入力欄は、上部に控えめなドラッグ閉じバー（`dragDismissAffordance`、下スワイプでキーボードを閉じる、`providesDragToDismiss = true`）と、右端に丸マイクボタン（`voiceInputButton`、`providesVoiceInput = true`）を持ち、送信/停止アクションは `DSInputBarActionState.none`（テキスト空時は非表示）/`.send`/`.stop` の3状態で、**空文字時は右スロットに何も出さない**設計だった。

実機検証で「ドラッグバーは不要」「音声入力ボタンは不要」「音声ボタンを消した位置に送信ボタンを置き、停止もそこに出す」との要望が出た（wave-7 依頼）。

## 決定

- **ドラッグ閉じバーを撤去**: `dragDismissAffordance` とその `DragGesture`、ピル上端の `overlay(alignment: .top)`、`dismissInput()` を削除。契約フラグ `providesDragToDismiss = false`。アクセシビリティラベル「入力欄を閉じる」を持つ要素が消える。キーボードを閉じる操作はチャット面の `.scrollDismissesKeyboard(.interactively)` に委ねる（ADR 0016 と同方針）。
- **音声入力ボタンを撤去**: `voiceInputButton`・`@State voiceInputController`・音声ステータス表示・`onDisappear` 停止処理・`submit()`/`stop()` 内の音声停止呼び出しを削除。契約フラグ `providesVoiceInput = false`。ラベル「音声入力を開始/停止」が消える。
- **送信/停止を右スロットに常設**: `enum DSInputBarActionState` から `.none` を廃止し、`actionState(text:isLoading:isRunning:)` を「`isRunning → .stop` / それ以外 → `.send(isEnabled: canSubmit(text:isLoading:))`」に変更。`pillRow` は `[＋ | TextField | modelSelector | 送信/停止]`。空文字・送信不能時も送信ボタンは常設し、`.disabled(!canSubmit)` ＋ `opacity(0.45)` で無効・淡色表示する。
- **維持**: 画像添付（PhotosPicker・最大4・添付ストリップ）／送信 `onSubmit`／実行中 `onStop`／モデルセレクタ差し込みスロット（`providesInlineModelSelectorSlot = true`）／中立フォーカス枠。`SessionDetailView` は API 不変で無変更。
- **凍結オラクル**: 新契約を `Wave7InputBarContractTests`（PM 著・不変）で凍結。実装役編集可の `DSInputBarWave5Tests`（drag/voice フラグの主張を反転）・`DSInputBarWave6Tests`（空入力→`.send(isEnabled: false)`）を新契約へ整合（骨抜きではなく新デザインの反映）。

## 結果

- 入力欄右端に常に送信/停止ボタンが出るようになり、空文字時は無効・淡色の送信ボタンが placeholder 的に据わる。ドラッグバー・マイクは描画されない（`Wave5RegressionUITests.testInputBarAffordancesAfterCleanup` が実描画で裏取り）。
- **音声サブシステムの孤児化（受容したトレードオフ）**: 入力欄からマイクを外したことで、`DSVoiceInputController`（`DSVoiceInputController.swift`、ADR 0015 でクラッシュ堅牢化済み・約460行）と、`ios/project.yml`/`Info.plist` の `NSMicrophoneUsageDescription`・`NSSpeechRecognitionUsageDescription` が production から参照されなくなる。依頼は「ボタン削除」に限定されており、クラス・権限文言の撤去はスコープ外・surgical 逸脱になるため**撤去せず温存**した。ADR 0015 は supersede しない（クラスは残存・再配線可能）。将来これらを撤去するかは後続判断事項として残す。
- **未検証**: 常設送信ボタンのタップ領域・視覚バランスの実機体感は本 run では未確認（シミュレータの `swift test`＋iOS ビルド＋`Wave5RegressionUITests` 4/4 の実走まで）。

## 却下した代替案

- **音声サブシステムごと撤去する**: 依頼は「ボタン削除」であり、~460行のクラスと権限文言の撤去は要求のスコープを超える。孤児化を承知で温存し、判断を後続に残す方が可逆的。
- **空文字時は送信ボタンを非表示のまま残す（`.none` 維持）**: 依頼は「そこに送信ボタンを配置」で常設を要求。無効・淡色の常設が語意と一般的なチャット UI に合致。
