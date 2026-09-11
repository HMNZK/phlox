#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
compact=/Users/ryosuke/.agents/scripts/compact-test
# 旧スタイルの除去（UI-05 の実装本体）。実装前は red。改名による素通りを防ぐため肯定検査も置く。
# 外観の合格判定はこれだけで行わず、PM が画像を目視する。
source_check() {
  "$compact" settings-buttons-source ruby -e '
    src = File.read("App/SettingsView.swift")
    abort "SettingsView.swift に RichButtonStyle が残っている" if src.include?("RichButtonStyle")
    abort "SettingsView.swift に focusEffectDisabled が残っている" if src.include?("focusEffectDisabled")
    abort "SettingsView.swift に focusable(false) が追加されている" if src.include?("focusable(false)")
    abort "SettingsView.swift に private な ButtonStyle 実装が残っている" if src =~ /struct\s+\w+\s*:\s*(Primitive)?ButtonStyle/
    n = src.scan(/\.buttonStyle\(\.bordered\)/).size
    abort "標準 .bordered の適用が3件未満（#{n}件）" if n < 3
  '
}
evidence=$(mktemp -d /tmp/phlox-settings-acceptance.XXXXXX)
printf 'PHLOX_UI_EVIDENCE=%s\n' "$evidence"
if command -v xcodegen >/dev/null; then
  xcodegen generate
else
  /opt/homebrew/bin/xcodegen generate
fi
options=(-project Phlox.xcodeproj -scheme PhloxUITests -configuration Debug
  -destination platform=macOS,arch=arm64 -derivedDataPath "$evidence"
  -parallel-testing-enabled NO)
"$compact" --full settings-buttons-build xcodebuild "${options[@]}" build-for-testing
code=0
"$compact" --full settings-buttons-gui xcodebuild "${options[@]}" \
  -resultBundlePath "$evidence/gui.xcresult" \
  -only-testing:PhloxUITests/SettingsAuxiliaryButtonsAcceptanceTests test-without-building || code=$?
xcrun xcresulttool get test-results summary --path "$evidence/gui.xcresult" > "$evidence/summary.json"
"$compact" settings-buttons-test-count ruby -rjson -e '
  s = JSON.parse(File.read(ARGV.fetch(0)))
  abort "設定ボタンの予定2件が未実走またはskipされた" unless
    s.fetch("totalTestCount") == 2 && s.fetch("skippedTests") == 0 &&
    s.fetch("expectedFailures") == 0 && s.fetch("passedTests") + s.fetch("failedTests") == 2
' "$evidence/summary.json"
printf 'PHLOX_UI_RESULT_BUNDLE=%s/gui.xcresult\n' "$evidence"
source_check
exit "$code"
