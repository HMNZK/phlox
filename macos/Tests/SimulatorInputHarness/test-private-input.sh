#!/bin/bash
set -uo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$TASK_ROOT/.build"
xcrun clang -fobjc-arc -fblocks -framework Foundation -framework AppKit -framework IOSurface \
  "$TASK_ROOT/PrivateInputTests.m" "$TASK_ROOT/../../SimulatorBridgeService/PrivateSimulatorAPI.m" \
  -o "$TASK_ROOT/.build/PrivateInputTests" || exit $?
failed=0
for case_name in 重複押下 キーリピート 小量 位相 ホイール 端; do
  "$TASK_ROOT/.build/PrivateInputTests" "$case_name" || failed=1
done
exit "$failed"
