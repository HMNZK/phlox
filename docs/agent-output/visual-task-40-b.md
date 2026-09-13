---
task: task-40
status: partial
gate: B
commit: 5c6bade18b76ef26accecf42e638fb984756d407
branch: feature/ui-ux-improvement-backlog
harness: macos/Packages/SessionFeature/Tests/SessionFeatureTests/Harness/TranscriptTypographyRenderHarness.swift
png_dir: /tmp/phlox-t13-visual.SPfR9c/t40-gateB/
---

# task-40 PM目視ゲート B（SessionFeature fixture）

合否は PM が PNG を見て判定する。本ファイルはハーネス作成・実行の記録であり、読順・欠け・重なりの合格を宣言しない。

## fixture の構成

実 `ChatTranscriptView` に `transcript:` で固定 ChatItem を渡した。ViewModel は `DisconnectedHarnessClient`（`events` 即 finish、start/turnStart/resume/interrupt/close は no-op）。`startNew` は呼ばない。課金セッションは作っていない。

ホスト引数は製品 `ChatSessionView.mainColumn(width:)` と同じく `contentMaxWidth: ComposerLayout.transcriptContentMaxWidth(mainColumnWidth:)` と `bottomScrollContentMargin:`（実測した `ChatComposer` 高。360/720 とも 118pt）。

並び（8/16/24 境界を同時に置く）:

1. ユーザー u1
2. 回答 a1: 日本語長文2段落、H1〜H6、長い節見出し、長い箇条書き・番号付き・入れ子、インラインコード、表、Swift フェンス、長いコード行
3. 回答 a2: 分割出力（answer→answer の 8pt）
4. 連続コマンド 2 件（複数行 `git log` + 25行出力）。既定折りたたみ
5. Reasoning（グループ区切り）
6. 別コマンド 1 件（`rg`）
7. Reasoning（空出力グループを独立させる区切り）
8. 空出力コマンド 2 件（grouping 上は 1 グループ。`CommandGroupHeader.shouldRender=false` のためカードは出ない）
9. 差分（既定折りたたみ）
10. タスク pending / inProgress / completed
11. 質問 回答済み
12. 質問 期限切れ
13. 回答 a3（process→answer の 16pt）
14. 料金（時刻は各セルの timestamp）
15. ユーザー u2（auxiliary→user の 24pt）

幅 360/720、倍率 0.8/1.0/2.0、テーマ phlox-light と dracula。PNG は 2x バック。固定 420pt では切っていない。

## 設定保存先の確認結果

製品 `ChatTranscriptView`（および各セル）の倍率・テーマは `@AppStorage(ChatFontSettings.scaleKey)` / `@AppStorage(ThemeStore.themeKey)` で、`store:` 引数なし。SwiftUI 既定は `UserDefaults.standard`。`.defaultAppStorage(suite)` を付けたときだけテスト用 suite を読む。

`ChatFontSettings.save` / `currentScale` の既定引数は `UserDefaults.standard`。ハーネスは suite へ `ChatFontSettings.save` し、ホストに `.defaultAppStorage(suite)` を付けた。

`DSColor` は `ThemeStore.active` を読む。`ThemeStore.active` は `UserDefaults.standard` 固定。テーマ色を変えるには suite だけでは足りず、standard の `phlox.theme` を一時書込して終了時に戻した。

実行時 sidecar: `/tmp/phlox-t13-visual.SPfR9c/t40-gateB/settings-store.txt`

中点画素の実測: phlox-light `(240,240,240)`、dracula `(49,49,49)`。テーマ差は出ている。

## PNG 一覧

パスはすべて `/tmp/phlox-t13-visual.SPfR9c/t40-gateB/` 配下。寸法は pixelWidth x pixelHeight（2x）。expanded と collapsed は同一バイト（展開操作が効いていない）。

| ファイル | 寸法 | 幅pt | 倍率 | テーマ | 展開 |
| --- | --- | ---: | ---: | --- | --- |
| transcript-w360-s0.8-phlox-light-collapsed.png | 720x4122 | 360 | 0.8 | phlox-light | collapsed |
| transcript-w360-s0.8-phlox-light-expanded.png | 720x4122 | 360 | 0.8 | phlox-light | expanded（未達） |
| transcript-w360-s0.8-dracula-collapsed.png | 720x4122 | 360 | 0.8 | dracula | collapsed |
| transcript-w360-s0.8-dracula-expanded.png | 720x4122 | 360 | 0.8 | dracula | expanded（未達） |
| transcript-w360-s1.0-phlox-light-collapsed.png | 720x5383 | 360 | 1.0 | phlox-light | collapsed |
| transcript-w360-s1.0-phlox-light-expanded.png | 720x5383 | 360 | 1.0 | phlox-light | expanded（未達） |
| transcript-w360-s1.0-dracula-collapsed.png | 720x5383 | 360 | 1.0 | dracula | collapsed |
| transcript-w360-s1.0-dracula-expanded.png | 720x5383 | 360 | 1.0 | dracula | expanded（未達） |
| transcript-w360-s2.0-phlox-light-collapsed.png | 720x14028 | 360 | 2.0 | phlox-light | collapsed |
| transcript-w360-s2.0-phlox-light-expanded.png | 720x14028 | 360 | 2.0 | phlox-light | expanded（未達） |
| transcript-w360-s2.0-dracula-collapsed.png | 720x14028 | 360 | 2.0 | dracula | collapsed |
| transcript-w360-s2.0-dracula-expanded.png | 720x14028 | 360 | 2.0 | dracula | expanded（未達） |
| transcript-w720-s0.8-phlox-light-collapsed.png | 1440x3424 | 720 | 0.8 | phlox-light | collapsed |
| transcript-w720-s0.8-phlox-light-expanded.png | 1440x3424 | 720 | 0.8 | phlox-light | expanded（未達） |
| transcript-w720-s0.8-dracula-collapsed.png | 1440x3424 | 720 | 0.8 | dracula | collapsed |
| transcript-w720-s0.8-dracula-expanded.png | 1440x3424 | 720 | 0.8 | dracula | expanded（未達） |
| transcript-w720-s1.0-phlox-light-collapsed.png | 1440x4071 | 720 | 1.0 | phlox-light | collapsed |
| transcript-w720-s1.0-phlox-light-expanded.png | 1440x4071 | 720 | 1.0 | phlox-light | expanded（未達） |
| transcript-w720-s1.0-dracula-collapsed.png | 1440x4071 | 720 | 1.0 | dracula | collapsed |
| transcript-w720-s1.0-dracula-expanded.png | 1440x4071 | 720 | 1.0 | dracula | expanded（未達） |
| transcript-w720-s2.0-phlox-light-collapsed.png | 1440x7844 | 720 | 2.0 | phlox-light | collapsed |
| transcript-w720-s2.0-phlox-light-expanded.png | 1440x7844 | 720 | 2.0 | phlox-light | expanded（未達） |
| transcript-w720-s2.0-dracula-collapsed.png | 1440x7844 | 720 | 2.0 | dracula | collapsed |
| transcript-w720-s2.0-dracula-expanded.png | 1440x7844 | 720 | 2.0 | dracula | expanded（未達） |
| cell-user-w720-s1.0-phlox-light.png | 1440x234 | 720 | 1.0 | phlox-light | default |
| cell-agent-markdown-w720-s1.0-phlox-light.png | 1440x1959 | 720 | 1.0 | phlox-light | default |
| cell-command-group-collapsed-w720-s1.0-phlox-light.png | 1440x102 | 720 | 1.0 | phlox-light | collapsed |
| cell-command-group-expanded-w720-s1.0-phlox-light.png | 1440x102 | 720 | 1.0 | phlox-light | expanded（未達） |
| cell-reasoning-w720-s1.0-phlox-light.png | 1440x140 | 720 | 1.0 | phlox-light | default |
| cell-file-change-w720-s1.0-phlox-light.png | 1440x102 | 720 | 1.0 | phlox-light | collapsed |
| cell-task-list-w720-s1.0-phlox-light.png | 1440x298 | 720 | 1.0 | phlox-light | 常時展開 |
| cell-question-answered-w720-s1.0-phlox-light.png | 1440x304 | 720 | 1.0 | phlox-light | default |
| cell-question-expired-w720-s1.0-phlox-light.png | 1440x376 | 720 | 1.0 | phlox-light | default |
| cell-turn-cost-w720-s1.0-phlox-light.png | 1440x90 | 720 | 1.0 | phlox-light | default |
| cell-thinking-w720-s1.0-phlox-light.png | 1440x120 | 720 | 1.0 | phlox-light | システム Reduce Motion |

## できなかった項目と理由

- 折りたたみ/展開の両状態: `DisclosureCard` の Button は NSView AX に `折りたたみ中` を出さない。見出し Cell へ合成マウスイベントを送ると `ChatTranscriptView` 側でハングした（ADR 0030 系の再レイアウトを疑う）。製品コードは触らない制約のため、展開 PNG は折りたたみと同じ。コマンドグループ・Reasoning・差分・20行超出力の展開内容は未撮影。
- Reduce Motion の両状態: `accessibilityReduceMotion` は WritableKeyPath ではなく `.environment` で上書きできない。システム設定は変更しない。Thinking は実行時のシステム値で 1 枚。
- トランスクリプト上の処理中表示: 切断クライアントで `startNew` しないため `status` は starting、`showsProcessingIndicator` は false。Thinking は個別セルのみ。
- 空出力グループのカード: 連続空白コマンド 2 件は `shouldRender=false` で描かれない（製品挙動）。fixture には入れてある。
- 課金セッションでの代替はしていない。

## 検証原文

```
(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-gateB-compile swift test --filter TranscriptTypographyRenderHarness)
✔ Test run with 1 test in 1 suite passed after 0.001 seconds.

(cd macos/Packages/SessionFeature && TRANSCRIPT_TYPOGRAPHY_HARNESS_OUT=/tmp/phlox-t13-visual.SPfR9c/t40-gateB ~/.agents/scripts/compact-test t40-gateB swift test --filter TranscriptTypographyRenderHarness)
✔ Test run with 1 test in 1 suite passed after 29.569 seconds.

(cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t40-gateB-full swift test)
✔ Test run with 902 tests in 113 suites passed after 1.215 seconds.
```

環境変数なしの filter 実行は 0.001 秒で成功（描画せず）。SessionFeature 全数は GREEN。コミットしていない。

=== REPORT COMPLETE ===
