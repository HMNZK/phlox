#!/usr/bin/env bash
# macos/Packages/* の swift test を、**決定論的に green になる走らせ方**で実行する。
#
# ここがこの走らせ方の**正本**である。`swift test` を直接叩くと、下の「なぜ直列にするか」で
# 説明する理由により DashboardFeature が不安定に落ちる。CI・ローカル・エージェントの検証は
# すべて本スクリプトを経由すること。
#
# 使い方:
#   macos/scripts/run-swift-tests.sh                      # 既定のパッケージを全部
#   macos/scripts/run-swift-tests.sh AgentDomain          # パッケージを指定
#   SWIFT_TEST_SKIP="SuiteA SuiteB" macos/scripts/run-swift-tests.sh
#
# 環境変数:
#   SWIFT_TEST_PACKAGES         空白区切りのパッケージ名。引数が無いときの対象（既定は下記）
#   SWIFT_TEST_SKIP             空白区切りで除外するテストスイート名（swift test --skip に渡す）
#   SWIFT_TEST_SERIAL_PACKAGES  --no-parallel で走らせるパッケージ（既定 DashboardFeature）
#   SWIFT_TEST_GIT_SUITES       実 git を起動するスイート。DashboardFeature の別パスで走らせる
#   SWIFT_TEST_OUTPUT           compact（成功時は要約）または full（全ログ）。既定 compact
#
# 注意（macOS の bash は 3.2）: 全角文字の直前の変数は必ず ${var} と括る。
# 3.2 は `$label）` を変数名 `label）` として読み、unbound variable で落ちる。
# 空配列の展開も `${arr[@]+"${arr[@]}"}` の形にする（3.2 は set -u 下で素の展開が落ちる）。
set -uo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPACT_COMMAND="$MACOS_DIR/scripts/compact-command.sh"

DEFAULT_PACKAGES="AgentDomain DesignSystem MessageStore SessionFeature DashboardFeature"

# ── 直列実行するパッケージ ────────────────────────────────────────────────
#
# なぜ直列にするか（2026-08-05 に実測で確定した根本原因。詳細は
# macos/docs/adr/0170-dashboardfeature-tests-serial-execution.md）:
#
# swift-testing は DashboardFeature の約 1626 件を並列実行するが、**そのうち 639 件が
# `@Test @MainActor`** で、これらは単一の main thread 上で直列化される。つまり並列度を上げても
# MainActor の仕事は一本の列に並ぶだけで、**個々のテストの所要時間が総実行時間とほぼ等しくなる**
# （総 9.571 秒の回で、green のテストが 9.483 / 9.358 / 9.277 秒——自分の仕事が重いのではなく
# 丸ごと待たされている）。ここで壁時計の予算（テスト側 `waitUntil` ヘルパーの既定 0.5 秒）を
# 持つテストは、他テストの MainActor 仕事が予算を超えて先に入るだけで落ちる。
# 失敗件数は総実行時間に比例し、総 10 秒で 1〜3 件、総 262 秒で 14 件が落ちた。
# 落ちる顔ぶれは毎回入れ替わる（競争に負けた者が落ちる）。単独実行では常に green。
#
# **これは「テストが遅い」問題ではなく「単一資源(main thread)の過剰購読」問題である。**
# 並列実行をやめると過剰購読そのものが消える。実測: 並列は 5 回中 1〜2 回失敗し、時には
# 300 秒経ってもサマリ行すら出ない。**直列は 8 回連続 green で所要 52〜56 秒**（CPU 負荷 12 本の
# 下でも 2 回連続 green・71 秒）。
#
# これは「待ちを延ばして通す」対症療法ではない。待ち時間は 1 ミリ秒も増やしておらず、
# テストの期待も一切変えていない。変えたのは**走らせ方**だけである。
#
# 残る限界（正直に）:
#
# (a) 各テストの壁時計予算そのものは残っている。直列化で「他テストとの競合」は無くなったが、
#     極端に遅いマシンでは理論上まだ落ちうる。予算の完全撤廃は各テストの設計変更になるので
#     別課題として残す。
#
# (b) **直列化は、プロセス共有状態を使うテスト間の並列干渉を「隠す」**。
#     `setenv("PHLOX_DEFAULTS_SUITE", ...)` を使うテストが 3 ファイルある
#     （`AgentStartCardsTests.swift:19` / `StartAreaSelectionWhiteboxTests.swift:73,120`）。
#     環境変数はプロセス全体で共有されるので、並列実行ではテスト同士が互いの suite を
#     踏み合いうる。直列にするとこの干渉は起きなくなるが、**欠陥が消えたわけではなく
#     見えなくなっただけ**である。根治には `UserDefaults.phloxDefaults(environment:)` を
#     製品コード側で依存性注入として通す必要があり、テストだけでは閉じない。
#     独立レビュー（2026-08-05）が検出した。**別課題として起票済み。**
SERIAL_PACKAGES="${SWIFT_TEST_SERIAL_PACKAGES-DashboardFeature}"

# ── 実 git スイートの別パス ──────────────────────────────────────────────
#
# 実 git サブプロセスを起動するスイートは DashboardFeature の**別パス**で実行する。
# 実 git を起動するテストを同じプールで走らせると CPU を奪い合って失敗率が跳ね上がる
# （5 アーム計 48 回で実測）。**どちらのパスも green を要求するので、除外して隠しているのではない。**
GIT_SUITES="${SWIFT_TEST_GIT_SUITES-WorktreeIsolationSpawnTests AcceptanceRestoreAbortNoSpawnTests}"
GIT_PASS_PACKAGE="DashboardFeature"
PACKAGES="${*:-${SWIFT_TEST_PACKAGES:-$DEFAULT_PACKAGES}}"

SKIP_ARGS=()
for suite in ${SWIFT_TEST_SKIP:-}; do
  SKIP_ARGS+=(--skip "$suite")
done

serial_args_for() {  # <package>
  case " $SERIAL_PACKAGES " in
    *" $1 "*) printf '%s' "--no-parallel" ;;
    *) printf '' ;;
  esac
}

run_swift_test() {
  local pkg="$1"; shift
  local label="$1"; shift
  echo "=== swift test --package-path Packages/${pkg} $* [${label}] ==="
  COMPACT_COMMAND_OUTPUT="${SWIFT_TEST_OUTPUT-compact}" \
    COMPACT_COMMAND_SUMMARY_PATTERN='^(✔ Test run with|[[:space:]]*Executed [0-9]+ tests)' \
    "$COMPACT_COMMAND" "${pkg} / ${label}" swift test --package-path "Packages/$pkg" "$@"
}

cd "$MACOS_DIR" || { echo "run-swift-tests: macos ディレクトリが無い: $MACOS_DIR" >&2; exit 1; }

failed=""
for pkg in $PACKAGES; do
  if [ ! -f "Packages/$pkg/Package.swift" ]; then
    echo "run-swift-tests: パッケージが見つからない: Packages/$pkg" >&2
    failed="$failed $pkg(missing)"
    continue
  fi

  serial_arg="$(serial_args_for "$pkg")"
  serial_args=()
  [ -n "$serial_arg" ] && serial_args=("$serial_arg")

  if [ "$pkg" = "$GIT_PASS_PACKAGE" ] && [ -n "$GIT_SUITES" ]; then
    # パス1: 実 git スイートを外した本体。
    main_args=(${serial_args[@]+"${serial_args[@]}"} ${SKIP_ARGS[@]+"${SKIP_ARGS[@]}"})
    filter_args=()
    for suite in $GIT_SUITES; do
      main_args+=(--skip "$suite")
      filter_args+=(--filter "$suite")
    done
    run_swift_test "$pkg" "本体" ${main_args[@]+"${main_args[@]}"} || failed="$failed $pkg(main)"

    # パス2: 実 git スイートだけ。SWIFT_TEST_SKIP で全件除外済みなら走らせない。
    # **こちらにも直列指定を渡す**（実 git スイートにも `@MainActor` テストがあり、
    # 本体パスだけ直列にすると同じ過剰購読がこのパスで再発する）。
    skipped_all=1
    for suite in $GIT_SUITES; do
      case " ${SWIFT_TEST_SKIP:-} " in
        *" $suite "*) ;;
        *) skipped_all=0 ;;
      esac
    done
    if [ "$skipped_all" -eq 0 ]; then
      run_swift_test "$pkg" "実git" ${serial_args[@]+"${serial_args[@]}"} \
        ${SKIP_ARGS[@]+"${SKIP_ARGS[@]}"} ${filter_args[@]+"${filter_args[@]}"} \
        || failed="$failed $pkg(git)"
    else
      echo "=== ${pkg} の実 git パスは SWIFT_TEST_SKIP で全件除外されているのでスキップ ==="
    fi
  else
    run_swift_test "$pkg" "全数" ${serial_args[@]+"${serial_args[@]}"} ${SKIP_ARGS[@]+"${SKIP_ARGS[@]}"} \
      || failed="$failed $pkg"
  fi
done

if [ -n "$failed" ]; then
  echo "run-swift-tests: FAILED ->$failed" >&2
  exit 1
fi
echo "run-swift-tests: OK ($PACKAGES${SWIFT_TEST_SKIP:+ / skipped:$SWIFT_TEST_SKIP}${GIT_SUITES:+ / git別パス:$GIT_SUITES}${SERIAL_PACKAGES:+ / 直列:$SERIAL_PACKAGES})"
exit 0
