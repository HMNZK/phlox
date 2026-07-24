---
status: completed
last-verified: 2026-07-24
---

# Worklog 0016: エージェントグリッドのカクつき実測と原因特定（→ ADR 0116）

## この run で何をしたか

グリッドビューで複数セッション同時出力時のカクつきについて、**本番 Release ビルド・実 9 セッションで Instruments 実測**し、根本原因を特定した。当初の仮説（端末エンジン = SwiftTerm の feed/draw がメインスレッド直列である、ADR 0115）を実測で**反証**し、`.appServer` グリッドのカクつきは SwiftUI/CoreAnimation 側であると確定。Codex（gpt-5.6-terra, effort=high, read-only）に修正方針を相談し、対処方針を **ADR 0116** に落とした。ADR 0115 は `.pty` 向けとスコープを限定した。実装は未着手。

## 計測セットアップ

- **ビルド**: 計測用 Release ビルド（`/private/tmp/PhloxBuildMetalRender/…/Phlox.app`）に Instruments を attach。
- **計装**: SwiftTerm fork に os_signpost を追加（`macos/Vendor/SwiftTerm/Sources/SwiftTerm/Apple/PhloxPerfSignpost.swift` の `com.phlox.perf`、`feed`/`draw`/`inputToDisplay` を `AppleTerminalView`/`MacTerminalView` に挿入）。**この計装は `.pty` 描画経路用**であり、今回の `.appServer` グリッドでは 1 件も発火しなかった（＝経路が別であることの証拠）。
- **記録**: `xctrace record --template 'Logging'`（os_signpost / os-signpost-interval）と `--template 'Time Profiler'`（time-profile / potential-hangs）。
- **負荷**: 9 つの実 `.appServer` セッション（Foxglove〜Bluebell）を 3×3 グリッドで同時実行。各セッションに read-only の重い課題を投入（サブエージェント fan-out ×2〔`model:haiku` 指定〕、ヘッドレス codex ×2、テスト実行、Release ビルド、rg 横断、git 履歴、大量スクロール）。UI 投入は CGEvent クリッカー＋クリップボード貼り付け＋Enter で自動化（`.appServer` の入力欄フォーカスは「次のセッション」メニューでは移らず、各タイルのクリックが必要と判明）。

## 実測結果

**定常（9 セッション同時出力・50 秒・os_signpost）**
- `CoreAnimation Transaction.Commit` 停滞: p50 15.6 / p95 22.6 / p99 26.1 / max 90.5ms（約 2489 回）
- `AppKit UpdateCycle` 停滞: p50 18.3 / p99 27.5 / max 90.5ms（1537 回）
- `com.phlox.perf`（SwiftTerm feed/draw）: **0 件**

**リサイズ（幅スイープ・18 秒・Time Profiler）**
- メインスレッドのハング **17 件・合計 7.8 秒（約 43%）**、個々 470〜643ms。
- メインスレッド内訳: CoreText 再 measure **85.6%** / SwiftUI layout 62.9% / AttributeGraph 57.1% / AttributedString 21.3% / Markdown(cmark) **0.1%**。

**確定した因果**: `.appServer` は `ChatTranscriptView`（ネイティブ SwiftUI・非 Lazy VStack・最大 40 件×9 タイル）で描画。リサイズで `contentMaxWidth`（`GridChatColumn` の子 GeometryReader 由来）が毎フレーム変わり、約 360 アイテムを CoreText で全再 typeset するのが 470〜643ms ハングの主因。markdown 再パースは無関係。

## Codex 助言（要点）

- リサイズ根治は **live resize 中の整形幅を完全固定し終了時に一回反映**（量子化・デバウンス・高さキャッシュは弱いと明確に否定）。
- 両方に効く最小変更は `gridTileDefaultLimit` 40→16。ただしリサイズ根治には幅固定が別途必要。
- 定常は `ChatItemView` Equatable 化＋確定/live 行分離。MarkdownUI AST キャッシュは後順位（API 有無要確認）。
- 長期本命は 1 タイル = TextKit 2 ドキュメント（段階移行）。

## 生成物 / 状態スナップショット

- **新規**: `macos/docs/adr/0116-agent-grid-swiftui-jank-live-resize-width-freeze.md`（対処方針・proposed）。
- **更新**: `macos/docs/adr/0115-terminal-engine-off-main-thread.md` にスコープ注記（`.pty` 向け・0116 参照）。
- 実装: **未着手**。ADR 0116 の優先順（幅固定 → 窓縮小 → 子 GeometryReader 除去 → Equatable/行分離）で着手予定。
- 生トレース（`/tmp/phlox-realmeasure/*.trace`・計装差分）は ephemeral。リポジトリにはコミットしていない。

## 積み残し / フォローアップ

- ADR 0116 の対処実装と、本ログの数値をベースラインにした再計測（hang 件数・Commit p99・CoreText 85.6% の低減確認）。
- `.pty` 系（ADR 0115）の feed/shaping/draw 分解は未取得のまま。
- 計装 signpost（`.pty` 用）を fork に残すか戻すかの判断。
