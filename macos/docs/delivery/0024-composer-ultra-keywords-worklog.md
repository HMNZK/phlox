---
status: completed
last-verified: 2026-07-29
---

# 0024: composer-ultra-keywords run 作業ログ

> **このファイルの役割**: 2026-07-28〜29 の composer-ultra-keywords run で何をしたか・何が残ったか。
> **書かないもの**: なぜこの設計か（→ adr/0138）、今どう動いているか（→ architecture/chat-mode-ux-components.md）。

## 何を解決したか

Phlox の入力欄が Claude Code 本体と2点で食い違っていた。

1. `ultrathink` 等のキーワード型機能が素のテキストで表示され、効くのか判らない。
2. `/ultrareview`・`/deep-research` が、そのセッションで最初の1通を送るまで補完に出ない。

## 起点になった誤解の訂正

ユーザーの当初の要望は「`/ultraplan` などがスラッシュコマンドで出ない」だったが、CLI バイナリの
実装を読んだ結果、**`ultraplan` はスラッシュコマンドではなくキーワード**（`UFo(e)=Rqs(e,"ultraplan")`）
であることが判った。したがって要件は「補完に出す」ではなく「**キーワード強調で可視化する**」へ変わった。
`ultrareview` はスラッシュコマンドとキーワードの両方だった。

**この訂正自体が不正確だった（2026-07-29 追記）**: `ultraplan` もスラッシュコマンドとして CLI に実装が
あり、`isEnabled()`（Claude Code on the web 連携ゲート）が false のため init の一覧に載っていなかった。
「キーワードで可視化する」という決定は変わらないが、理由は「コマンドではないから」ではなく
「CLI が無効化しているから」。詳細は adr/0138 の追記節。

## 実測（本 run で PM が実行）

| 対象 | 結果 |
|---|---|
| `init` の `slash_commands`（cwd 2箇所で計測） | 106 件。`ultrareview`・`deep-research` を含み `ultraplan`・`ultrathink`・`ultracode` を含まない |
| 無送信 30 秒での init 到達 | 届かない（`hook_started` / `hook_response` の2行のみ）。ADR-0120 の主張を追認 |
| ADR-0120 の 104 件との差 | 2日で 2 件増。**一覧は日単位で動く** |
| キーワード検出の実装 | 2系統（`ultrathink` は素朴一致、他3語は `Rqs` の除外規則つき） |

## タスク分解と成果

並列幅3・クリティカルパス2。実装は Claude、レビューは Codex（クロスモデル）。

| task | 内容 | 難易度 | コミット |
|---|---|---|---|
| task-1 | `ComposerHighlight` のキーワード検出（純関数） | deep | 62491dd |
| task-2 | 静的フォールバック拡充（10→22）＋`seedCommands` 受け口 | standard | 47cfed8 |
| task-3 | `AvailableCommandsStore`（一覧の永続化） | standard | 47cfed8 |
| task-4 | 色トークン・網羅 switch・View / ViewModel 配線 | standard | f8a987c |

凍結した受け入れテスト（ab27a24・091a9e5→62491dd に統合）:
`AcceptanceComposerKeywordDetectionTests` / `AcceptanceComposerSeedCommandsTests` /
`AcceptanceAvailableCommandsStoreTests` / `AcceptanceComposerKeywordRenderingTests`。

## 検証（PM 自身が実走）

`.claude/verify.sh` を全数（フィルタ・skip なし）実走し **exit 0**:

- `swift test --package-path macos/Packages/SessionFeature` → **705 tests / 75 suites passed**
- `swift test --package-path macos/Packages/DashboardFeature` → **1492 tests / 140 suites passed**
- `swift build --package-path macos/Packages/AppBootstrap` → **Build complete!**

色の判別性は値で検証: 背景とのコントラスト light 5.02:1 / dark 13.37:1（WCAG AA 4.5:1 を満たす）、
既存2色との RGB 距離 154〜201（最大 441）。

## 独立レビューで見つかった実質的な指摘（1件）

`fallbackSlashCandidates` がカスタムコマンド → スキル → seed の順に積み、`deduplicated` が先勝ちのため、
同名がカスタムコマンドとスキルの両方にあると SKILL.md の description が捨てられ `"Custom command"` が残る。
積む順を「静的リスト → seed → commands → skills」へ変更して修正し、再現テストを追加した。
修正後のコードは task-4 のレビューが独立に検査して 0 件で通っている。

## 残った未検証・積み残し

- **GUI 目視は未実施**。実画面でキーワードが第3色で描画されるか、ライト/ダーク双方で判読できるか、
  エージェント種別ごとに ON/OFF が効くかは、AppKit レベルの受け入れテスト（実 `NSTextStorage` の
  前景色を比較）と色値の計算で担保しているが、**スクリーンショットによる確認はしていない**。
  検証用の Debug ビルドは `/tmp/PhloxBuildUltraKeywords/Build/Products/Debug/Phlox.app` にある。
- 初回起動かつ永続値なしでは、静的 22 件＋ディレクトリ走査に留まる（ADR 0138 の「残る制約」）。
- Codex / Cursor には一覧の供給源が無く静的フォールバックのまま（ADR-0120 の既知の制約・別 run）。
- `Rqs` は CLI の内部実装であり、CLI 更新で変わりうる。

## run 運営で起きたこと（次回への申し送り）

- **受け入れテストを4タスク分まとめて先行凍結したため、Swift のテストターゲットが task-4 完了まで
  コンパイルできなかった**。未実装のシンボルを参照するテストが1本でもあるとターゲット全体が落ちるため、
  task-1〜3 は「自分の担当分でエラーがゼロ」までしか確認できず、全数 green の確認が最後まで持ち越された。
  コンパイル言語では、タスクごとに凍結するか、未実装分をビルド対象から外せる構成を先に用意する。
- **`ComposerSuggestionController` が task-2 のファイルにあるのに、その配線を task-4 の契約に書いた**
  （PM の分解ミス）。task-4 の実装役はスコープを自分で広げず停止して報告し、PM が所有権を移管した。
- **`git add -A` で task-1 の実装をテスト用コミットに巻き込んだ**。`--amend` でメッセージを訂正した。
- 独立レビュアー（Codex の read-only サンドボックス）は **Swift のテストを自走できない**
  （`/tmp/xcrun_db-*` の作成が拒否される）。判定は静的検証に限られ、テスト green は PM が別経路で供給した。
