#!/usr/bin/env bash
# 実AppUpdaterの初期化を検査する。Sparkleの開始入口だけを観測用に差し替える。
# 使用: compact-test updater-isolation bash <このファイル> [Sparkle.frameworkの絶対パス]
set -euo pipefail

FRAMEWORK="${1:-}"
MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_DIR="$(dirname "$MACOS_DIR")"
mkdir -p "$PROJECT_DIR/.verification"
PROBE_DIR="$(mktemp -d "$PROJECT_DIR/.verification/updater-isolation.XXXXXX")"
BUILD_OUTPUT_DIR="${MANAGED_BUILD_DIR:-$PROBE_DIR/build}"
mkdir -p "$BUILD_OUTPUT_DIR" "$PROBE_DIR/temporary"
export TMPDIR="$PROBE_DIR/temporary/"
printf 'purpose=AppUpdater isolation test\nsession=%s\noutput=%s\nbuild_output=%s\npid=%s executable=%s\n' \
    "${PROBE_DIR##*/}" "$PROBE_DIR" "$BUILD_OUTPUT_DIR" "$$" "$BASH" > "$PROBE_DIR/ownership.txt"
cleanup() {
    local status=$?
    local trash_dir
    mkdir -p "$HOME/.Trash"
    trash_dir="$(mktemp -d "$HOME/.Trash/phlox-updater-isolation.XXXXXX")"
    mv "$PROBE_DIR" "$trash_dir/"
    return "$status"
}
trap cleanup EXIT

run_recorded() {
    "$@" &
    local pid=$!
    printf 'pid=%s command=' "$pid" >> "$PROBE_DIR/ownership.txt"
    printf ' %q' "$@" >> "$PROBE_DIR/ownership.txt"
    printf '\n' >> "$PROBE_DIR/ownership.txt"
    wait "$pid"
}

if [[ -z "$FRAMEWORK" ]]; then
    settings_exit=0
    run_recorded xcodebuild -project "$MACOS_DIR/Phlox.xcodeproj" -scheme Phlox -configuration Debug \
        -showBuildSettings -disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile \
        > "$PROBE_DIR/build-settings.log" 2>&1 || settings_exit=$?
    if [[ "$settings_exit" != 0 ]]; then cat "$PROBE_DIR/build-settings.log" >&2; exit "$settings_exit"; fi
    BUILD_DIR="$(awk '$1 == "BUILD_DIR" && $2 == "=" && !value { sub(/^.*= /, ""); value = $0 } END { print value }' "$PROBE_DIR/build-settings.log")"
    [[ "$BUILD_DIR" = /* ]] || { echo "BUILD_DIRを解決できません" >&2; exit 1; }
    FRAMEWORK="$(dirname "$(dirname "$BUILD_DIR")")/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
fi
[[ "$FRAMEWORK" = /* && -f "$FRAMEWORK/Sparkle" ]] || { echo "Sparkle実体が見つかりません: $FRAMEWORK" >&2; exit 1; }

# 宣言をコピーせず毎回製品から取る。開始条件そのものはテスト側へ転記しない。
awk '
  BEGIN { print "import Foundation\nimport Combine\nimport Sparkle" }
  /^final class AppUpdater: / {
    if (previous != "@MainActor") exit 1
    print previous; active = 1; found++
  }
  active { print }
  active && /^}$/ { active = 0 }
  { previous = $0 }
  END { if (found != 1 || active) exit 1 }
' "$MACOS_DIR/App/PhloxApp.swift" > "$PROBE_DIR/AppUpdater.swift"

# AppUpdaterの製品依存も正本を使う。AppBootstrap全体のリンクは不要。
awk '$0 != "import AppBootstrap" { print }' \
    "$MACOS_DIR/App/SessionRuntimeUpdateDelegate.swift" > "$PROBE_DIR/SessionRuntimeUpdateDelegate.swift"
cp "$MACOS_DIR/Packages/AppBootstrap/Sources/AppBootstrap/SessionRuntimeUpdateCompatibility.swift" \
    "$PROBE_DIR/SessionRuntimeUpdateCompatibility.swift"
awk '
  BEGIN { print "import Foundation" }
  /^public struct SessionRuntimeDiscovery: / { active = 1; found++ }
  active { print }
  active && /^}$/ { active = 0 }
  END { if (found != 1 || active) exit 1 }
' "$MACOS_DIR/Packages/AppBootstrap/Sources/AppBootstrap/SessionRuntimeBootstrap.swift" \
    > "$PROBE_DIR/SessionRuntimeDiscovery.swift"

cat > "$PROBE_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>phlox.updater.probe.${PROBE_DIR##*.}</string>
<key>CFBundleVersion</key><string>1</string>
<key>SUDefaultsDomain</key><string>phlox.updater.probe.${PROBE_DIR##*.}.sparkle</string>
</dict></plist>
PLIST

cat > "$PROBE_DIR/Probe.swift" <<'SWIFT'
import Foundation
import Combine
import Sparkle
import ObjectiveC

@main
struct Probe {
    @MainActor static var calls = 0

    @MainActor static func main() throws {
        exit(try run())
    }

    @MainActor static func run() throws -> Int32 {
        let domain = Bundle.main.bundleIdentifier ?? ""
        precondition(domain.hasPrefix("phlox.updater.probe."))
        let sparkleDomain = domain + ".sparkle"
        precondition(Bundle.main.object(forInfoDictionaryKey: "SUDefaultsDomain") as? String == sparkleDomain)
        let preference = CommandLine.arguments[2]
        precondition(["missing", "true", "false"].contains(preference))
        let initial: [String: Any] = preference == "missing" ? [:] : ["SUEnableAutomaticChecks": preference == "true"]
        UserDefaults.standard.setPersistentDomain(initial, forName: domain)
        UserDefaults.standard.setPersistentDomain(initial, forName: sparkleDomain)
        defer {
            UserDefaults.standard.removePersistentDomain(forName: domain)
            UserDefaults.standard.removePersistentDomain(forName: sparkleDomain)
        }
        guard let method = class_getInstanceMethod(
            SPUStandardUpdaterController.self, #selector(SPUStandardUpdaterController.startUpdater)
        ) else { fatalError("実Sparkleの開始入口を発見できません") }
        let record: @convention(block) (AnyObject) -> Void = { _ in
            MainActor.assumeIsolated { calls += 1 }
        }
        let replacement = imp_implementationWithBlock(record)
        let original = method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        let before = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
        let sparkleBefore = UserDefaults.standard.persistentDomain(forName: sparkleDomain) ?? [:]
        let updater = AppUpdater()
        let expected = Int(CommandLine.arguments[1])!
        return withExtendedLifetime(updater) {
            let after = UserDefaults.standard.persistentDomain(forName: domain) ?? [:]
            let sparkleAfter = UserDefaults.standard.persistentDomain(forName: sparkleDomain) ?? [:]
            guard NSDictionary(dictionary: before).isEqual(to: after),
                  NSDictionary(dictionary: sparkleBefore).isEqual(to: sparkleAfter) else {
                print("FAIL: 初期化が所有設定へ書き込みました")
                return 2
            }
            guard calls == expected else {
                print("FAIL: preference=\(preference), starts=\(calls), expected=\(expected)")
                return 1
            }
            print("PASS: preference=\(preference), starts=\(calls)")
            return 0
        }
    }
}
SWIFT

run_recorded xcrun swiftc -swift-version 6 -D DEBUG -parse-as-library \
    -module-cache-path "$BUILD_OUTPUT_DIR/module-cache" \
    -F "$(dirname "$FRAMEWORK")" -framework Sparkle \
    -Xlinker -rpath -Xlinker "$(dirname "$FRAMEWORK")" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PROBE_DIR/Info.plist" \
    "$PROBE_DIR/AppUpdater.swift" "$PROBE_DIR/SessionRuntimeUpdateDelegate.swift" \
    "$PROBE_DIR/SessionRuntimeUpdateCompatibility.swift" "$PROBE_DIR/SessionRuntimeDiscovery.swift" \
    "$PROBE_DIR/Probe.swift" -o "$BUILD_OUTPUT_DIR/probe"

failed=0
for preference in missing true false; do
    run_recorded env -u PHLOX_DEFAULTS_SUITE "$BUILD_OUTPUT_DIR/probe" 1 "$preference" || failed=1
    run_recorded env PHLOX_DEFAULTS_SUITE= "$BUILD_OUTPUT_DIR/probe" 1 "$preference" || failed=1
    run_recorded env "PHLOX_DEFAULTS_SUITE=phlox.updater.suite.${PROBE_DIR##*.}" "$BUILD_OUTPUT_DIR/probe" 0 "$preference" || failed=1
    run_recorded env 'PHLOX_DEFAULTS_SUITE= ' "$BUILD_OUTPUT_DIR/probe" 0 "$preference" || failed=1
done
exit "$failed"
