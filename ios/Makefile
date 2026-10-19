# Makefile — convenience targets mirroring the CI steps in .github/workflows/ci.yml
#
# Prerequisites:
#   - XcodeGen installed (brew install xcodegen)
#   - Sibling Phlox repo checked out at ../Phlox on branch dev
#   - Xcode 16+ selected (xcode-select or xcodes)
#
# Usage:
#   make generate      — run xcodegen to regenerate the .xcodeproj
#   make build         — xcodebuild for the PhloxMobile scheme on iPhone 16 simulator
#   make run           — シミュレーターでデモ起動（モックデータ・一覧画面）
#   make run-live      — シミュレーターで本番フロー起動
#   make snapshot      — 単体テストで一覧・会話の PNG を書き出す
#   make test          — swift test on Packages/PhloxKit
#   make lint          — raw-value literal lint
#   make all           — generate → build → test → lint

SCHEME        := PhloxMobile
PACKAGE_PATH  := Packages/PhloxKit
LINT_SCRIPT   := scripts/lint-raw-values.sh
RUN_SCRIPT    := scripts/run-simulator.sh
# 注: $(shell) 内の括弧は make が対応を数えるため、未対応の `(` を含む grep パターンは使えない（sed の括弧は対で釣り合う）
SIMULATOR_ID  := $(shell xcrun simctl list devices available | sed -nE 's/^[[:space:]]*iPhone 16 \(([A-F0-9-]+)\).*/\1/p' | head -1)
# 注: name= 指定は OS:latest に解決され、複数ランタイム共存環境で失敗する（既知）。UDID で固定する。
DESTINATION   := platform=iOS Simulator,id=$(SIMULATOR_ID)
SNAPSHOT_SIMULATOR_ID ?= $(shell xcrun simctl list devices available | sed -nE 's/^[[:space:]]*iPhone[^()]*\(([A-F0-9-]+)\).*/\1/p' | head -1)
SNAPSHOT_ROOT ?= $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)/.verification/ios-redesign

.PHONY: all generate build run run-live snapshot test lint

all: generate build test lint

generate:
	xcodegen generate

build: generate
	xcodebuild build \
	  -scheme $(SCHEME) \
	  -destination '$(DESTINATION)' \
	  CODE_SIGNING_ALLOWED=NO \
	  | xcpretty || xcodebuild build -scheme $(SCHEME) -destination '$(DESTINATION)' CODE_SIGNING_ALLOWED=NO

run:
	bash $(RUN_SCRIPT)

run-live:
	bash $(RUN_SCRIPT) --live

# Render only the snapshot suite; interactive tests require a separate explicit request.
snapshot: generate
	TEST_RUNNER_PHLOX_DESIGN_SNAPSHOTS=1 \
	TEST_RUNNER_PHLOX_SNAPSHOT_DIR='$(SNAPSHOT_ROOT)/snapshots' \
	xcodebuild test \
	  -scheme PhloxMobileSnapshots \
	  -only-testing:PhloxMobileSnapshotTests/DesignSnapshotRenderTests \
	  -destination 'platform=iOS Simulator,id=$(SNAPSHOT_SIMULATOR_ID)' \
	  -derivedDataPath '$(SNAPSHOT_ROOT)/build' \
	  CODE_SIGNING_ALLOWED=NO

test:
	swift test --package-path $(PACKAGE_PATH)

lint:
	bash $(LINT_SCRIPT)
