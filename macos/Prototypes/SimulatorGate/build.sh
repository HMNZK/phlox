#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
xcodegen generate --spec project.yml
xcodebuild -project SimulatorGate.xcodeproj -scheme SimulatorGate -configuration Release -derivedDataPath "$PWD/.build/DerivedData" clean build 2>&1 | tee .build/host-build.log
xcodebuild -project SimulatorGate.xcodeproj -scheme GateTest -configuration Release -sdk iphonesimulator -derivedDataPath "$PWD/.build/TestDerivedData" clean build 2>&1 | tee .build/test-build.log
# 公証・タイムスタンプサーバーへの送信は行わない。
identity=$(security find-identity -v -p codesigning | python3 -c 'import re,sys; text=sys.stdin.read(); found=re.search(r"([0-9A-F]{40}) \"Developer ID Application:", text); print(found.group(1) if found else "-")')
app=.build/DerivedData/Build/Products/Release/SimulatorGate.app
codesign --options runtime --timestamp=none --sign "$identity" "$app/Contents/XPCServices/SimulatorGateService.xpc"
codesign --options runtime --timestamp=none --sign "$identity" "$app"
codesign --verify --strict --verbose=2 "$app/Contents/XPCServices/SimulatorGateService.xpc"
codesign --verify --strict --verbose=2 "$app"
printf '試作のビルド・署名検査が完了しました。署名: %s\n' "$identity"
