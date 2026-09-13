---
task: task-40
status: completed
---

## 詰まった点

- 前回のファイル全体 `strip_draw_attribute_modifiers` は、新規 `.font` を残余から消す目的では通るが、契約 12 の「font／padding 行の無条件削除」そのものなので、接続表の View／関数範囲へ移した。範囲外の `.font` は残余比較に残す。
- `TASK40_RB_BASELINE` は未設定・`HEAD`・ブランチ名を拒否し、承認済み修理コミットの短い SHA の blob と作業ツリーの rb を比較する。selftest の `evaluate_frozen_baseline` 直呼びだけでは本番欠落を拾えないため、一時 git リポジトリで rb を改変して `check_frozen_baseline` を通した。
- 検証用 SHA は `git stash` せず、detached worktree へ修理後 rb をコピーして commit し、その短い SHA で本番 GREEN を出した。worktree は `git worktree remove --force` で削除済み。

## できた風だが実は未完

- PM 目視ゲート A/B、App xcodebuild、`.claude/verify.sh` 全量は本手順の指定外。GUI は起動していない。
- 凍結テスト・契約・台帳は未改変。他担当の `tasks/frozen/staged/`、`DashboardFeature/Tests`、`SessionFeatureTests/Harness`、`docs/agent-output/visual-*` には触っていない。
- 検証 worktree の commit `941e0ee` は本番ブランチには載せていない。PM が修理後 rb を本ブランチへ commit し、その短い SHA を `TASK40_RB_BASELINE` に設定する必要がある。

## 置いた前提

- `TASK40_BASELINE` / `baseline_commit` は `bdbf1d9`。
- 描画修飾の strip／spacing マスクは接続表の View（および Markdown の `chatMarkdownTheme`）に限定する。`import DesignSystem` 行と `@AppStorage(ChatFontSettings.scaleKey)` 行は許可された追加としてファイル単位で除去する（font／padding の無条件削除ではない）。
- `AgentMessageCell` は接続表の「本文・補助間隔」（本文と時刻の `metadataGap`）のエージェント側呼び出し View として、同じ `:basic` case の範囲に含めた。ファイル全体マスクの再導入ではない。
- 料金 `opacity(0.7)`、差分意味色、エラー色 `statusError`、差分行間 0、親 VStack spacing 0、ブロックあたり gap 修飾 1 個は維持検査で固定する。
- 凍結 Swift 受け入れテストと `tasks/frozen/staged/` は未改変。テスト新規作成なし。

## 契約からの逸脱

なし。指摘 1・2 はハーネス欠陥として rb を修理し、製品コードは変更していない。

## レビュー重点

- ファイル全体から `.font`／`.padding`／`.foregroundStyle` を消していないか。範囲外（例: `ChatAttachmentBadge`）の `.font` 変更が残余 NG になるか。
- エラー色を primary にしても、gap padding を複製しても、マスクで消えずに専用検査で落ちるか。
- 本番経路が作業ツリーの rb を `TASK40_RB_BASELINE` blob と比較しているか。`rb_now: rb_blob` の自己比較に戻っていないか。
- 親 VStack spacing 0 とブロックあたり gap 修飾ちょうど 1 個が同時に保たれているか。

## rb 修理の内容

### 指摘 1

- `normalize_allowed_surface` 先頭のファイル全体 `strip_draw_attribute_modifiers` と `mask_typo_spacing` を削除した。
- 描画修飾の strip は接続表に対応する case／View 範囲（`mask_typography_draw_in_struct`）と `chatMarkdownTheme` に限定した。
- `check_protected_frozen_attrs` にエラー色（`statusError`）の維持を追加。差分意味色と料金 opacity 0.7 の維持は残した。
- `check_gap_application` に、ブロック ForEach 内の `.padding(.top, TranscriptTypography.gap)` がちょうど 1 個であること、親 VStack spacing 0（既存）を組み合わせた。
- 負例: エラー色→primary、gap padding 複製、範囲外（`ChatAttachmentBadge`）での `.font` 変更。

### 指摘 2

- `check_frozen_baseline` は作業ツリーの rb（`read_if_exist`）と `TASK40_RB_BASELINE` の blob を比較する。凍結 blob 同士の自己比較は止めた。
- 未設定・`HEAD`／`HEAD~`／`HEAD^`／`@`・ブランチ名は拒否する。
- selftest に、一時ディレクトリの git リポジトリで rb を改変し、本番関数 `check_frozen_baseline` が作業ツリーを読んで NG になる負例を追加した。

## 製品変更

なし。`TASK40_BASELINE=bdbf1d9` と修理後 rb の SHA で本番検査は製品側 NG なし。

## 検証原文

### `TASK40_RB_BASELINE=$(git rev-parse --short HEAD)`（作業ツリー改変の負例）

```
HEAD_SHA=5c6bade
task40-wiring: NG 基準時点の rb 自身が現在と同一ではない
```

exit 1。コマンド: `env TASK40_BASELINE=bdbf1d9 TASK40_RB_BASELINE=$(git rev-parse --short HEAD) ruby .claude/scripts/task40-wiring.rb`

### `TASK40_RB_BASELINE=HEAD`（文字列 HEAD 拒否）

```
task40-wiring: NG TASK40_RB_BASELINE に HEAD は使えない（短い SHA を渡す）
task40-wiring: NG 基準時点の rb 自身を git show できない（git show TASK40_RB_BASELINE:.claude/scripts/task40-wiring.rb）
```

exit 1。

### 本番 rb GREEN（worktree SHA `941e0ee`）

```
task40-wiring: OK
```

exit 0。コマンド: `env TASK40_BASELINE=bdbf1d9 TASK40_RB_BASELINE=941e0ee ruby .claude/scripts/task40-wiring.rb`

worktree は `git worktree add --detach /tmp/t40rb-wt HEAD` → 修理後 rb をコピーして commit → 検査後 `git worktree remove --force /tmp/t40rb-wt`。

### `t40-selftest`

```
t40-selftest: OK（要約未対応）
```

exit 0。コマンド: `~/.agents/scripts/compact-test t40-selftest ruby .claude/scripts/task40-wiring.rb --selftest`

生実行も `task40-wiring --selftest: OK`（exit 0）。

### DesignSystem `swift test`

```
✔ Test run with 158 tests in 30 suites passed after 0.086 seconds.
```

exit 0。コマンド: `(cd macos/Packages/DesignSystem && ~/.agents/scripts/compact-test t40-ds swift test)`

### SessionFeature `swift test`

```
✔ Test run with 902 tests in 113 suites passed after 1.224 seconds.
```

exit 0。コマンド: `(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-sf swift test)`

### `git diff --check`

出力なし、exit 0。

GUI は未起動。本ブランチへはコミットしていない。

=== REPORT COMPLETE ===
