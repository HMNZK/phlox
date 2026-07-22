---
status: completed
last-verified: 2026-07-22
---

# 0013 添付画像の番号付けと本文への `[Image #N]` 埋め込み（iOS・iOS 18 化）

## この run で何をしたか

- **最低対応を iOS 18.0 へ引き上げ**（`Package.swift` / `project.yml`）。iOS 18 の
  `TextField(text:selection:prompt:axis:label:)` と `SwiftUI.TextSelection` を使うため。`UITextView` 化はしていない。
  `.macOS(.v14)` は `swift test` をホストで走らせるため維持。
- **`SessionDetailViewModel`**: `SessionAttachmentItem` に `number` を追加。`inputCursorUTF16` を公開し、
  `addAttachments` が上限判定を全て通過したあとに採番＋本文へプレースホルダ挿入、`removeAttachment` が
  該当プレースホルダだけを本文から除去する。弾かれたバッチは番号も本文も汚さない。
- **`DSInputBar`**: `cursorUTF16: Binding<Int>` を追加し、iOS では `TextSelection` と非対称に同期。
  `DSAttachmentStripItem` に `number` を追加し、サムネイル左上に `#N` バッジを表示。
  既存の静的契約フラグと見た目（pill・4行上限・フォーカス枠）は不変。`providesCursorAwareInput` を追加。

## 途中で潰した不具合（いずれも自動テストでは検出できなかった）

1. **起動直後の SIGTRAP**: `String.Index.utf16Offset(in:)` に別世代の文字列の index を渡していた
   （`onChange(of: textSelection)` / `(of: text)` / `(of: cursorUTF16)` の三方が相互更新して世代がずれる）。
   → 非対称同期に組み替え、`text` 変化だけでは選択を押し戻さないようにした。
2. **プレースホルダが常に本文の先頭へ入る**: 妥当性判定に `text.indices.contains(index)` を使っていたが、
   `String.indices` は `endIndex` を含まない。キャレットが本文末尾（最も普通の状態）だと常に弾かれ、
   `cursorUTF16` が 0 のままだった。
   → `DSInputCursorMath.utf16Offset(of:in:)`（`#if os(iOS)` の外の純関数）へ切り出し、`endIndex` を受理。
   受け入れテストに `endIndex` ケースを凍結した。

## 状態

完了。

## 検証

- `swift test --package-path ios/Packages/PhloxKit` — 471 件 pass
- iOS シミュレータ（iPhone 17 Pro / iOS 26.2）向け Debug ビルド — 成功
- **シミュレータでの実操作確認**: セッション詳細で `abc` を入力 → 「+」→ 写真を選択 →
  本文が `abc [Image #1] ` になり、サムネイルに `#1` バッジが出ることを目視確認。
  複数枚選択で `[Image #1] [Image #2]` と連番になることも確認。クラッシュ・フリーズなし。

## 関連

- `ios/docs/adr/0025-ios18-textselection-for-cursor-aware-input.md`
- 表記・採番の決定: `macos/docs/adr/0114-inline-image-placeholder-and-numbering.md`
- macOS 側: `macos/docs/delivery/0014-inline-image-attachments-worklog.md`
