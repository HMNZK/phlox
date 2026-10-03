#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build
/opt/homebrew/bin/xcodegen generate --spec project.yml
xcodebuild -project SimulatorInputHarness.xcodeproj -scheme SimulatorInputHarness -configuration Debug -derivedDataPath "$PWD/.build/DerivedData" build > .build/host-build.log 2>&1
xcodebuild -project SimulatorInputHarness.xcodeproj -scheme InputObserver -configuration Debug -sdk iphonesimulator -derivedDataPath "$PWD/.build/ObserverDerivedData" build > .build/observer-build.log 2>&1
codesign --verify --strict --verbose=2 .build/DerivedData/Build/Products/Debug/SimulatorInputHarness.app
printf '本番入力経路の確認用ビルドが完了しました。公証は行っていません。\n'
