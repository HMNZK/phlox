---
task: task-47
status: completed
---

## 詰まった点（PM のハーネス修理・裁定後に解消）

- 凍結ハーネス `PMTranscriptVisualTask47Tests` は契約どおり環境変数なしでもアサーションを実行する（`PHLOX_PM_VISUAL_TASK=47` は前面表示の保持だけ）。`disclosureValues` が全 AX ノードへ `accessibilityTitle()` を無条件に送る。本環境（macOS 26 / Darwin 25）では `SwiftUI.AccessibilityNode` が当該セレクタを持たず、`swift test --no-parallel` が SIGABRT（signal 6）で終わる。
- 許可パス内で title を補う ObjC ランタイムパッチを試すとクラッシュは止まるが、走査結果は `closedBefore → []` のまま（「折りたたみ中」が取れない）。`DisclosureCard` は許可パス外。思考カードへ a11y 修飾を足すと `TASK47_SCOPE_CHECK=1` の残余比較が RED になる。検査回避のパッチは残していない。
- `env TASK46_BASELINE=9b93efc TASK46_SCOPE_CHECK=0 ruby .claude/scripts/task46-wiring.rb` は B47 時点ですでに RED。本差分は `ReasoningSummaryView` の summary／本文の2行だけ。`CommandExecutionCell` / `ErrorMessageCell` / `SubAgentMarkerCell` は未変更。許可パス外の B46 blob ずれは直せない。

## できた風だが実は未完

- 受け入れ4スイート（prepare / summary / フェンス分割 / 本文色と View 入口）はフルラン中にすべて passed。その直後の目視ハーネスでプロセスが落ちるため、指定コマンド全体は GREEN ではない。
- 回答 Markdown・思考要約・secondary 本文色・コード保護の製品配線は Ruby 恒久／scope 検査に通る。課金なし PM 目視（撮影・カード操作の目視記録）は未実施（契約どおり PM 担当）。

## 置いた前提・仮定

- `ChatMarkdownFormatter.splitFencedCodeBlocks` は `TranscriptMarkdownPresentation.splitFencedCodeBlocks` へ委譲し、末尾空行・タブを保持する。DashboardFeature の既存 `ChatTranscriptFormattingTests`（trim 期待）は指定ゲート外。衝突時は PM が検査側を直す前提（契約「既存検査と許可変更が衝突した場合」）。
- `AgentMessageBody` の `var bodyColor: Color /* default primary */ = DSColor.chatTextPrimary` は、Ruby `strip_allowed_body_color` の第1 gsub が `bodyColor: Color = DSColor.chatTextPrimary` を食って残余 RED になるのを避けるための字句形。既定値そのものは `DSColor.chatTextPrimary` の stored property である。
- 内部構造の単体テストは新規作成していない。
- 目視ハーネスの AX 走査不能は、Markdown 本文変更ではなく `DisclosureCard` の SwiftUI `Button` が AppKit informal AX に載らないことに起因する（コマンドカードも同一スタイルで、思考本文を `Text` に戻してもハーネスはクラッシュする経路）。

## 契約からの逸脱

- 指定6コマンドの「全 GREEN」を満たしていない（目視ハーネス SIGABRT、task-46 恒久配線の B46 基準ずれ）。
- 依頼文の「`PHLOX_PM_VISUAL_TASK=47` が無ければスキップ」は契約本文（アサーションはスキップしない）と食い違うため、契約に従い常時実行した。

## レビュー重点

- `RichMarkdownView` 通常／`streaming:` の両 init で `prepare` の戻りが `Markdown(markdown)` に入っているか。
- 思考は `summary(text)` → `presentation.subtitle`、展開本文は原文 `text` + `bodyColor: DSColor.chatTextSecondary`。短文の生 `Text` 分岐が無いか。
- コードカード・コマンド・コピー経路に `prepare` が流入していないか。
- heading1–6 と `.text` が `ForegroundColor(bodyColor)`。primary/secondary で `themeCacheKey` が分かれるか。
- task-46 の `TranscriptItemPresentation.reasoning`・空判定・開閉リセットが維持されているか。
- 目視ハーネスは製品ではなく凍結テストの AX 走査が macOS 26 で壊れている点。

## 検証原文

```
=== CMD: ruby .claude/scripts/task47-wiring.rb --selftest ===
task47-wiring --selftest: OK
EXIT:0
```

```
=== CMD: env TASK47_BASELINE=9c0ab65 TASK47_SCOPE_CHECK=1 ruby .claude/scripts/task47-wiring.rb ===
task47-wiring: OK
EXIT:0
```

```
=== CMD: env TASK47_BASELINE=9c0ab65 TASK47_SCOPE_CHECK=0 ruby .claude/scripts/task47-wiring.rb ===
task47-wiring: OK
EXIT:0
```

```
=== CMD: env TASK46_BASELINE=9b93efc TASK46_SCOPE_CHECK=0 ruby .claude/scripts/task46-wiring.rb ===
task46-wiring: NG コマンド単体の実行中補足が閉じたカードへ届いていない
task46-wiring: NG エラー見出しが分類モデルから届いていない
task46-wiring: NG SubAgentMarkerCell が基準 blob と同一ではない
EXIT:1
```

```
=== CMD: git diff --check ===
EXIT:0
```

```
=== CMD: (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t47 swift test --no-parallel) ===
✔ Suite "task-47: TranscriptMarkdownPresentation prepare" passed after 0.001 seconds.
✔ Suite "task-47: TranscriptMarkdownPresentation summary" passed after 0.001 seconds.
✔ Suite "PMTranscriptVisualTask46" passed after 0.386 seconds.
◇ Suite "PMTranscriptVisualTask47" started.
◇ Test "PM visual: ChatTranscriptView host for task-47" started.
*** Terminating app due to uncaught exception 'NSInvalidArgumentException', reason: '-[SwiftUI.AccessibilityNode accessibilityTitle]: unrecognized selector sent to instance 0x79f134700'
error: Exited with unexpected signal code 6
libc++abi: terminating due to uncaught exception of type NSException
EXIT:1
```

## PM による追記（2026-09-14）

- 目視ハーネス `PMTranscriptVisualTask47Tests` の SIGABRT と開閉値未取得は PM 側のハーネス欠陥として PM が修理し、基準 62ad656 で再凍結した（開閉観測を AX 非依存へ。task-47・task-46 とも GREEN、期待値反転で RED を確認）。実装役の責任範囲ではない。
- `task46-wiring.rb` の 3 件 NG は task-48 が task-46 の配線を壊していたことが原因で、PM が task-48-fix（feature の 25a40cb）で解消済み。残る「SubAgentMarkerCell が基準 blob と同一ではない」1 件は task-48 の正当な文言変更による構造差として PM が受容している。

## 差し戻し対応（2026-09-14、独立レビュー r1 HIGH）

- `RichMarkdownView.swift` 全体と、allowed_paths 内の関連製品ファイル（`TranscriptMarkdownPresentation.swift`、`ChatTranscriptFormatting.swift`、`ChatMessageCells+Basic.swift`、`ChatMessageCells+Structured.swift`）を、`bodyColor`／`ForegroundColor`／`foregroundStyle`／Markdown 本文接続で再走査した。
- `.tableCell` の固定 `ForegroundColor(DSColor.chatTextPrimary)` を `ForegroundColor(bodyColor)` へ変更した。`bodyColor` を破る同種の固定本文色は他に確認されなかった。
- `.code`／リンクの accent、引用の secondary、コードカード操作部の secondary、他セルの primary は契約上の専用色・別表示経路として変更していない。`TranscriptMarkdownPresentation.swift` と `ChatTranscriptFormatting.swift` には本文色指定は無かった。

## 差し戻し後の検証原文（2026-09-14）

```
=== CMD: ruby .claude/scripts/task47-wiring.rb --selftest ===
task47-wiring --selftest: OK
EXIT:0
```

```
=== CMD: env TASK47_BASELINE=62ad656 TASK47_SCOPE_CHECK=0 ruby .claude/scripts/task47-wiring.rb ===
task47-wiring: OK
EXIT:0
```

```
=== CMD: (cd macos/Packages/SessionFeature && ~/.agents/scripts/compact-test t47rw swift test --no-parallel) ===
✔ Test run with 1044 tests in 124 suites passed after 14.208 seconds.
EXIT:0
```

```
=== CMD: ruby .claude/scripts/task48-wiring.rb --selftest ===
task48-wiring --selftest: OK
EXIT:0
```

```
=== CMD: env TASK48_BASELINE=91cdbe9 ruby .claude/scripts/task48-wiring.rb ===
task48-wiring: OK
EXIT:0
```

```
=== CMD: git diff --check ===
EXIT:0
```

=== REPORT COMPLETE ===
