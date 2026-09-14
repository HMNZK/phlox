---
status: completed
task: 47
---

# task-47 ハーネス修理レポート

## 変更点

- `PMTranscriptVisualTask47Tests.swift` に、窓表示時だけ読む `PHLOX_PM_VISUAL_WIDTH`、`PHLOX_PM_VISUAL_SCALE`、`PHLOX_PM_VISUAL_THEME` を追加した。
- 幅・倍率は既存の `applyWidth(_:)` / `applyScale(_:)` を使い、既存の受け入れアサーション通過後、`makeKeyAndOrderFront(nil)` の直前に適用するようにした。`hostView.frame`、`nsWindow.setContentSize(...)`、レイアウト、メインループ反映も行う。
- テーマ指定時は `AppTheme.phloxLight.id` / `AppTheme.phlox.id` を専用 suite と `UserDefaults.standard` に設定し、`NSAppearance` もホストと窓へ設定する。標準 UserDefaults の元値は `finishVisual` で復元し、未設定なら削除する。窓非表示時はテーマ処理と復元を行わない。
- 許容外の幅・倍率・テーマは `#expect` で実値を含むメッセージを出す。
- 製品コード、凍結テスト、コミットは変更していない。

## 実走した検証

1. コマンド:

   `~/.agents/scripts/compact-test t47-harness-default bash -c 'cd /tmp/ui-ux-wt-47/macos/Packages/SessionFeature && swift test --no-parallel --filter PMTranscriptVisualTask47Tests'`

   結果原文の要点:

   `✔ Test run with 1 test in 1 suite passed after 1.472 seconds.`

2. コマンド:

   `~/.agents/scripts/compact-test t47-harness-no-window-env env -u PHLOX_PM_VISUAL_TASK PHLOX_PM_VISUAL_WIDTH=360 PHLOX_PM_VISUAL_SCALE=2.0 PHLOX_PM_VISUAL_THEME=dark bash -c 'cd /tmp/ui-ux-wt-47/macos/Packages/SessionFeature && swift test --no-parallel --filter PMTranscriptVisualTask47Tests'`

   結果原文の要点:

   `✔ Test run with 1 test in 1 suite passed after 1.300 seconds.`

3. `PHLOX_PM_VISUAL_WIDTH=500` + `PHLOX_PM_VISUAL_TASK=47` は窓を開くため実走していない。コード上は、窓表示時に `applyWindowLaunchEnvironment` が `"500"` を許容値辞書で不一致とし、`#expect(parsed != nil, "PHLOX_PM_VISUAL_WIDTH は 360|720、実際は 500")` を記録する。

## plist md5

- 変更前: `51a4354558727f023b062c7246ce19db`
- 変更後: `51a4354558727f023b062c7246ce19db`

前後一致。Release Phlox のプロセスや plist は操作していない。

## 差分統計

`git -C /tmp/ui-ux-wt-47 diff --stat`:

```text
 .../Acceptance/PMTranscriptVisualTask47Tests.swift | 108 ++++++++++++++++++++-
 1 file changed, 103 insertions(+), 5 deletions(-)
```

## 未検証項目

- `PHLOX_PM_VISUAL_TASK=47` での窓表示、12 組（幅 360／720 × 倍率 0.8／1.0／2.0 × 明暗テーマ）の実撮影。
- `PHLOX_PM_VISUAL_WIDTH=500` の窓あり実走。

=== REPORT COMPLETE ===
