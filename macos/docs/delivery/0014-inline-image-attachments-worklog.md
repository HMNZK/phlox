---
status: completed
last-verified: 2026-07-22
---

# 0014 添付画像の番号付けと本文への `[Image #N]` 埋め込み（macOS）

## この run で何をしたか

Claude Code CLI と同じく、画像を添付すると本文のカーソル位置へ `[Image #N]` を挿入し、添付チップに同じ番号を表示するようにした。

- **共有面（`AgentDomain`）**: `ComposerImagePlaceholder` を新設。`text(for:)` / `nextNumber(after:)` /
  `inserting(number:into:cursorUTF16:)` / `removing(number:from:)` の4純関数で、表記・採番・挿入・削除の規則を1箇所に決めた。
  macOS と iOS が path 依存でこれを共有する。
- **`ComposerAttachments.swift`**: `ComposerAttachment` に `number` を追加。`addImage` を
  `@discardableResult -> ComposerAttachment?` にして、受理したときだけ採番済みの添付を返すようにした（上限判定の文言・閾値は不変）。
  チップ表示用の純関数 `ComposerAttachmentChipPresentation`（`badge` / `title`）を追加。
- **`ChatComposer.swift`**: `SubmitAwareTextView` に `onPasteImageOutcome`（`unsupported` / `rejected` / `attached(number:)`）を
  **追加**し、`attached` のときだけカーソル位置へプレースホルダを挿入する。既存の `onPasteImage` と `handlePaste(from:) -> Bool` の
  シグネチャは凍結済みのため変更せず、`onPasteImageOutcome` が nil なら従来経路にフォールバックする。
  IME 変換中は `unmarkText()` で確定してから挿入する。
- **`GridChatColumn.swift`**: 同じペースト経路の複製にも同じ配線を入れた（片方だけ直さない）。
- **`ComposerSettingsControls.swift`**: 「+」ボタン経路は本文末尾へ挿入（この経路はカーソルを取得できない）。
- **添付チップの削除**: `ComposerAttachmentStrip` に `onRemove` を足し、呼び出し側で `store.remove` と
  本文からのプレースホルダ除去を行う。

## 状態

完了。macOS 側の未検証点は「実アプリでの目視確認」のみ（画像添付は Claude セッションでしか有効にならないため）。
受け入れテストは実 `NSPasteboard` → 実 `NSTextView` の経路で挿入結果とキャレット位置まで検査している。

## 検証

- `swift test --package-path macos/Packages/AgentDomain` — 198 件 pass（うち受け入れ 23 件）
- `swift test --package-path macos/Packages/SessionFeature` — 303 件 pass
- `swift test --package-path macos/Packages/DashboardFeature --no-parallel` — 1418 件 pass（うち本 run の受け入れ 44 件）
- `swift build --package-path macos/Packages/SessionFeature` — 成功
- macOS アプリの Debug ビルド（xcodebuild）— 成功

## 追補: 実機確認後の追加要望（task-4〜7）

実アプリで触ったユーザーから3つ要望が来たので同じ run で続けた。

### task-4: 本文からプレースホルダを消したら添付も外す（双方向化）

当初は「添付を消したら本文からも消える」片方向だけだった。本文の `[Image #1]` を消しても画像が残るのは
直感に反するため双方向にした。判定は `numbersRemoved(from:to:among:)` で、**oldText に無かった番号は決して
返さない**のが安全弁（Control API 経由で積まれた画像や、挿入した直後の添付を誤って外さない）。

macOS 固有の落とし穴: 送信は本文を空にするが、送信ペイロード（`buildChatInputs`）は**ライブの
`attachmentStore` を読む**。素直に `.onChange(of: text)` を書くと、送信で本文が空になった瞬間に添付が外れ、
画像が送られない／`turnStart` 失敗時に添付が残らない。`ChatSessionViewModel.syncAttachmentsWithDraftEdit` が
クリア直前の本文を覚えて読み飛ばす。iOS は送信前に `backupItems` を控える設計なのでこの防護は不要。

### task-5 / task-6: トークン単位の削除と、コピーで画像も載せる

- macOS は `deleteBackward` / `deleteForward` を override してトークン全体（＋隣接スペース1つ）を一度に消す。
  チップの × 経路（`removing`）と同じ本文になることをテストで縛っている。
- iOS は SwiftUI の `TextField` で打鍵を横取りできないため、**1文字消えた直後に残骸をまとめて取り除く**
  後追い修復（`repairingBrokenPlaceholder`）。共通接頭・接尾から編集範囲を推定するので、消した文字列が
  周囲と似ていると推定が外れる。無傷で残っている他のプレースホルダを壊す結果になったら修復を諦める
  （`preserving:`）のが安全弁。
- コピーは1つ目の pasteboard item にテキストと画像を両方載せる。自分でコピーしたものを composer へ
  貼り戻すときは画像として横取りしない（横取りすると選択していた本文が丸ごと捨てられる）。
  iOS はコピーを横取りできないため非対応。

### task-7: 選択もトークン単位にする

設計を2度作り直した。詳細と「なぜその方式か」は ADR 0114 の決定7 に記録した。要点だけ:

- `setSelectedRange` で選択を書き換えると AppKit の選択の起点が壊れ、shift+← で伸ばした選択を
  shift+→ で戻せなくなる。
- コマンドを個別に override する方式は覆うべき集合が閉じない（キャレットがトークン内側・shift+↑↓・
  マウスドラッグで穴が出た）。
- 採用したのは `NSTextViewDelegate.textView(_:willChangeSelectionFromCharacterRange:toCharacterRange:)`
  の1箇所で守る方式。

1文字打つたびに走る経路なので実測した。50k字・添付5枚で **17.2 ms → 1.05 ms**（本文を1回だけ走査する形へ
変更）。添付が無ければ本文を読まない。

### 独立レビューで見つかった実バグ（すべて実装時に持ち込んだもの）

1. macOS の送信でペイロードから画像が落ちる／失敗時に添付が残らない（task-4）
2. iOS で1つ目のトークンを範囲選択で消すと隣のトークンが壊れる（task-5）
3. コピーしたものを貼り戻すと選択していた本文が丸ごと消える（task-6）
4. キャレットがトークン内側にあると選択が分断され、shift+→ で起点を飛び越える（task-7）
5. マウスのドラッグ・ダブルクリックだけ吸着が効いていない（task-7）
6. 19桁以上の数字列を含む本文で計算があふれてクラッシュ（task-7 の性能改善で混入）

いずれも自動テストと自分の目視では取り切れず、独立レビューの敵対的検証で出た。

## 検証（追補分）

- `swift test --package-path macos/Packages/AgentDomain` — 231 件 pass
- `swift test --package-path macos/Packages/DashboardFeature --no-parallel` — 1454 件 pass
- `swift test`（`ios/Packages/PhloxKit`） — swift-testing 481 件 + XCTest 430 件 pass
- macOS Debug ビルドを Release 版と共存起動し、ユーザーが実アプリで挙動を確認済み
- **未検証**: iOS 実機での task-4〜5 の挙動（端末がオフラインのため未実施）

## 関連

- `macos/docs/adr/0114-inline-image-placeholder-and-numbering.md`
- iOS 側: `ios/docs/delivery/0013-inline-image-attachments-worklog.md`
