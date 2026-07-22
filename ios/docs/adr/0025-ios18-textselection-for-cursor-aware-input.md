---
status: accepted
last-verified: 2026-07-22
---

# ADR 0025: 最低対応を iOS 18.0 へ引き上げ、`TextField(selection:)` でカーソル位置を扱う

## 文脈

添付画像を本文のカーソル位置へ `[Image #N]` として挿入する機能（`macos/docs/adr/0114`）を iOS にも入れるにあたり、
入力欄のカーソル位置を取得する手段が要る。当時の最低対応は **iOS 17.0** で、`DSInputBar` の入力欄は
SwiftUI の `TextField(text:axis:)` だった。iOS 17 の SwiftUI にはカーソル位置を読む API が無い。

取り得た選択肢:

- **A. 末尾追記で妥協**: カーソルを扱わず、常に本文末尾へ挿入する。安全だが要件を満たさない。
- **B. `UIViewRepresentable`(`UITextView`) へ作り替え**: カーソルは扱えるが、高さ制御（1〜4行）・プレースホルダ・
  フォーカス・IME を自前で作り直すことになる。しかも `swift test` は macOS ホストで走るため
  `#if os(iOS)` 配下は自動テストで一切守れない。アプリで最も使う部品を、テストの効かない状態で全面的に作り直すことになる。
- **C. 最低対応を iOS 18.0 へ引き上げる**: iOS 18 の `TextField(text:selection:prompt:axis:label:)` と
  `SwiftUI.TextSelection` を使う。**既存の `TextField` に `selection:` を足すだけ**で済む。

## 決定

**C を採用**し、最低対応を iOS 18.0 に引き上げた（利用者の合意済み）。

- `ios/Packages/PhloxKit/Package.swift` の `platforms` を `.iOS(.v18)` に。`.macOS(.v14)` は維持する
  （`swift test` を macOS ホストで走らせるため）。
- `ios/project.yml` の `IPHONEOS_DEPLOYMENT_TARGET` と各ターゲットの `deploymentTarget` を `18.0` に。
  `PhloxMobile.xcodeproj` は xcodegen が `project.yml` から生成する（リポジトリでは追跡していない）。
- `DSInputBar` は `cursorUTF16: Binding<Int>` を受け取り、iOS では `TextSelection` と非対称に同期する:
  - ユーザー操作由来の選択変化 → `cursorUTF16` へ一方向に反映
  - 外部（ViewModel）が `cursorUTF16` を変えたときだけ選択位置を押し戻す
  - `text` の変化だけを理由に選択を押し戻さない
  macOS ホストビルドでは `#if os(iOS)` で従来の `TextField(text:axis:)` にフォールバックする。
- 番号採番・プレースホルダの挿入／削除は `SessionDetailViewModel`（プラットフォーム非依存）に置き、View 層は
  カーソル位置の受け渡しだけに保つ。テストで守れる面積を最大化するため。

## 結果・学び

- `UITextView` 化を回避でき、`DSInputBar` の見た目・高さ制御・フォーカス・既存の静的契約フラグはそのまま維持できた。
- iOS 17 の端末はサポート外になった。
- **`#if os(iOS)` 配下は自動テストで守れない**という制約が2件の実バグを生み、いずれもシミュレータでの手動確認でしか
  検出できなかった。同種の作業では実機確認を完了条件に含めること:
  1. `String.Index.utf16Offset(in:)` に別世代の文字列の index を渡して起動直後に SIGTRAP（`onChange` の相互更新で
     選択とテキストの世代がずれた）。
  2. 妥当性判定に `text.indices.contains(index)` を使ったため、**キャレットが本文末尾**（= `endIndex`。最も普通の状態）
     だと常に弾かれ、カーソル位置が外部へ伝わらず添付が常に本文の先頭へ入った。
  対策として、オフセット計算は `DSInputCursorMath`（`#if os(iOS)` の外の純関数）へ切り出し、`endIndex` を有効位置として
  受理することを受け入れテストで凍結した。

## 関連

- 表記・採番の決定は `macos/docs/adr/0114-inline-image-placeholder-and-numbering.md`
- 実装: `ios/Packages/PhloxKit/Sources/DesignSystemIOS/Molecules/DSInputBar.swift`、
  `ios/Packages/PhloxKit/Sources/Features/SessionDetail/SessionDetailViewModel.swift`
- 作業ログ: `ios/docs/delivery/0013-inline-image-attachments-worklog.md`
