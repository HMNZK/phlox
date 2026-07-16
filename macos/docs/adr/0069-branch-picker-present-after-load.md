---
status: active
last-verified: 2026-07-10
---

# 0069. ブランチ picker は present-after-load 状態機械で提示し、提示中の popover 内容変更を構造的に禁止する

## 状態

active

## 文脈

composer のブランチ chip をクリックすると非決定的にアプリが SIGSEGV（exit 139・クラッシュレポート生成なし）で落ちた。lldb 実測のスタックで真因を特定:

- 旧実装は popover を「Loading branches...」表示で先に開き、`localBranches` 完了後に一覧へ差し替えていた。
- この内容サイズ変化が SwiftUI の `PopoverHostingView.updateAnimatedWindowSize` → `NSPopover _setContentView:size:canAnimate:` → `NSMoveHelper _doAnimation`（ネストランループ）を **`NSHostingView.windowDidLayout` の最中**に走らせ、AppKit の表示サイクル（`UpdateCycle UC::DriverCore::continueProcessing()`）が再入して NULL ジャンプ（EXC_BAD_ACCESS 0x0）で落ちる。
- タイミング依存のため単体テスト・静的検査では検出できず、ReportCrash の重複抑制により .ips も残らない（→ 検証は exit status 直取りで行う。lessons L-41）。

30秒周期の `TimelineView` による `refreshCurrentBranch()` も、提示中に `currentBranch` を変えると checkmark 行構成が変わり同じリサイズ再入を誘発しうる（stage-2 レビューが指摘した残穴）。

## 決定

「**popover は最終内容が確定してから提示し、提示中に内容（行構成・サイズ）を変えるコードパスを持たない**」を不変条件とし、提示状態機械 `ComposerBranchPickerModel`（`SessionFeature`・純粋な値型）で構造的に強制する:

- `idle → beginOpen() → loading → finishLoading(.success) → presented`。**読み込み完了までは提示しない**（Loading 表示の popover を出さない）。
- `presented` 中に届いた読み込み結果は無視（提示中の一覧差し替え禁止）。
- 選択は `select(branch:)` で**先に閉じてから** checkout の Task を開始。checkout 後の再読込は撤去（次回 beginOpen で読む）。
- `allowsExternalRefresh`（`phase == .idle` のみ true）で、外部起因の `refreshCurrentBranch()`（30秒周期・workspacePath 変更）を提示中・読み込み中は延期。閉じた直後（dismiss 経路）に1回だけ再読込してラベルを追随させる。

凍結受け入れテスト 8 件（`AcceptanceBranchPickerPresentationTests`）がこの契約を符号化している。

## 棄却した代替案

- **Loading 表示を維持したまま popover のアニメーションリサイズだけ抑止**: `NSPopover` の内部（`_setContentView:size:canAnimate:`）に依存する回避で、SwiftUI 側から確実に制御する公開 API がない。OS 更新で壊れる。
- **提示中の再読込に debounce/遅延を挟む**: タイミング窓を狭めるだけで再入条件は残る（対症療法）。

## 結果

- 実機 Debug で picker 開閉 25 サイクル（外側クリック dismiss 15＋Escape 10）を連打してクラッシュなし・CPU 0〜1.3% 収束・dismiss 後のラベル追随を確認（2026-07-10）。
- 提示中は branch 一覧・checkmark が更新されない（構造上の制約）。鮮度より安定を優先し、更新は次回オープン時に反映される。
- 一般則: **NSPopover / NSHostingView 併用時、提示中の SwiftUI 状態変更によるコンテンツサイズ変化は表示サイクル再入クラッシュの火種**。同種の popover を追加する際は present-after-load と提示中 freeze を踏襲すること。
