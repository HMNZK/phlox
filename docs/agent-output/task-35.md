---
task: task-35
status: completed
---
## 詰まった / 完了できなかった点
- 実装役の範囲では PM 目視ゲート（隔離 Debug 起動、Dracula / GitHub Light の候補見本と適用後画面の撮影比較）を行っていない。ユーザー指示どおりアプリ起動はしていない。
- 入力欄の実画面比較は契約どおり未達のまま残る。配色テスト・他 3 要素の目視で代替合格にしていない。

## できた風だが実は未完（最重要）
- 凍結テスト・配線検査・App Debug ビルドは通過したが、見本の実寸・欠け・ホバー透け・候補ごとの固有配色はスクリーンショット未取得。数値は RGB 契約値であり測色値ではない。
- 用途名・テーマ名・選択チェックが通常の設定ウィンドウ幅（520pt）で欠けないことはレイアウト上の意図のみ。実ウィンドウでの欠落確認は未実施。
- VoiceOver 実音声は未検証。コード上は行の `accessibilityLabel` をテーマ名、選択時に `.isSelected`、見本と色帯を `accessibilityHidden` にしただけである。
- UI-06 全体の完了マーク条件（入力欄実画面比較）は本タスク実装では満たしていない。

## 置いた前提・仮定
- `AppTheme.sidebarSelectedOpacity` と `RGB.relativeLuminance` は同一モジュールの既存計算として再利用してよい（新しい輝度式は書いていない）。
- 見本寸法（アプリ見本幅 148、選択行高 18、入力欄高 20、色帯 9×22）は契約に数値が無いため DS トークンから仮置きした。未測定であり検証済みとしない。
- 見本の外枠色は model に無い新配色になるため付けていない。不透明下地は各 ZStack 先頭の `model.background` と外枠 `.background(model.background.color)` で担う。
- `ThemePreviewModel.make` は渡された候補だけを写し、`ThemeStore.active` / `UserDefaults` は参照しない。

## 契約からの逸脱
- なし。変更は `ThemePreviewModel.swift`（新規）、`SettingsView.swift`（ThemeRowView / ThemeAppPreview / ThemeSwatchStrip）、本レポートのみ。テスト・配線スクリプト・契約・台帳は未変更。

## App ビルド結果（xcodebuild 末尾）
```
RegisterWithLaunchServices /tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app (in target 'Phlox' from project 'Phlox')
    cd /Users/ryosuke/Projects/Phlox-oss-worktrees/ui-ux-improvement-backlog/macos
    /System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted /tmp/phlox-t13-visual.SPfR9c/Build/Build/Products/Debug/Phlox.app

note: Disabling hardened runtime with ad-hoc codesigning. (in target 'Phlox' from project 'Phlox')
note: Run script build phase 'Re-register Debug app with LaunchServices (Dock display name)' will be run during every build because the option to run the script phase "Based on dependency analysis" is unchecked. (in target 'Phlox' from project 'Phlox')
** BUILD SUCCEEDED **
```
ログ: `/tmp/phlox-t13-visual.SPfR9c/build-t35.log`。稼働中 Release Phlox には未接触。

Stop フック相当: `TASK35_BASELINE=094f86a ruby .claude/scripts/task35-wiring.rb` → `task35-wiring: OK`。`(cd macos/Packages/DesignSystem && swift test)` → exit 0（`task-35: theme preview model` を含む 143 tests / 28 suites）。`git diff --check` 空。

## レビュー重点（PM 用）
- `ThemeRowView` が候補 `theme` で `let model = ThemePreviewModel.make(theme: theme)` し、同一 `model` を `ThemeAppPreview` と `ThemeSwatchStrip` の両方へ渡しているか。
- 選択行・入力欄それぞれを含む ZStack の先頭が不透明な `model.background` で、Layer は `.rgb.color.opacity(.opacity)` か。色帯が `model.terminalSwatches` の順で、添字・reversed・shuffled が無いか。
- 見本内に `DSColor` / `ThemeStore.active` / 入力コントロールが混入していないか。テーマ名・チェック・他 Section の到達性が残っているか。
- 見本寸法は未測定。狭い幅での欠け、ホバー面の透け、選択前から各候補が固有色かは目視ゲートの対象。
- 入力欄の実画面比較が済むまで UI-06 を完了マークしないこと。
=== REPORT COMPLETE ===
