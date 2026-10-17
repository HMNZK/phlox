#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$SCRIPT_DIR/../run-swift-tests.sh"
COMPACT_RUNNER="$SCRIPT_DIR/../compact-command.sh"
TEMP_DIR="$(mktemp -d)"
trap 'rm -R "$TEMP_DIR"' EXIT

assert_contains() { [[ "$1" == *"$2"* ]] || { echo "expected output to contain: $2" >&2; exit 1; }; }
assert_not_contains() { [[ "$1" != *"$2"* ]] || { echo "expected output not to contain: $2" >&2; exit 1; }; }
assert_exit() { [[ "$1" -eq "$2" ]] || { echo "expected exit $2, got $1" >&2; exit 1; }; }

mkdir -p "$TEMP_DIR/bin"
cat > "$TEMP_DIR/bin/swift" <<'SWIFT'
#!/usr/bin/env bash
if [ "${FAKE_SWIFT_BUILD_FAIL:-0}" = "1" ] && [ "$1" = "build" ] && [ "${2:-}" = "--build-tests" ]; then
  echo "resource-only failure detail" >&2; exit 23
fi
command_name="$1"
shift
configuration=""
testability="absent"
package=""
scratch=""
mode="$command_name"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --configuration|--package-path)
      [ "$#" -ge 2 ] || { echo 'missing option argument' >&2; exit 2; }
      if [ "$1" = "--configuration" ]; then configuration="$2"; else package="$2"; fi
      shift 2 ;;
    --configuration=*) configuration="${1#--configuration=}"; shift ;;
    --package-path=*) package="${1#--package-path=}"; shift ;;
    --scratch-path)
      [ "$#" -ge 2 ] || { echo 'missing scratch path' >&2; exit 2; }
      scratch="$2"; shift 2 ;;
    -Xswiftc)
      [ "$#" -ge 2 ] || { echo 'missing compiler argument' >&2; exit 2; }
      if [ "$2" = "-enable-testing" ]; then testability=enabled; fi
      shift 2 ;;
    --build-tests) mode="build-tests"; shift ;;
    --show-bin-path) mode="bin-path"; shift ;;
    *) shift ;;
  esac
done
if [ -n "${FAKE_SWIFT_CALLS:-}" ]; then
  printf '%s %s %s %s\n' "$mode" "$configuration" "$package" "$testability" >> "$FAKE_SWIFT_CALLS"
fi
if [ -n "${FAKE_SWIFT_SCRATCH_CALLS:-}" ]; then
  printf '%s\t%s\t%s\n' "$mode" "$package" "$scratch" >> "$FAKE_SWIFT_SCRATCH_CALLS"
fi
if [ -n "${FAKE_SWIFT_ASSET_ROOT:-}" ]; then
  bundle="$FAKE_SWIFT_ASSET_ROOT/DesignSystem_DesignSystem.bundle"
  if [ "$mode" = build-tests ]; then mkdir -p "$bundle/Icons.xcassets"; fi
  if [ "$mode" = bin-path ]; then printf '%s\n' "$FAKE_SWIFT_ASSET_ROOT"; exit 0; fi
  if [ "$mode" = test ] && [ ! -f "$bundle/Assets.car" ]; then echo 'assets were not prepared before tests' >&2; exit 24; fi
fi
echo "build noise"
echo "✔ Test run with 3 tests in 1 suite passed after 0.001 seconds."
if [ "${FAKE_SWIFT_FAIL:-0}" = "1" ]; then echo "failure detail"; exit 1; fi
SWIFT
chmod +x "$TEMP_DIR/bin/swift"
cat > "$TEMP_DIR/bin/xcrun" <<'XCRUN'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = actool ] && [ "$2" = --compile ] || exit 25
printf 'compiled\n' > "$3/Assets.car"
XCRUN
chmod +x "$TEMP_DIR/bin/xcrun"

plain="$("$COMPACT_RUNNER" demo printf 'verbose output\n')"
[[ "$plain" = "demo: OK（要約未対応）" ]] || { echo "unexpected compact output: $plain" >&2; exit 1; }

set +e
preserved="$("$COMPACT_RUNNER" demo sh -c 'echo failure; exit 7' 2>&1)"
preserved_exit=$?
set -e
assert_exit "$preserved_exit" 7
assert_contains "$preserved" "failure"

compact="$(PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_PACKAGES=AgentDomain "$RUNNER")"
assert_contains "$compact" "✔ Test run with 3 tests"
assert_not_contains "$compact" "build noise"

full="$(PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_PACKAGES=AgentDomain SWIFT_TEST_OUTPUT=full "$RUNNER")"
assert_contains "$full" "build noise"

set +e
failed="$(PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_PACKAGES=AgentDomain FAKE_SWIFT_FAIL=1 "$RUNNER" 2>&1)"
failed_exit=$?
set -e
assert_exit "$failed_exit" 1
assert_contains "$failed" "failure detail"

set +e
resource_failed="$(PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_PACKAGES=AgentDomain FAKE_SWIFT_BUILD_FAIL=1 "$RUNNER" 2>&1)"
resource_failed_exit=$?
set -e
assert_exit "$resource_failed_exit" 1
assert_contains "$resource_failed" "resource-only failure detail"
assert_contains "$resource_failed" "✔ Test run with 3 tests"
assert_contains "$resource_failed" "AgentDomain(assets)"

set +e
invalid="$(PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_PACKAGES=AgentDomain SWIFT_TEST_OUTPUT=invalid "$RUNNER" 2>&1)"
invalid_exit=$?
set -e
assert_exit "$invalid_exit" 1
assert_contains "$invalid" "compact または full"

filtered="$(PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_FILTER="SuiteA SuiteB" SWIFT_TEST_OUTPUT=full "$RUNNER" DashboardFeature)"
assert_contains "$filtered" "--filter SuiteA --filter SuiteB [絞り込み]"
assert_not_contains "$filtered" "[実git]"
assert_contains "$filtered" "全件の合格ではない"

# Verify configuration on all three real argv routes, without relying on option order.
export FAKE_SWIFT_CALLS="$TEMP_DIR/configuration-calls"
for requested in default debug release; do
  : > "$FAKE_SWIFT_CALLS"
  expected="$requested"
  if [ "$requested" = default ]; then
    expected=debug
    env -u SWIFT_TEST_CONFIGURATION PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_PACKAGES=AgentDomain "$RUNNER" > "$TEMP_DIR/configuration-output"
  else
    env SWIFT_TEST_CONFIGURATION="$requested" PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_PACKAGES=AgentDomain "$RUNNER" > "$TEMP_DIR/configuration-output"
  fi
  for mode in build-tests bin-path test; do
    expected_testability=absent
    if [ "$mode" = build-tests ] && [ "$expected" = release ]; then expected_testability=enabled; fi
    grep -Fxq "$mode $expected Packages/AgentDomain $expected_testability" "$FAKE_SWIFT_CALLS" || {
      echo "missing expected configuration route: $mode $expected" >&2; exit 1;
    }
  done
  [ "$(wc -l < "$FAKE_SWIFT_CALLS")" -eq 3 ] || { echo 'unexpected extra swift invocation' >&2; exit 1; }
done
: > "$FAKE_SWIFT_CALLS"
set +e
bad_configuration="$(PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_PACKAGES=AgentDomain SWIFT_TEST_CONFIGURATION=unknown "$RUNNER" 2>&1)"
bad_configuration_exit=$?
set -e
assert_exit "$bad_configuration_exit" 1
assert_contains "$bad_configuration" "debug または release"
[ ! -s "$FAKE_SWIFT_CALLS" ] || { echo 'invalid configuration reached swift' >&2; exit 1; }
unset FAKE_SWIFT_CALLS

# ビルド・素材の出力先検索・テストが、空白を含む同じ専用領域を使う。
# 素材が無い初回と素材が更新された再実行の両方で、テストより前にactoolが終わる。
export FAKE_SWIFT_SCRATCH_CALLS="$TEMP_DIR/scratch-calls"
export FAKE_SWIFT_ASSET_ROOT="$TEMP_DIR/asset output"
scratch_root="$TEMP_DIR/scratch output"
for pass in first updated; do
  : > "$FAKE_SWIFT_SCRATCH_CALLS"
  if [ "$pass" = updated ]; then
    printf 'stale\n' > "$FAKE_SWIFT_ASSET_ROOT/DesignSystem_DesignSystem.bundle/Assets.car"
  fi
  PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_SCRATCH_ROOT="$scratch_root" \
    SWIFT_TEST_FILTER=SuiteA "$RUNNER" DashboardFeature > "$TEMP_DIR/scratch-output"
  for mode in build-tests bin-path test; do
    expected="$(printf '%s\tPackages/DashboardFeature\t%s/DashboardFeature' "$mode" "$scratch_root")"
    grep -Fxq "$expected" "$FAKE_SWIFT_SCRATCH_CALLS" || { echo "missing scratch route: $mode" >&2; exit 1; }
  done
  [ "$(cat "$FAKE_SWIFT_ASSET_ROOT/DesignSystem_DesignSystem.bundle/Assets.car")" = compiled ] || {
    echo 'asset catalog was not refreshed' >&2; exit 1;
  }
done
: > "$FAKE_SWIFT_SCRATCH_CALLS"
set +e
bad_scratch="$(PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_SCRATCH_ROOT=relative "$RUNNER" AgentDomain 2>&1)"
bad_scratch_exit=$?
set -e
assert_exit "$bad_scratch_exit" 1
assert_contains "$bad_scratch" "絶対パス"
[ ! -s "$FAKE_SWIFT_SCRATCH_CALLS" ] || { echo 'invalid scratch reached swift' >&2; exit 1; }
unset FAKE_SWIFT_SCRATCH_CALLS FAKE_SWIFT_ASSET_ROOT

echo "run-swift-tests-output.test: OK"
