---
task: task-48
status: completed
---

## 詰まった点

レビュー r1 HIGH は `CommandExecutionCell` の見出しをコマンド原文／`missingCommand` にしたことが task-46 の統一見出し「処理の詳細（N件）」を壊していた。凍結テスト `AcceptanceUIWordingTests` は `UIWording.text(.missingCommand)` の日英リテラルだけを検査し、見出しへの接続は要求しない。rb の VIEW_SITES は `CommandExecutionCell` の body が `.missingCommand` を参照することだけを要求する。両立する。見出しは `presentation.heading` に戻し、`missingCommand` は展開内容のコマンド原文が空のときの代替表示にだけ使う。MEDIUM のハーネス修理は先行コミット。

## できた風だが実は未完

実装担当の指定検証（配線 selftest / 配線本番 / DesignSystem・SessionFeature・DashboardFeature の Swift Testing / `git diff --check`）は、配線本番の rb 自身の基準不一致 NG を除き GREEN。契約 4 の App ビルドと契約 5 のプレースホルダ画面目視は PM ゲートであり本役では未実施。チーム入力欄の到達目視も未実施。

## 置いた前提・仮定

- 対象 View は `@Environment(\.locale)` の主言語を `languageCode` として渡す。正本は UserDefaults / `Locale.current` を読まない。
- 権限固有の値名（Read Only / Auto / Full Access / Bypass 等）と `claudePermissionTitle` / `cursorModeTitle` は task-50 に残す。Plan 見出しだけ正本へ接続した。
- `CommandExecutionCell` の見出しは task-46 の `TranscriptItemPresentation.heading`。サブタイトルの「実行中」と空出力条件、`isToolCall` 式、コピー成功時間、token 丸めは基準のまま。
- `RichMarkdownView.theme` / `themeCacheKey` の `languageCode` 既定は空文字。既存のテーマキャッシュテストが言語引数なしで呼ぶため。空は日本語フォールバックになる。
- `ApprovalBanner` の承認・拒否・キャンセルはファイル直下ヘルパー経由で正本へ届く（配線は struct 外ヘルパーを追跡する）。

## 契約からの逸脱

なし。allowed_paths 外・台帳・契約は変更していない。既存 3 テストと rb の変更は PM 裁定のハーネス修理に限る。

## レビュー重点

- 単体コマンドのカード見出しが `presentation.heading`（「処理の詳細（1件）」）であり、コマンド原文は展開内容側であること。
- `missingCommand` が空コマンドの展開表示にだけ使われていること。
- 3 入力欄が同じ `composerPlaceholder` を参照しているか。グリッドは `GridChatColumn` が正本を引き、`GridComposerBar` は文字列を表示するだけである点。
- 通常メニューと省略メニュー、コピー前後の help / AX、Markdown テーマキャッシュの言語キー。
- task-50 所有の権限値名を翻訳していないか。Plan の末尾配置・排他・内部値。

## 検証原文

```
$ ruby .claude/scripts/task48-wiring.rb --selftest
task48-wiring --selftest: OK
SELFTEST_EXIT:0

$ env TASK48_BASELINE=274e730 ruby .claude/scripts/task48-wiring.rb
task48-wiring: NG 基準時点のrb 自身が現在と同一ではない
WIRING_EXIT:1

$ SWIFT_TEST_SERIAL_PACKAGES="DashboardFeature SessionFeature" ~/.agents/scripts/compact-test t48-rw bash macos/scripts/run-swift-tests.sh DesignSystem SessionFeature DashboardFeature
✔ Test run with 14 tests in 2 suites passed after 5.320 seconds.
SWIFT_TEST_EXIT:0

$ git diff --check
(出力なし)
DIFF_CHECK_EXIT:0
```

=== REPORT COMPLETE ===
