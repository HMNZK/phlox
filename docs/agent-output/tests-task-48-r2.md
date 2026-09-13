# task-48 r2 ハーネス修理の検証原文

PM 裁定（decision-log 2026-09-14「task-48 レビュー r1 裁定」）の (2)(3) に対するハーネス修理後。
rb・テスト自身の基準不一致 NG は想定内。他の NG は無い。

```
$ ruby .claude/scripts/task48-wiring.rb --selftest
task48-wiring --selftest: OK
SELFTEST_EXIT:0

$ env TASK48_BASELINE=274e730 ruby .claude/scripts/task48-wiring.rb
task48-wiring: NG 基準時点のrb 自身が現在と同一ではない
WIRING_EXIT:1

$ SWIFT_TEST_SERIAL_PACKAGES="DashboardFeature SessionFeature" ~/.agents/scripts/compact-test t48-rw bash macos/scripts/run-swift-tests.sh DesignSystem SessionFeature DashboardFeature
✔ Test run with 14 tests in 2 suites passed after 5.218 seconds.
SWIFT_TEST_EXIT:0

$ git diff --check
(出力なし)
DIFF_CHECK_EXIT:0
```
