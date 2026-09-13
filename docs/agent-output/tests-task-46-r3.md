---
task: task-46
status: completed

## 修理内容

製品コードは未変更。契約・台帳は未変更。固定シナリオのアサーションは環境変数なしで常時実行、ウィンドウ表示・操作待ちだけ `PHLOX_PM_VISUAL_TASK=46` で切替、のまま。

### PMTranscriptVisualTask46Tests.swift（コンパイル修理）

- L220: `Task46VisualScenario` を `private final class` にした。internal クラスが `private` の `Task46VisualClient` を保持すると emit-module が落ちる。可視性を揃えただけで、保持する client・シナリオ操作は同じ。
- L227: `contentMaxWidth` を `CGFloat?` にし、初期値も `ComposerLayout.transcriptContentMaxWidth(mainColumnWidth: 720)` にした。戻りは製品どおり Optional。`nil` を `720` に潰すと ChatSessionView 経路と意味が変わる。
- L56・L286: Optional のまま代入する（unwrap しない）。製品 `ChatTranscriptView(contentMaxWidth: CGFloat?)` と同じ値を渡す。
- L421-423: 同期 `pumpMainRunLoop` を追加。`RunLoop.run(until:)` は async 文脈から呼べない。呼び出し側の待ち時間 0.12 / 0.2 秒は変えていない。
- L66・L105・L466: `RunLoop.main.run` の直呼びを `pumpMainRunLoop` に置換。イベント処理の意味は同じ。環境変数ありのウィンドウ保持ループも RunLoop を回す。

### AcceptanceTranscriptItemPresentationTests.swift（テスト欠陥）

- L258-263: `diffLines.count == 501` を `diffCodeView.sourceLineCount == 501` に変更。fixture は `+line1`…`+line501` に `---` / `+++` / `@@` を付けている。`diffLines` はヘッダ込み 504 行。契約の「501行は初期500・残り1」はカード描画行（`sourceLineCount`、ヘッダ・hunk 除外）。初期500・`line501` 非表示・copy 全文の期待は維持。

### PMTranscriptVisualTask46Tests.swift L203-207（同上）

- 同じ 501 行を `diffCodeView.sourceLineCount` で数える。表示上限 `visibleLineLimit` の期待は維持。

### AcceptanceCodexProductionReachabilityTests.swift（テスト欠陥）

- L131-132: AX の `inspect` 直読みを見出し `タスク（2件）` に変更。CodexSessionSurface は `TaskListCell` を使う。契約はタスク既定閉で、閉時 AX は `AXDisclosureTriangle` の「タスク（2件）」のみ（実測）。ステップ名 `inspect` は既存の `viewModel.codexPlanTaskState?.tasks.map(\.title)` 照合で維持。`child-new` と identifier の期待は維持。

## 検証原文

```
$ ruby .claude/scripts/task46-wiring.rb --selftest
task46-wiring --selftest: OK
exit_code: 0

$ env TASK46_BASELINE=11fbb08 ruby .claude/scripts/task46-wiring.rb
task46-wiring: NG 基準時点の受け入れテスト1が現在と同一ではない
task46-wiring: NG 基準時点の受け入れテスト2が現在と同一ではない
exit_code: 1
```

NG はハーネス修理した受け入れテスト 2 本の blob 不一致のみ。rb 自身・恒久回帰・基準祖先・実装前マーカーの NG 行は無い。

```
$ (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t46-h swift test --no-parallel)
✔ Test run with 950 tests in 117 suites passed after 12.505 seconds.
exit_code: 0

$ git diff --check
exit_code: 0
```

`--no-parallel` は SessionFeature の `@MainActor` 競合で壁時計テストが落ちるのを避ける公式走らせ方。並列の `swift test` では本修理と無関係な timeout が RED になる。

=== REPORT COMPLETE ===
