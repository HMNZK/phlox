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

## 関連

- `macos/docs/adr/0114-inline-image-placeholder-and-numbering.md`
- iOS 側: `ios/docs/delivery/0013-inline-image-attachments-worklog.md`
