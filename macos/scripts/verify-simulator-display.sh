#!/usr/bin/env bash
# §7-4 の品質ゲート。アプリを終了・再起動せず、worktree 内にだけビルドする。
set -euo pipefail
MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$MACOS_DIR/.." && pwd)"
mkdir -p "$ROOT/.build"
xcodegen generate --spec "$MACOS_DIR/project.yml"
xcodebuild -project "$MACOS_DIR/Phlox.xcodeproj" -scheme Phlox -configuration Debug \
  -derivedDataPath "$ROOT/.build/DerivedData" build
"$HOME/.agents/scripts/compact-test" simulator-display-packages \
  bash "$MACOS_DIR/scripts/run-swift-tests.sh" DashboardFeature SimulatorBridgeKit
"$HOME/.agents/scripts/compact-test" simulator-bridge-regressions \
  python3 "$MACOS_DIR/scripts/tests/test_simulator_bridge_regressions.py"
"$HOME/.agents/scripts/compact-test" simulator-bridge-signing \
  bash "$MACOS_DIR/scripts/tests/test_simulator_bridge_signing.sh"
