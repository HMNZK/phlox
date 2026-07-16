---
status: active
last-verified: 2026-07-16
---

# ADR 0016: チャット入力欄をカード型からコンパクトなピル型へ再デザインし、送信/停止を同一スロットに統合する

> **このファイルの役割**: wave-6（task-1）で、wave-5 で導入したカード型入力欄（角丸コンテナ＋上部ドラッグハンドル＋フォーカス時オレンジ枠＋別置き停止ボタン）を、実機検証のフィードバックを受けてコンパクトなピル型（左に丸＋ボタン・中央プレースホルダ・右に丸マイク、実行中は送信と同じスロットに停止ボタン）へ再デザインした決定を記録する。
> **書かないもの**: 音声入力のクラッシュ対処（→ [ADR 0015](0015-voice-input-crash-hardening.md)）。branch 表示のスコープ（→ [ADR 0012](0012-input-bar-branch-display-only.md)、本 wave でも無変更）。入力欄の現行の詳細構成（→ [architecture/overview.md](../architecture/overview.md)）。
>
> **後続の変更（wave-7）**: 本 ADR のドラッグ閉じバー（`providesDragToDismiss = true`）とマイクボタン（`providesVoiceInput = true`）、および `.none`＝空文字時非表示は wave-7 で撤回された（両フラグ false・送信/停止を右スロット常設）→ [ADR 0018](0018-input-bar-remove-drag-and-voice.md)。ピル外形・中立枠・送信/停止同一スロットの核は本 ADR のまま有効。

## 文脈

wave-5 task-1 は入力欄をカード型（角丸コンテナ、上部ドラッグハンドルで下スワイプ閉じ、フォーカス時に `DSColor.accent` で強調するオレンジ系の枠、送信ボタン）に刷新した。停止ボタンは `DSInputBar` の外側で `SessionDetailView` が別に配置していた（`HStack` に `DSInputBar` と `stopButton` を並置）。wave-5 のカード型入力欄そのものを記録した専用 ADR は無く（ADR 0012 は branch 表示のみを対象とし、chrome の詳細は明示的にスコープ外としている）、視覚仕様は `architecture/overview.md` にのみ記述されていた。

wave-5 の実機検証で6件の追修正が必要と判明し、wave-6 のゲート①でユーザーが初期表示案として Image#6（コンパクトなピル型: 左＋・中央プレースホルダ・右マイク）を明示選択、配色は「オレンジ枠廃止＋落ち着いた微調整」と決定した（decision-log wave-6 フェーズ0/1）。

## 決定

- **外形をカードからピルへ**: `DSInputBar` のコンテナ形状を `RoundedRectangle`（`cardShape`）から `Capsule()` へ変更し、静的契約フラグを `providesCardChrome = false` / `providesPillChrome = true` に更新した（`DSInputBarWave6Tests.inputBarPublishesCompactNeutralPillContract` で凍結）。
- **1行レイアウトへの統合**: 写真添付ボタン・プレースホルダ付きテキストフィールド・モデルセレクタスロット・マイクボタン・送信/停止アクションボタンを、`pillRow` という単一の `HStack` に横並びにした。旧来は「ドラッグハンドル／selectorRow（モデルセレクタ＋branch）／テキストフィールド／ボタン行」の縦積みだった。
- **送信⇄停止を同一スロットへ統合**: `DSInputBarActionState`（`.none` / `.send(isEnabled:)` / `.stop`）を新設し、`DSInputBar.actionState(text:isLoading:isRunning:)` が「実行中なら常に `.stop`」「テキストが空なら `.none`」「それ以外は `.send`」の優先順位で状態を決める。`actionButton` がこの状態に応じて送信ボタンと停止ボタンを排他的に描画する。`SessionDetailView` 側の別置き `stopButton`（`DSInputBar` の外に配置していた実装）を廃止し、`SessionDetailView` は `isRunning: viewModel.currentStatus == .running && viewModel.canInterrupt` と `onStop` クロージャを `DSInputBar` に渡すだけになった。
- **フォーカス枠の中立化**: フォーカス時に `DSColor.accent` で強調していた `cardBorderColor` を廃止し、フォーカス有無に関わらず `DSColor.campCardBorder` 固定の `pillBorderColor` にした（`usesNeutralFocusBorder = true` / `usesAccentFocusBorder = false` の契約フラグで表明）。送信ボタンのグロー演出（`dsShadow(canSubmit ? DSShadow.fabGlow : ...)`）も削除し、`DSColor.accent` 単色背景に簡素化した。
- **ドラッグ閉じの温存・縮小**: 上部ドラッグハンドルは `dragDismissAffordance` としてピル上端に `overlay(alignment: .top)` で残し、視覚をより控えめな細いバー（幅24pt・高さ2pt、旧は幅38pt・高さ5pt）に縮小した。`providesDragToDismiss = true` の契約は不変。
- **モデルセレクタスロットは維持しつつ条件表示**: `providesInlineModelSelectorSlot = true` は不変（`pillRow` 内に配置）。`SessionDetailView` 側で `showsModelSelectorChip` が真の時だけ中身を返し、既定は `EmptyView()`。安静時（モデルチップ非表示時）は空スロットとしてピルのレイアウトに影響しない。
- **凍結テストとの衝突是正（PM の契約指示ミス）**: 初回実装で `providesInlineModelSelectorSlot = false` にしたところ、allowed_paths 外の凍結テスト（`Task3AcceptanceTests`／`Task3KeyboardDismissTests`）およびプレースホルダ契約（`SessionDetailCopy.inputPlaceholder = "回答を入力…"`）と衝突した。凍結テストは不変のまま、スロットを `= true` へ復元し、プレースホルダは既存契約文言を維持することで是正した（decision-log wave-6 フェーズ2/3/4）。

## 結果

- 入力欄の視覚がカード型からコンパクトなピル型へ変わり、実行中は送信ボタンと同じ位置に停止ボタンが表示される（別置きの停止ボタンは廃止）。
- フォーカス時の枠色変化が無くなり、フォーカス切替による強調のちらつきが減った。
- `DSInputBarWave5Tests` は `providesCardChrome` の主張を `!providesCardChrome` へ反転しつつ、`providesDragToDismiss`／`providesVoiceInput`／`usesFocusState`／`providesInlineModelSelectorSlot` という wave-5 由来の契約は維持されることを確認する形に更新された（`inputBarPreservesWave5InteractionsWithoutLegacyCardChrome`）。新規 `DSInputBarWave6Tests` がアクション状態遷移とピル/中立枠契約を凍結する。
- **未検証**: ピル型 UI の実機体感（タップ領域の実感・視覚バランス）は本 run では確認できていない（統合検証はシミュレータビルド＋wave-5 XCUITest の再実走まで）。

## 却下した代替案

- **カード型の外形を保ったまま停止ボタンだけをスロット化する**: ユーザーがゲート①で Image#6（ピル型）を明示選択しており、外形自体の変更が要求のスコープ内だった。
- **送信ボタンと停止ボタンを別々の固定スロットとして両方常時表示する**: 実行中は送信操作がそもそも無効なため、同一スロットでの排他表示（`DSInputBarActionState`）の方が誤タップの余地が少ないと判断した。
- **wave-5 のカード型入力欄を記録した既存 ADR を supersede する**: 探索の結果、カード型 chrome を対象とした専用 ADR は存在しなかった（ADR 0012 は branch 表示のみが対象でカード chrome を明示的にスコープ外としている）。supersede 対象が無いため、本 ADR は新規決定として起こした。
