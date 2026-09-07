#!/usr/bin/env bash
# 実AppUpdaterの初期化を検査する。Sparkleの開始入口だけを観測用に差し替える。
# 使用: compact-test updater-isolation bash <このファイル> [Sparkle.frameworkの絶対パス]
set -euo pipefail

FRAMEWORK="${1:-}"
MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROBE_DIR="$(mktemp -d /tmp/phlox-updater-probe.XXXXXX)"
cleanup() {
    /bin/rm -f "$PROBE_DIR/AppUpdater.swift" "$PROBE_DIR/Probe.swift" "$PROBE_DIR/Info.plist" "$PROBE_DIR/probe" "$PROBE_DIR/build-settings.log"
    /bin/rmdir "$PROBE_DIR"
}
trap cleanup EXIT

if [[ -z "$FRAMEWORK" ]]; then
    settings_exit=0
    xcodebuild -project "$MACOS_DIR/Phlox.xcodeproj" -scheme Phlox -configuration Debug \
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

xcrun swiftc -swift-version 6 -D DEBUG -parse-as-library \
    -F "$(dirname "$FRAMEWORK")" -framework Sparkle \
    -Xlinker -rpath -Xlinker "$(dirname "$FRAMEWORK")" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$PROBE_DIR/Info.plist" \
    "$PROBE_DIR/AppUpdater.swift" "$PROBE_DIR/Probe.swift" -o "$PROBE_DIR/probe"

failed=0
for preference in missing true false; do
    env -u PHLOX_DEFAULTS_SUITE "$PROBE_DIR/probe" 1 "$preference" || failed=1
    env PHLOX_DEFAULTS_SUITE= "$PROBE_DIR/probe" 1 "$preference" || failed=1
    env "PHLOX_DEFAULTS_SUITE=phlox.updater.suite.${PROBE_DIR##*.}" "$PROBE_DIR/probe" 0 "$preference" || failed=1
    env 'PHLOX_DEFAULTS_SUITE= ' "$PROBE_DIR/probe" 0 "$preference" || failed=1
done
exit "$failed"
