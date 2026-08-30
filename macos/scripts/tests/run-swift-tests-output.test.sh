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
printf '%s\n' '#!/usr/bin/env bash' \
  'echo "build noise"' \
  'echo "✔ Test run with 3 tests in 1 suite passed after 0.001 seconds."' \
  'if [ "${FAKE_SWIFT_FAIL:-0}" = "1" ]; then echo "failure detail"; exit 1; fi' \
  > "$TEMP_DIR/bin/swift"
chmod +x "$TEMP_DIR/bin/swift"

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
invalid="$(PATH="$TEMP_DIR/bin:$PATH" SWIFT_TEST_PACKAGES=AgentDomain SWIFT_TEST_OUTPUT=invalid "$RUNNER" 2>&1)"
invalid_exit=$?
set -e
assert_exit "$invalid_exit" 1
assert_contains "$invalid" "compact または full"

echo "run-swift-tests-output.test: OK"
