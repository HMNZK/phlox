#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
compact=/Users/ryosuke/.agents/scripts/compact-test
evidence=$(mktemp -d /tmp/phlox-mode-acceptance.XXXXXX)
printf 'PHLOX_UI_EVIDENCE=%s\n' "$evidence"
if command -v xcodegen >/dev/null; then
  xcodegen generate
else
  /opt/homebrew/bin/xcodegen generate
fi
options=(-project Phlox.xcodeproj -scheme PhloxUITests -configuration Debug
  -destination platform=macOS,arch=arm64 -derivedDataPath "$evidence"
  -parallel-testing-enabled NO)
"$compact" --full view-mode-build xcodebuild "${options[@]}" build-for-testing
code=0
"$compact" --full view-mode-gui xcodebuild "${options[@]}" \
  -resultBundlePath "$evidence/gui.xcresult" \
  -only-testing:PhloxUITests/ViewModeAccessibilityTests test-without-building || code=$?
xcrun xcresulttool get test-results summary --path "$evidence/gui.xcresult" > "$evidence/summary.json"
"$compact" view-mode-test-count ruby -rjson -e '
  s = JSON.parse(File.read(ARGV.fetch(0)))
  abort "表示モードの予定2件が未実走またはskipされた" unless
    s.fetch("totalTestCount") == 2 && s.fetch("skippedTests") == 0 &&
    s.fetch("expectedFailures") == 0 && s.fetch("passedTests") + s.fetch("failedTests") == 2
' "$evidence/summary.json"
printf 'PHLOX_UI_RESULT_BUNDLE=%s/gui.xcresult\n' "$evidence"
exit "$code"
