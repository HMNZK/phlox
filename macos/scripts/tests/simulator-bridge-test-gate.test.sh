#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TEMP_DIR="$(mktemp -d "$MACOS_DIR/../.build/simulator-test-gate.XXXXXX")"
trap 'rm -R "$TEMP_DIR"' EXIT
mkdir -p "$TEMP_DIR/bin"
cat > "$TEMP_DIR/bin/swift" <<'SWIFT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SIMULATOR_GATE_COMMANDS"
echo '✔ Test run with 1 test passed.'
SWIFT
chmod +x "$TEMP_DIR/bin/swift"
export SIMULATOR_GATE_COMMANDS="$TEMP_DIR/commands"
# 引数・環境変数で対象を上書きせず、既定の検証対象に含まれることを確認する。
env -u SWIFT_TEST_PACKAGES -u SWIFT_TEST_SKIP PATH="$TEMP_DIR/bin:$PATH" \
  "$SCRIPT_DIR/../run-swift-tests.sh"
if ! grep -Fxq 'test --package-path Packages/SimulatorBridgeKit' "$SIMULATOR_GATE_COMMANDS"; then
  echo 'SimulatorBridgeKit が既定の検証対象にありません' >&2
  exit 1
fi
echo 'シミュレーター共通部品の検証ゲート: 成功'
